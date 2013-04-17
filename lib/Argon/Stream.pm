package Argon::Stream;

use strict;
use warnings;
use Carp;

use Moose;
use MooseX::StrictConstructor;

use Coro;
use Coro::AnyEvent;
use Coro::Channel;
use IO::Socket::INET;
use AnyEvent;
use AnyEvent::Util qw//;
use AnyEvent::Util qw//;
use Socket         qw/getnameinfo NI_NUMERICSERV/;
use Errno          qw/EWOULDBLOCK/;
use Argon          qw/:logging :commands/;
use Argon::Message;

has 'in_fh' => (
    is       => 'ro',
    isa      => 'FileHandle',
    clearer  => 'unset_in_fh',
    trigger  => \&watch_fh,
);

has 'out_fh' => (
    is       => 'ro',
    isa      => 'FileHandle',
    clearer  => 'unset_out_fh',
);

has 'buffer' => (
    is       => 'rw',
    isa      => 'Str',
    default  => '',
    init_arg => undef,
);

has 'offset' => (
    is       => 'rw',
    isa      => 'Int',
    default  => 0,
    init_arg => undef,
    traits   => ['Counter'],
    handles  => {
        'inc_offset' => 'inc',
        'dec_offset' => 'dec',
    });

has 'is_connected' => (
    is       => 'rw',
    isa      => 'Int',
    default  => 1,
    init_arg => undef,
);

has 'error' => (
    is       => 'rw',
    isa      => 'Str',
    default  => '',
    init_arg => undef,
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
# Returns true if an error message represents a connection error.
#-------------------------------------------------------------------------------
sub is_connection_error {
    my $msg = shift;
    return $msg =~ /connection was closed/
        || $msg =~ /Connection reset by peer/
        || $msg =~ /Broken pipe/;
}

#-------------------------------------------------------------------------------
# Trigger (in_fh): starts a thread that watches for new messages while the
# stream is connected.
#-------------------------------------------------------------------------------
sub watch_fh {
    my ($self, $fh, $old_fh) = @_;

    if (defined $fh) {
        AnyEvent::Util::fh_nonblocking $fh, 1;
        $self->inbox(Coro::Channel->new());
        $self->is_connected(1);

        my $fd = $self->in_fh->fileno;
        $self->poll_fh($fd);
    }
}

#-------------------------------------------------------------------------------
# Polls the file handle for new messages and adds them to the appropriate
# channel (inbox or pending). Handles the special case of PING requests.
#-------------------------------------------------------------------------------
sub poll_fh {
    my ($self, $fd) = @_;
    async {
        while ($self->is_connected) {
            my $msg = eval { $self->read_message };

            if ($@) {
                WARN('(%d) Connection: %s', $fd, $@)
                    unless is_connection_error($@);
                last;
            }
            
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
    my $addr = $self->address;

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
# Returns the host:port of the connected socket as a string. Returns the string
# <not connected> if there is no active connection.
#-------------------------------------------------------------------------------
sub address {
    my $self = shift;
    
    my $fh
        = defined $self->out_fh ? $self->out_fh
        : defined $self->in_fh  ? $self->in_fh
        : undef;
    
    if ($self->is_connected
     && $fh->isa('IO::Socket::INET')
     && $fh->can('peername'))
    {
        my ($err, $host, $port) = getnameinfo($fh->peername, NI_NUMERICSERV);
        return sprintf('%s:%s', $host, $port);
    } elsif (defined $fh) {
        return sprintf('fh:%s', $fh->fileno);
    } else {
        return sprintf('%s', $self);
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

    AnyEvent::Util::fh_nonblocking $sock, 1;

    Coro::AnyEvent::writable($sock);
    return $class->new(in_fh => $sock, out_fh => $sock);
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
    croak $self->error unless $self->is_connected;
    Coro::AnyEvent::writable($self->out_fh);

    # Note: must check again for connection after sleeping until writable
    croak $self->error unless $self->is_connected;

    my $bytes = syswrite($self->out_fh, $msg->encode . $Argon::EOL);

    if (!defined $bytes) {
        $self->close_with_error($!);
    } elsif ($bytes == 0) {
        $self->close_with_error('connection was closed');
    }

    return $bytes;
}

#-------------------------------------------------------------------------------
# Reads a chunk of data from the socket. Returns the number of bytes read.
#-------------------------------------------------------------------------------
sub read_chunk {
    my $self = shift;
    croak $self->error unless $self->is_connected;

    my $bytes = sysread(
        $self->in_fh,
        $self->{buffer},
        $Argon::CHUNK_SIZE,
        $self->offset,
    );

    if (!defined $bytes) {
        return if $! == EWOULDBLOCK;
        $self->close_with_error($!);
    } elsif ($bytes == 0) {
        $self->close_with_error('connection was closed');
    } else {
        $self->inc_offset($bytes);
    }

    return $bytes;
}

#-------------------------------------------------------------------------------
# Reads the next available message from the socket and returns it.
#-------------------------------------------------------------------------------
sub read_message {
    my ($self, %param) = @_;
    my $eol = $param{eol} || $Argon::EOL;

    my $eol_index = -1;
    while ($eol_index == -1) {
        $eol_index = index($self->{buffer}, $eol);

        if ($eol_index == -1) {
            Coro::AnyEvent::readable($self->in_fh);
            $self->read_chunk;
        }

        unless ($self->is_connected) {
            croak $self->error;
        }
    }

    my $line   = substr($self->{buffer}, 0, $eol_index);
    my $offset = $eol_index + length($eol);

    substr($self->{buffer}, 0, $offset) = '';
    $self->dec_offset($offset);

    my $msg = Argon::Message::decode($line);

    return $msg;
}

#-------------------------------------------------------------------------------
# Closes the socket and marks stream as disconnected.
#-------------------------------------------------------------------------------
sub close {
    my $self = shift;
    $self->is_connected(0);

    if (defined $self->in_fh) {
        $self->in_fh->close;
        $self->unset_in_fh;
    }
    
    if (defined $self->out_fh) {
        $self->out_fh->close;
        $self->unset_out_fh;
    }

    foreach my $msgid ($self->all_pending) {
        $self->get_pending($msgid)->put(0);
        $self->del_pending($msgid);
    }
}

#-------------------------------------------------------------------------------
# Closes the stream and records an error.
#-------------------------------------------------------------------------------
sub close_with_error {
    my ($self, $error) = @_;
    $self->error($error);
    $self->close;
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
