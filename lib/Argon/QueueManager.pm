#-------------------------------------------------------------------------------
# Defines the behavior of classes which assign tasks from the queue. When the
# class is constructed, a timer is started which probes the queue for entries
# and calls the method 'process_message' until one of two conditions is met:
#    1) the queue is empty
#    2) process_message returns false
#-------------------------------------------------------------------------------
package QueueManager;

use Moose::Role;
use Carp;
use namespace::autoclean;
use AnyEvent qw//;
use Argon    qw/:statuses/;

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
    is       => 'ro',
    init_arg => undef,
);

#-------------------------------------------------------------------------------
# Adds a timer that polls the queue and attempts to assign any queued tasks.
#-------------------------------------------------------------------------------
sub BEGIN {};
after 'BEGIN' => sub {
    my $self = shift;
    $self->queue_timer(AnyEvent->timer(
        interval => 0.25,
        after => 0,
        cb => sub {
            until ($self->queue->is_empty) {
                $self->assign_message($self->queue->get)
                    or last;
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
    
    if ($self->queue->is_full) {
        return 0;
    } else {
        $msg->update_timestamp;
        $self->queue->put($msg);
        $self->$orig->($msg);
    }
};

__PACKAGE__->meta->make_immutable;

1;