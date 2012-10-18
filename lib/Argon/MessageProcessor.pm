#-------------------------------------------------------------------------------
# MessageProcessors queue and track message status.
#-------------------------------------------------------------------------------
package Argon::MessageProcessor;

use Moose;
use Carp;
use namespace::autoclean;
use Argon qw/:commands/;

require Argon::MessageQueue;
require Argon::Message;

use constant STATUS_QUEUED   => 0;
use constant STATUS_ASSIGNED => 1;
use constant STATUS_COMPLETE => 2;

# Max number of messages that can be queued
has 'queue_limit' => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

# Incoming message queue
has 'queue' => (
    is       => 'ro',
    isa      => 'Argon::MessageQueue',
    init_arg => undef,
    lazy     => 1,
    default  => sub { Argon::MessageQueue->new(limit => $_[0]->queue_limit) },
);

# Hash of msg id => msg
has 'message' => (
    is       => 'ro',
    isa      => 'HashRef',
    init_arg => undef,
    default  => sub { {} },
);

# Hash of msg id => STATUS_*
has 'status' => (
    is       => 'ro',
    isa      => 'HashRef',
    init_arg => undef,
    default  => sub { {} },
);

#-------------------------------------------------------------------------------
# Adds a message to the queue and begins internal tracking.
#-------------------------------------------------------------------------------
sub msg_queue {
    my ($self, $msg) = @_;

    if ($self->queue->is_full) {
        return 0;
    } else {
        $msg->update_timestamp;
        $self->queue->put($msg);

        $self->message->{$msg->id} = $msg;
        $self->status->{$msg->id}  = STATUS_QUEUED;

        return 1;
    }   
}

#-------------------------------------------------------------------------------
# When a message has been assigned, this method is called to update tracking.
#-------------------------------------------------------------------------------
sub msg_assigned {
    my ($self, $msg) = @_;
    $self->message->{$msg->id} = $msg;
    $self->status->{$msg->id}  = STATUS_ASSIGNED;
}

#-------------------------------------------------------------------------------
# When a message is complete, this method is called to update tracking.
#-------------------------------------------------------------------------------
sub msg_complete {
    my ($self, $msg) = @_;
    $self->message->{$msg->id} = $msg;
    $self->status->{$msg->id}  = STATUS_COMPLETE;
}

#-------------------------------------------------------------------------------
# When a complete message is collected, this method is called to clear tracking
# data.
#-------------------------------------------------------------------------------
sub msg_clear {
    my ($self, $msg) = @_;
    undef $self->message->{$msg->id};
    undef $self->status->{$msg->id};
}


__PACKAGE__->meta->make_immutable;

1;