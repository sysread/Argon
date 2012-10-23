package Argon::MessageServer;

use Moose::Role;
use Carp;
use namespace::autoclean;
use Argon qw/:commands EOL CHUNK_SIZE/;
use Argon::MessageProcessor;

# Maps local msg status to a CMD_* reply (for msg_status)
my %STATUS_MAP = (
    Argon::MessageProcessor::STATUS_QUEUED,   CMD_PENDING,
    Argon::MessageProcessor::STATUS_ASSIGNED, CMD_PENDING,
    Argon::MessageProcessor::STATUS_COMPLETE, CMD_COMPLETE,
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
    is  => 'ro',
    isa => 'Argon::Server',
);

#-------------------------------------------------------------------------------
# Configures the server, mapping commands to local methods.
#-------------------------------------------------------------------------------
sub build_protocol {
    my $self = shift;
    $self->server->respond_to(CMD_QUEUE,  $self->reply_queue);
    $self->server->respond_to(CMD_STATUS, $self->reply_status);
}

#-------------------------------------------------------------------------------
# Replies to request to queue a new message.
#-------------------------------------------------------------------------------
sub reply_queue {
    my ($self, $msg) = @_;
    return $msg->reply($self->msg_queue($msg) ? CMD_ACK : CMD_REJECTED);
}

#-------------------------------------------------------------------------------
# Replies with the current message status (pending, complete, etc.)
#-------------------------------------------------------------------------------
sub reply_status {
    my ($self, $msg) = @_;
    return $msg->reply(CMD_ERROR) if !exists $self->status->{$msg->id};
    return $msg->reply($STATUS_MAP{$self->status->{$msg->id}});
}

__PACKAGE__->meta->make_immutable;

1;