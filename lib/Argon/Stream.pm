#-------------------------------------------------------------------------------
# Argon::Stream manages an input and output handle (see Coro::Handle), making it
# far simpler to send and receive messages.
#-------------------------------------------------------------------------------
package Argon::Stream;

use strict;
use warnings;
use Carp          qw/carp croak cluck confess/;

use Moose;
use MooseX::StrictConstructor;

use Coro;
use Coro::AnyEvent;
use Coro::Channel;
use Coro::Handle   qw/unblock/;
use IO::Socket     qw/SOCK_STREAM/;
use Socket         qw/getnameinfo NI_NUMERICSERV/;
use Argon          qw/:logging :commands/;
use Argon::Message;

#-------------------------------------------------------------------------------
# Flag set to true when connected.
#-------------------------------------------------------------------------------
has 'is_connected' => (
    is        => 'rw',
    isa       => 'Int',
    default   => 1,
);

#-------------------------------------------------------------------------------
# Input channel
#-------------------------------------------------------------------------------
has 'in_chan' => (
    is        => 'ro',
    isa       => 'Coro::Handle',
    trigger   => \&trigger_in_chan,
    predicate => 'has_in_chan',
);

#-------------------------------------------------------------------------------
# Output channel
#-------------------------------------------------------------------------------
has 'out_chan' => (
    is        => 'ro',
    isa       => 'Coro::Handle',
    clearer   => 'unset_out_chan',
    predicate => 'has_out_chan',
);

#-------------------------------------------------------------------------------
# Queue of messages that have come in from the input channel
#-------------------------------------------------------------------------------
has 'inbox' => (
    is        => 'rw',
    isa       => 'Coro::Channel',
    init_arg  => undef,
    clearer   => 'clear_inbox',
    handles   => {
        receive => 'get',
    }
);

#-------------------------------------------------------------------------------
# Tracks messages that have been sent out using send().
#-------------------------------------------------------------------------------
has 'pending' => (
    is       => 'ro',
    isa      => 'HashRef[Coro::Channel]',
    init_arg => undef,
    default  => sub {{}},
    traits   => ['Hash'],
    handles  => {
        set_pending => 'set',
        get_pending => 'get',
        del_pending => 'delete',
        has_pending => 'exists',
        all_pending => 'keys',
    }
);

#-------------------------------------------------------------------------------
# CLASS METHOD:
# Connects to a remote host and creates a new Stream object. Accepts two named
# parameters, 'host' and 'port'. Returns the new stream object.
#-------------------------------------------------------------------------------
sub connect {
    my ($class, %param) = @_;
    my $host = $param{host} || croak 'expected host';
    my $port = $param{port} || croak 'expected port';

    my $sock = IO::Socket::INET->new(
        PeerHost => $host,
        PeerPort => $port,
        Proto    => 'tcp',
        Type     => SOCK_STREAM,
    ) or croak $!;

    my $handle = unblock $sock;
    return $class->new(
        in_chan  => $handle,
        out_chan => $handle,
    );
}

#-------------------------------------------------------------------------------
# Creates a new stream using a single handle as both input and output channels.
#-------------------------------------------------------------------------------
sub create {
    my ($class, $handle) = @_;
    $handle = unblock($handle) unless $handle->isa('Coro::Handle');
    $class->new(
        in_chan  => $handle,
        out_chan => $handle,
    );
}

#-------------------------------------------------------------------------------
# Class method: returns true if an error message represents a connection error.
#-------------------------------------------------------------------------------
sub is_connection_error {
    my $msg = shift;
    return $msg =~ /disconnected/
        || $msg =~ /Connection reset by peer/
        || $msg =~ /Broken pipe/
        || $msg =~ /Bad file descriptor/;
}

#-------------------------------------------------------------------------------
# Trigger (in_chan): starts a thread that watches for new messages while the
# stream is connected.
#-------------------------------------------------------------------------------
sub trigger_in_chan {
    my ($self, $in_chan, $old_in_chan) = @_;
    if (defined $in_chan) {
        $self->inbox(Coro::Channel->new());
        $self->poll_loop;
    } else {
        $self->is_connected(0);
    }
}

#-------------------------------------------------------------------------------
# Polls the file handle for new messages and adds them to the appropriate
# channel (inbox or pending). Handles the special case of PING requests.
#-------------------------------------------------------------------------------
sub poll_loop {
    my ($self) = @_;
    async {
        while ($self->is_connected) {
            my $line = $self->in_chan->readline($Argon::EOL);
            last unless defined $line;

            do { local $/ = $Argon::EOL; chomp $line; };
            my $msg = Argon::Message::decode($line);

            if ($msg->command == CMD_PING) {
                $self->send_message($msg->reply(CMD_ACK));
            } elsif ($self->has_pending($msg->id)) {
                $self->get_pending($msg->id)->put($msg);
            } else {
                $self->inbox->put($msg);
            }
        }

        $self->close;
    };
}

#-------------------------------------------------------------------------------
# Sends a ping across the stream and waits for an acknowledgement.
#-------------------------------------------------------------------------------
sub ping {
    my $self  = shift;
    my $start = time;
    my $ping  = Argon::Message->new(command => CMD_PING);
    my $reply = $self->send($ping);
    return unless defined $reply;
    return time - $start;
}

#-------------------------------------------------------------------------------
# Launches a coro that perpetually pings the loop. Returns control to $on_fail
# should the connection be interrupted.
#-------------------------------------------------------------------------------
sub monitor {
    my ($self, $on_fail) = @_;
    async {
        while ($self->is_connected) {
            my $ping = $self->ping;
            last unless defined $ping;
            Coro::AnyEvent::sleep $Argon::POLL_INTERVAL;
        }

        $self->is_connected(0);
        $on_fail->($self, $!);
    };
}

