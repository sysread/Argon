package Argon::Role::MessageServer;

use Moose::Role;
use Carp;
use namespace::autoclean;
use Argon qw/:commands :statuses LOG EOL CHUNK_SIZE/;
use Argon::MessageProcessor;

requires 'msg_accept';
requires 'status';

# Maps local msg status to a CMD_* reply (for msg_status)
my %STATUS_MAP = (
    STATUS_QUEUED,   CMD_PENDING,
    STATUS_ASSIGNED, CMD_PENDING,
    STATUS_COMPLETE, CMD_COMPLETE,
);

has 'endline' => (
    is      => 'ro',
    isa     => 'Str',
    default => EOL,
);

has 'chunk_size' => (
    is      => 'ro',
    isa     => 'Int',
    default => CHUNK_SIZE,
);

# Instance of Argon::Server used to accept messages
has 'server' => (
    is       => 'ro',
    isa      => 'Argon::Server',
    required => 1,
);

#-------------------------------------------------------------------------------
# Configures the server, mapping commands to local methods.
#-------------------------------------------------------------------------------
sub BUILD {}
after 'BUILD' => sub {
    my $self = shift;
    $self->server->respond_to(CMD_QUEUE,  sub { $self->reply_queue(@_)  });
    $self->server->respond_to(CMD_STATUS, sub { $self->reply_status(@_) });
};

#-------------------------------------------------------------------------------
# Replies to request to accept/queue a new message.
#-------------------------------------------------------------------------------
sub reply_queue {
    my ($self, $msg) = @_;
    my $accepted = eval { $self->msg_accept($msg) };
    if ($@) {
        my $error = $@;
        LOG("Error accepting message %s: %s", $msg->id, $error);
        my $reply = $msg->reply(CMD_REJECTED);
        $reply->set_payload($error);
        return $reply;
    } else {
        LOG("Message accepted: %s", $msg->id);
        my $reply = $msg->reply($accepted ? CMD_ACK : CMD_REJECTED);
        return $reply;
    }
}

#-------------------------------------------------------------------------------
# Replies with the current message status (pending, complete, etc.)
#-------------------------------------------------------------------------------
sub reply_status {
    my ($self, $msg) = @_;
    LOG("Message status: %s => %d", $msg->id, $self->status->{$msg->id});
    if (exists $self->status->{$msg->id}) {
        if ($self->status->{$msg->id} eq STATUS_COMPLETE) {
            return $self->msg_clear($msg);
        } else {
            return $msg->reply(CMD_PENDING);
        }
        return $msg->reply($STATUS_MAP{$self->status->{$msg->id}});
    } else {
        my $reply = $msg->reply(CMD_ERROR);
        $reply->set_payload('Unknown message ID');
        return $reply;
    }
}

1;