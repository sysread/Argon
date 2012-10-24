#-------------------------------------------------------------------------------
# MessageProcessors track message status.
#-------------------------------------------------------------------------------
package Argon::MessageProcessor;

use Moose;
use Carp;
use namespace::autoclean;
use Argon qw/:commands :statuses/;

require Argon::MessageQueue;
require Argon::Message;

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
# When a message has been accepted, this method is called to updated tracking.
#-------------------------------------------------------------------------------
sub msg_accept {
    my ($self, $msg) = @_;
    $self->message->{$msg->id} = $msg;
    $self->status->{$msg->id}  = STATUS_QUEUED;
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