#-------------------------------------------------------------------------------
# Returns a string representing the first defined of <in-channel|out-channel>.
#-------------------------------------------------------------------------------
sub address {
    my $self = shift;
    return '<not connected>' unless $self->is_connected;

    my $handle
        = defined $self->in_chan  ? $self->in_chan
        : defined $self->out_chan ? $self->out_chan
        : undef;

    if (defined $handle) {
        if ($handle->can('peername')) {
            my $host = $handle->peerhost;
            my $port = $handle->peerport;
            return sprintf('sock<%s:%s @%d>', $host, $port, $self);
        }
        elsif (defined $self->handle) {
            return sprintf('file<fd:%s @%d>', $handle->fileno, $self);
        }
    } else {
        return sprintf('none<%s>', $self);
    }
}

#-------------------------------------------------------------------------------
# Sends a message and returns the reply.
#-------------------------------------------------------------------------------
sub send {
    my ($self, $msg) = @_;
    croak 'not connected'                unless $self->is_connected;
    croak 'no output channel configured' unless $self->has_out_chan;
    croak 'no input channel configured'  unless $self->has_in_chan;
    $self->set_pending($msg->id, Coro::Channel->new(1));
    $self->send_message($msg);
    return $self->get_response($msg->id);
}

#-------------------------------------------------------------------------------
# Reads messages off of the wire and sets them complete until the desired
# message's reply becomes available. Returns the reply.
#-------------------------------------------------------------------------------
sub get_response {
    my ($self, $msg_id) = @_;
    croak 'not connected' unless $self->is_connected;
    croak 'no input channel configured' unless $self->has_in_chan;
    croak sprintf('dead lock detected: msg %s not pending', $msg_id)
        unless $self->has_pending($msg_id);

    my $reply = $self->get_pending($msg_id)->get;
    $self->del_pending($msg_id);

    croak $! if $reply == 0;
    return $reply;
}

#-------------------------------------------------------------------------------
# Writes a single message to the socket. Returns the number of bytes read.
#-------------------------------------------------------------------------------
sub send_message {
    my ($self, $msg) = @_;
    croak 'not connected' unless $self->is_connected;
    croak 'no output channel configured' unless $self->has_out_chan;
    $self->out_chan->print($msg->encode . $Argon::EOL);
}

#-------------------------------------------------------------------------------
# Closes the socket and marks stream as disconnected.
#-------------------------------------------------------------------------------
sub close {
    my $self = shift;
    $self->is_connected(0);

    $self->inbox->shutdown # wake anyone waiting on a message
        if defined $self->inbox;

    if (defined $self->in_chan) {
        close $self->in_chan->fh;
    }

    if (defined $self->out_chan) {
        close $self->out_chan->fh;
    }

    foreach my $msgid ($self->all_pending) {
        $self->get_pending($msgid)->put(0);
        $self->del_pending($msgid);
    }
}

#-------------------------------------------------------------------------------
# Ensures that sockets are cleaned up when stream is destroyed.
#-------------------------------------------------------------------------------
sub DEMOLISH {
    my $self = shift;
    $self->close;
}

;
__PACKAGE__->meta->make_immutable;

1;

=pod

=head1 NAME

Argon::Stream

=head1 SYNOPSIS

    use Coro::Handle;
    use Argon::Stream;

    # Create a stream manually
    my $stream = Argon::Stream->new(
        in_chan  => unblock(*STDIN),
        out_chan => unblock(*STDOUT),
    );

    # Create stream by directly connecting to a remote host
    my $stream = Argon::Stream->connect(host => 'someserver', port => 8888);

    # Create stream from a single existing 2-way channel (e.g. a socket)
    my $stream = Argon::Stream->create($sock);

    # Send a message and wait for a response (yields to Coro loop).
    my $reply = $stream->send($msg);

    # Send a message manually
    $stream->send_message($msg);

    # Get the reply
    my $reply = $stream->receive;

    # Disconnect
    $stream->close;

=head1 DESCRIPTION

Argon::Stream wraps an input and output handle to make sending and receiving
messages easier. It also facilitates some of the monitoring between
Argon::Cluster and Argon::Node objects.

=head1 METHDOS

=head2 new(in_chan => Coro::Handle, out_chan => Coro::Handle)

Creates a new Argon::Stream using two Coro::Handle objects. Note that neither
handle is required, allowing unidirectional streams to be created.

=head2 create(IO::Handle)

Creates a new Argon::Stream using a single, bidirectional IO::Handle object.

=head2 connect(host => 'someserver', port => 8888)

Creates a new Argon::Stream by connecting directly to a remote host.

=head2 monitor($on_fail)

Begins monitoring the channel for connectivity. WARNING: this method assumes
that the other end of the connection is controlled by an Argon::Stream as well.
If connectivity breaks, subroutine $on_fail is triggered with two arguments: the
stream object and the error message.

=head2 address()

Returns the address of this stream. Note that this is NOT just the URL or IP
address. Since the stream is composed of (possibly) two handles, this is simply
an identifier that may be used to uniquely identify the stream as well as to
create a human-readable description of it.

=head2 send_message($msg)

Sends an Argon::Message. Croaks if not connected or if the output handle has not
been configured.

=head2 receive()

Blocks until the next Argon::Message is available on the stream. Croaks if an
input handle has not been configured.

=head2 send($msg)

Sends an Argon::Message and returns the response (another Argon::Message).
Blocks until the response is available. Croaks if either the output or input
handles have not been configured.

=head2 close()

Closes and disconnects the stream. The instance is not left in a useable or
reconnectable state.

=head1 AUTHOR

Jeff Ober L<mailto:jeffober@gmail.com>

=head1 LICENSE

BSD license

=cut
