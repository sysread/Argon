#-------------------------------------------------------------------------------
#
#-------------------------------------------------------------------------------
package Argon::Stream2;

use Moose;
use MooseX::AttributeShortcuts;
use MooseX::StrictConstructor;

use Carp;
use AnyEvent;
use AnyEvent::Handle;
use IO::Socket::INET;
use Socket qw(:all);

use Argon qw(K :logging :commands);


#-------------------------------------------------------------------------------
# Callback triggered when a new message arrives via the inchan for which there
# is no other callback (e.g. it was not sent using 'send').
#-------------------------------------------------------------------------------
has on_message => (
    is => 'rwp',
    isa => 'CodeRef',
    required => 1,
    traits => ['Code'],
    handles => {
        signal_message => 'execute',
    }
);

#-------------------------------------------------------------------------------
# Callback triggered when the other end of the connection is closed or an error
# which is considered fatal to the connection occurs.
#-------------------------------------------------------------------------------
has on_close => (
    is => 'rwp',
    isa => 'CodeRef',
    required => 1,
    traits => ['Code'],
    handles => {
        signal_close => 'execute',
    }
);

#-------------------------------------------------------------------------------
# Stores the timer object that pings the remote host whenevever an outchan is
# present.
#-------------------------------------------------------------------------------
has monitor => (
    is => 'rwp',
    init_arg => undef,
);

#-------------------------------------------------------------------------------
# An AnyEvent::Handle monitoring an IO::Handle used for input.
#-------------------------------------------------------------------------------
has inchan => (
    is => 'rwp',
    isa => 'AnyEvent::Handle',
    clearer => '_clear_inchan',
    predicate => 'can_read',
    trigger => \&_trigger_inchan,
);

sub _trigger_inchan {
    my ($self, $handle) = @_;
    $handle->on_error(K('_on_error', $self));
    $handle->on_eof(K('_on_eof', $self));
    $self->schedule_read;
}

#-------------------------------------------------------------------------------
# An AnyEvent::Handle monitoring an IO::Handle used for output.
#-------------------------------------------------------------------------------
has outchan => (
    is => 'rwp',
    isa => 'AnyEvent::Handle',
    clearer => '_clear_outchan',
    predicate => 'can_write',
    trigger => \&_trigger_outchan,
);

sub _trigger_outchan {
    my ($self, $handle) = @_;
    $handle->on_error(K('_on_error', $self));
    $handle->on_eof(K('_on_eof', $self));
    $self->_set_monitor(
        AnyEvent->timer(
            after    => $Argon::POLL_INTERVAL,
            interval => $Argon::POLL_INTERVAL,
            cb       => K('_ping', $self),
        )
    );
}

#-------------------------------------------------------------------------------
# Tracks messages that have been sent out using send().
#-------------------------------------------------------------------------------
has pending => (
    is       => 'ro',
    isa      => 'HashRef[CodeRef]',
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
# Creates a new Stream using a single IO::Handle for both input and output.
#-------------------------------------------------------------------------------
sub create {
    my ($class, $fh, %param) = @_;
    return $class->new(
        %param,
        inchan  => AnyEvent::Handle->new(fh => $fh),
        outchan => AnyEvent::Handle->new(fh => $fh),
    );
}

#-------------------------------------------------------------------------------
# Connects to a remote host (synchronously) and returns a Stream object using
# the socket connection for both input and output.
#-------------------------------------------------------------------------------
sub connect {
    my ($class, %param) = @_;
    my $host = delete $param{host} || croak 'expected host';
    my $port = delete $param{port} || croak 'expected port';

    my $sock = IO::Socket::INET->new(
        PeerHost => $host,
        PeerPort => $port,
        Proto    => 'tcp',
        Type     => SOCK_STREAM,
    ) or croak $!;

    return $class->create($sock, %param);
}

#-------------------------------------------------------------------------------
# Internally used method when an error or occurs on the input or output handle.
#-------------------------------------------------------------------------------
sub _on_error {
    my ($self, $handle, $fatal, $msg) = @_;
    $self->close;
}

#-------------------------------------------------------------------------------
# Internally used method when an eof (disconnect) occurs on the input or output
# handle.
#-------------------------------------------------------------------------------
sub _on_eof {
    my ($self, $handle) = @_;
    $self->close;
}

#-------------------------------------------------------------------------------
# Triggered when a new line of data is available on the input handle. The
# callback is registered in schedule_read.
#-------------------------------------------------------------------------------
sub _on_line {
    my ($self, $handle, $line, $eol) = @_;
    return unless $self->is_connected;

    my $msg = eval { Argon::Message::decode($line) };
    if ($@) {
        ERROR 'Error decoding message: %s', $@;
        $self->close;
        return;
    }

    if ($msg->command == CMD_PING) {
        $self->write($msg->reply(CMD_ACK));
    } elsif ($self->has_pending($msg->id)) {
        my $cb = $self->get_pending($msg->id);
        $self->del_pending($msg->id);
        $cb->($msg);
    } else {
        $self->signal_message($msg);
    }

    $self->schedule_read;
}

#-------------------------------------------------------------------------------
# Sends a CMD_PING message to the remote host. This should trigger an error if
# the output channel is disconnected.
#-------------------------------------------------------------------------------
sub _ping {
    my $self = shift;
    my $msg  = Argon::Message->new(command => CMD_PING);
    $self->write($msg);
}

#-------------------------------------------------------------------------------
# Returns true if either and input or output handle are present and have not
# triggered any errors.
#-------------------------------------------------------------------------------
sub is_connected {
    my $self = shift;
    return $self->can_read || $self->can_write;
}

#-------------------------------------------------------------------------------
# Registers the input handle to be monitored for read events and data buffered
# until an $Argon::EOL is reached, at which point '_on_line' is triggered for
# the line of text (which ultimately re-schedules another read via this
# method). Croaks if not connected or not input handle is set.
#-------------------------------------------------------------------------------
sub schedule_read {
    my $self = shift;
    croak 'no input channel' unless $self->can_read;
    croak 'not connected'    unless $self->is_connected;
    $self->inchan->push_read(line => $Argon::EOL, K('_on_line', $self));
}

#-------------------------------------------------------------------------------
# Writes the encoded message to the output channel. Croaks if not connected or
# no output handle is set.
#-------------------------------------------------------------------------------
sub write {
    my ($self, $msg) = @_;
    croak 'no output channel' unless $self->can_write;
    croak 'not connected'     unless $self->is_connected;
    $self->outchan->push_write($msg->encode . $Argon::EOL);
}

#-------------------------------------------------------------------------------
# Sends a message and triggers a callback when the message's reply (identified
# by the message id) is received.
#-------------------------------------------------------------------------------
sub send {
    my ($self, $msg, $cb) = @_;
    $self->set_pending($msg->id, $cb);
    $self->write($msg);
}

#-------------------------------------------------------------------------------
# Closes the connection and triggers the close callback.
#-------------------------------------------------------------------------------
sub close {
    my $self = shift;
    return unless $self->is_connected;
    $self->signal_close($self);
    $self->_clear_inchan;
    $self->_clear_outchan;
}


no Moose;
1;
