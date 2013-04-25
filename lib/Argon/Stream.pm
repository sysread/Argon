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

has 'is_connected' => (
    is       => 'rw',
    isa      => 'Int',
    default  => 1,
);

has 'in_chan' => (
    is       => 'ro',
    isa      => 'Coro::Handle',
    trigger  => \&trigger_in_chan,
);

has 'out_chan' => (
    is       => 'ro',
    isa      => 'Coro::Handle',
    clearer  => 'unset_out_chan',
);

has 'inbox' => (
    is        => 'rw',
    isa       => 'Coro::Channel',
    init_arg  => undef,
    clearer   => 'clear_inbox',
    handles   => {
        receive => 'get',
    }
);

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
            #INFO 'RECV [%s]: [%s]', $self->address, $line;

            my $msg = Argon::Message::decode($line);

            if ($msg->command == CMD_PING) {
                $self->send_message($msg->reply(CMD_ACK));
            } elsif ($self->has_pending($msg->id)) {
                $self->get_pending($msg->id)->put($msg);
            } else {
                $self->inbox->put($msg);
            }
        }

        $self->is_connected(0);
        $self->close;
        $self->inbox->shutdown;
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
# Sends a message and waits for the response. If the message is rejected,
# continues to resend the message after longer and longer delays until it is
# accepted.
#-------------------------------------------------------------------------------
sub send_retry {
    my ($self, $msg) = @_;
    my $attempts = 0;

    while (1) {
        ++$attempts;
        my $reply = $self->send($msg);

        # If the task was rejected, sleep a short (but lengthening) amount of
        # time before attempting again.
        if ($reply->command == CMD_REJECTED) {
            my $sleep_time = log($attempts + 1) / log(10);
            Coro::AnyEvent::sleep($sleep_time);
        }
        else {
            return $reply;
        }
    }
}

#-------------------------------------------------------------------------------
# Sends a message and returns the reply.
#-------------------------------------------------------------------------------
sub send {
    my ($self, $msg) = @_;
    croak 'not connected' unless $self->is_connected;
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
    #INFO 'SEND [%s]: [%s]', $self->address, $msg->encode;
    $self->out_chan->print($msg->encode . $Argon::EOL);
}

#-------------------------------------------------------------------------------
# Closes the socket and marks stream as disconnected.
#-------------------------------------------------------------------------------
sub close {
    my $self = shift;
    $self->is_connected(0);

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

    $self->inbox->shutdown; # wake anyone waiting on a message
}

#-------------------------------------------------------------------------------
# Ensures that sockets are cleaned up when stream is destroyed.
#-------------------------------------------------------------------------------
sub DEMOLISH {
    my $self = shift;
    $self->close;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
