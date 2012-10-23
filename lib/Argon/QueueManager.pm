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

requires 'process_message';
requires 'queue';

has 'queue_timer' => (
    is       => 'ro',
    init_arg => undef,
);

sub BEGIN {};
after 'BEGIN' => sub {
    my $self = shift;
    $self->queue_timer(AnyEvent->timer(
        after    => 0,
        interval => 0.25,
        cb => sub {
            until ($self->queue->is_empty) {
                $self->process_message($self->queue->get)
                    or last;
            }
        }
    ));
};

__PACKAGE__->meta->make_immutable;

1;