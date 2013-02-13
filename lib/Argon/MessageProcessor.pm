#-------------------------------------------------------------------------------
# MessageProcessors serve as a proxy or hub, tracking message status as messages
# are accepted, routed for processing, and returned.
#-------------------------------------------------------------------------------
package Argon::MessageProcessor;

use Moose;
use Carp;
use namespace::autoclean;
use Argon qw/LOG :commands :statuses/;

require Argon::Message;

# Hash of msg id => msg
has 'message' => (
    is       => 'ro',
    isa      => 'HashRef[Argon::Message]',
    init_arg => undef,
    default  => sub { {} },
    traits   => ['Hash'],
    handles  => {
        message_set => 'set',
        message_get => 'get',
        message_del => 'delete',
    },
);

# Hash of msg id => STATUS_*
has 'status' => (
    is       => 'ro',
    isa      => 'HashRef[Int]',
    init_arg => undef,
    default  => sub { {} },
    traits   => ['Hash'],
    handles  => {
        status_set => 'set',
        status_get => 'get',
        status_del => 'delete',
    },
);

#-------------------------------------------------------------------------------
# When a message has been accepted, this method is called to updated tracking.
#-------------------------------------------------------------------------------
sub msg_accept {
    my ($self, $msg) = @_;
    $self->message_set($msg->id, $msg);
    $self->status_set($msg->id, STATUS_QUEUED);
    return 1;
}

#-------------------------------------------------------------------------------
# When a message has been assigned, this method is called to update tracking.
#-------------------------------------------------------------------------------
sub msg_assigned {
    my ($self, $msg) = @_;
    $self->message_set($msg->id, $msg);
    $self->status_set($msg->id, STATUS_ASSIGNED);
    return 1;
}

#-------------------------------------------------------------------------------
# When a message is complete, this method is called to update tracking.
#-------------------------------------------------------------------------------
sub msg_complete {
    my ($self, $msg) = @_;
    $self->message_set($msg->id, $msg);
    $self->status_set($msg->id, STATUS_COMPLETE);
    return 1;
}

#-------------------------------------------------------------------------------
# When a complete message is collected, this method is called to clear tracking
# data. Returns the last stored version of the message.
#-------------------------------------------------------------------------------
sub msg_clear {
    my ($self, $msg) = @_;
    my $result = $self->message_get($msg->id);
    $self->message_del($msg->id);
    $self->status_del($msg->id);
    return $result;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
