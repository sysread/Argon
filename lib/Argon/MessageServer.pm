package Argon::MessageServer;

use Moose::Role;
use Carp;
use namespace::autoclean;
use Argon qw/:commands :statuses EOL CHUNK_SIZE/;
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
    $self->server->respond_to(CMD_QUEUE,  $self->reply_queue);
    $self->server->respond_to(CMD_STATUS, $self->reply_status);
};

#-------------------------------------------------------------------------------
# Replies to request to accept/queue a new message.
#-------------------------------------------------------------------------------
sub reply_queue {
    my ($self, $msg) = @_;
    eval { $self->msg_accept($msg) };
    if ($@) {
        my $error = $@;
        my $reply = $msg->reply(CMD_REJECTED);
        $reply->set_payload($error);
        return $reply;
    } else {
        return $msg->reply(CMD_ACK);
    }
    return $msg->reply($self->msg_accept($msg) ? CMD_ACK : CMD_REJECTED);
}

#-------------------------------------------------------------------------------
# Replies with the current message status (pending, complete, etc.)
#-------------------------------------------------------------------------------
sub reply_status {
    my ($self, $msg) = @_;
    if (exists $self->status->{$msg->id}) {
        return $msg->reply($STATUS_MAP{$self->status->{$msg->id}});
    } else {
        my $reply = $msg->reply(CMD_ERROR);
        $reply->set_payload('Unknown message ID');
        return $reply;
    }
}

__PACKAGE__->meta->make_immutable;

1;