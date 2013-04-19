package Argon::Stream;

use strict;
use warnings;
use Carp;

use Moose;
use MooseX::StrictConstructor;

use Coro;
use Coro::AnyEvent;
use Coro::Channel;
use AnyEvent;
use AnyEvent::Util qw//;
use IO::Socket     qw/SOCK_STREAM/;
use Argon          qw/:logging :commands/;
use Argon::Message;
use Argon::IO::InChannel;
use Argon::IO::OutChannel;

has 'is_connected' => (
    is       => 'rw',
    isa      => 'Int',
    default  => 0,
);

has 'in_chan' => (
    is       => 'ro',
    isa      => 'Argon::IO::InChannel',
    clearer  => 'unset_in_chan',
    trigger  => \&watch_in_chan,
);

has 'out_chan' => (
    is       => 'ro',
    isa      => 'Argon::IO::OutChannel',
    clearer  => 'unset_out_chan',
);

has 'inbox' => (
    is       => 'rw',
    isa      => 'Coro::Channel',
    init_arg => undef,
    handles  => {
        next_message => 'get',
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

sub fh {
    my ($self, $fh) = @_;

    if (defined $fh) {
        $self->in_fh($fh);
        $self->out_fh($fh);
    }

    return ($self->in_fh, $self->out_fh);
}

#-------------------------------------------------------------------------------
# Class method: returns true if an error message represents a connection error.
#-------------------------------------------------------------------------------
sub is_connection_error {
    my $msg = shift;
    return $msg =~ /disconnected/
        || $msg =~ /Connection reset by peer/
        || $msg =~ /Broken pipe/;
}

#-------------------------------------------------------------------------------
# Trigger (in_chan): starts a thread that watches for new messages while the
# stream is connected.
#-------------------------------------------------------------------------------
sub watch_in_chan {
    my ($self, $in_chan, $old_in_chan) = @_;
    if (defined $in_chan) {
        $self->inbox(Coro::Channel->new());
        $self->is_connected(1);
        $self->poll_fh;
    }
}

#-------------------------------------------------------------------------------
# Polls the file handle for new messages and adds them to the appropriate
# channel (inbox or pending). Handles the special case of PING requests.
#-------------------------------------------------------------------------------
sub poll_fh {
    my ($self) = @_;
    async {
        while ($self->is_connected) {
            my $line = $self->in_chan->receive;

            unless (defined $line && $self->in_chan->is_connected) {
                WARN('Connection error: %s', $self->in_chan->last_error)
                    unless is_connection_error($self->in_chan->last_error);
                last;
            }

            my $msg = Argon::Message::decode($line);

            if ($msg->command == CMD_PING) {
                $self->send_message($msg->reply(CMD_ACK));
            } elsif ($self->has_pending($msg->id)) {
                $self->get_pending($msg->id)->put($msg);
            } else {
                $self->inbox->put($msg);
            }
        }

        $self->inbox->shutdown;
        $self->is_connected(0);
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
    return time - $start;
}

#-------------------------------------------------------------------------------
# Launches a coro that perpetually pings the loop. Returns control to $on_fail
# should the connection be interrupted.
#-------------------------------------------------------------------------------
sub monitor {
    my ($self, $on_fail) = @_;
    async {
        while (1) {
            my $ping = eval { $self->ping };
            if ($@) {
                $on_fail->($self, $@);
                last;
            } else {
                Coro::AnyEvent::sleep $Argon::POLL_INTERVAL;
            }
        }
    };
}

#-------------------------------------------------------------------------------
# Returns a string representing the first defined of <in-channel|out-channel>.
#-------------------------------------------------------------------------------
sub address {
    my $self = shift;
    return
        defined $self->in_chan ? $self->in_chan->address
      : defined $self->out_chan ? $self->out_chan->address
      : '<not connected>';
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

    AnyEvent::Util::fh_nonblocking $sock, 1;
    Coro::AnyEvent::writable($sock);
    
    my $in_chan  = Argon::IO::InChannel->new(handle => $sock);
    my $out_chan = Argon::IO::OutChannel->new(handle => $sock);

    return $class->new(in_chan => $in_chan, out_chan => $out_chan);
}

#-------------------------------------------------------------------------------
# Creates a new stream using a single handle as both input and output channels.
#-------------------------------------------------------------------------------
sub create {
    my ($class, $handle) = @_;
    return $class->new(
        in_chan  => Argon::IO::InChannel->new(handle => $handle),
        out_chan => Argon::IO::OutChannel->new(handle => $handle),
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
    croak $self->in_chan->error unless $self->in_chan->is_connected;
    croak sprintf('dead lock detected: msg %s not pending', $msg_id)
        unless $self->has_pending($msg_id);

    my $reply = $self->get_pending($msg_id)->get;
    $self->del_pending($msg_id);

    croak $self->error if $reply == 0;
    return $reply;
}

#-------------------------------------------------------------------------------
# Writes a single message to the socket. Returns the number of bytes read.
#-------------------------------------------------------------------------------
sub send_message {
    my ($self, $msg) = @_;
    croak $self->out_chan->error unless $self->out_chan->is_connected;
    $self->out_chan->send($msg->encode . $Argon::EOL);
}

#-------------------------------------------------------------------------------
# Closes the socket and marks stream as disconnected.
#-------------------------------------------------------------------------------
sub close {
    my $self = shift;
    $self->is_connected(0);

    if (defined $self->in_chan) {
        $self->unset_in_chan;
    }
    
    if (defined $self->out_chan) {
        $self->unset_out_chan;
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

no Moose;
__PACKAGE__->meta->make_immutable;

1;
