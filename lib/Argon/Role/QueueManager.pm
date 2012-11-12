#-------------------------------------------------------------------------------
# Defines the behavior of classes which assign tasks from the queue. When the
# class is constructed, a timer is started which probes the queue for entries
# and calls the method 'process_message' until one of two conditions is met:
#    1) the queue is empty
#    2) process_message returns false
#-------------------------------------------------------------------------------
package Argon::Role::QueueManager;

use Moose::Role;
use Carp;
use namespace::autoclean;
use AnyEvent qw//;
use Argon    qw/LOG :defaults :statuses/;

requires 'assign_message';
requires 'msg_accept';

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

has 'queue_timer' => (
    is       => 'rw',
    init_arg => undef,
);

#-------------------------------------------------------------------------------
# Adds a timer that polls the queue and attempts to assign any queued tasks.
#-------------------------------------------------------------------------------
sub BUILD {}
after 'BUILD' => sub {
    my $self = shift;
    LOG('Queue limit is %d', $self->queue_limit);
    $self->queue_timer(AnyEvent->timer(
        interval => POLL_INTERVAL,
        after    => 0,
        cb       => sub {
            until ($self->queue->is_empty) {
                # Attempt to assign the message at the top of the queue. If
                # successful, remove from the queue. Otherwise, stop processing
                # messages.
                my $msg = $self->queue->top;
                if ($self->assign_message($msg)) {
                    $self->queue->get;
                } else {
                    last;
                }
            }
        }
    ));
};

#-------------------------------------------------------------------------------
# Modifies the behavior of msg_accept to place accepted messages in the queue
# and to fail if the queue is full.
#-------------------------------------------------------------------------------
around 'msg_accept' => sub {
    my ($orig, $self, $msg) = @_;
    if ($self->queue->is_full || !$self->$orig($msg)) {
        croak 'Queue is full';
    } else {
        $msg->update_timestamp;
        $self->queue->put($msg);
    }
};

1;