#-------------------------------------------------------------------------------
# A bounded queue with rudimentary safeguards against starvation. Queues
# manage a separate array for each priority. Pulling the next item from the
# queue checks each priority's array in turn, returning the next item from the
# highest priority queue. Starvation is avoided by increasing the priority of
# items which have remained in their queue for too long.
#-------------------------------------------------------------------------------
package Argon::Queue;

use strict;
use warnings;
use Carp;
use namespace::autoclean;

use Coro;
use Time::HiRes qw/time/;
use Argon       qw/:priorities/;

use fields (
    'check',      # seconds (float) between reprioritization checks
    'limit',      # max items permitted in queue
    'queues',     # store queue for each priority
    'count',      # # of items currently in queue
    'last_check', # time stamp of last reprioritization
    'item',       # hash of item to [item ref, priority, time added]
    'sem',        # used to block get() until an element is ready
);

#-------------------------------------------------------------------------------
# Creates a new queue. Queues may be bounded to set a maximum length to the
# queue. Optional parameter 'check' flips on starvation checks. When active,
# a starvation check will occur no more often than once every 'check' seconds.
# At that point, if any element has been present in the queue for 'check'
# seconds, its priority will be bumped to the next highest to prevent it from
# being starved by higher priority queues indefinitely. Reprioritization is
# performed on get()s and put()s.
#
# Inputs:
#   limit (int,   optional) = upper limit on queue length
#   check (float, optional) = seconds between reprioritization checks
#-------------------------------------------------------------------------------
sub new {
    my ($class, %param) = @_;
    my $limit = $param{limit};
    my $check = $param{check};
    my $self  = fields::new($class);

    $self->{limit}  = $limit;
    $self->{check}  = $check;
    $self->{queues} = [map {[]} (PRI_MAX .. PRI_MIN)];
    $self->{item}   = {};
    $self->{sem}    = Coro::Semaphore->new(0);
    $self->{last_check} = 0;

    return $self;
}

#-------------------------------------------------------------------------------
# Returns true if there are no elements in the queue.
#-------------------------------------------------------------------------------
sub is_empty { $_[0]->{count} == 0 }

#-------------------------------------------------------------------------------
# Returns true if there is no limit set or if the queue is at the specified
# limit.
#-------------------------------------------------------------------------------
sub is_full { defined $_[0]->{limit} && $_[0]->{count} == $_[0]->{limit} }

#-------------------------------------------------------------------------------
# Helper method that actually does the work of placing the item in the queue.
#-------------------------------------------------------------------------------
sub _put {
    my ($self, $item, $priority) = @_;
    push @{$self->{queues}[$priority]}, $item;

    # Only record item if it can be given a higher priority
    $self->{item}{$item} = [$item, $priority, time]
        unless $priority == PRI_MAX;

    ++$self->{count};
    $self->{sem}->up;
}

#-------------------------------------------------------------------------------
# Places an item in the queue. Throws an error if the queue is full.
#
# Inputs:
#    item (any): item to place in the queue
#    priority (Argon::PRI_*, optional): priority of the item (defaults to PRI_NORMAL)
# Output:
#    new queue length
#-------------------------------------------------------------------------------
sub put {
    my ($self, $item, $priority) = @_;
    $self->is_full && croak 'queue is full';
    !defined $priority && ($priority = PRI_NORMAL);
    $self->reprioritize;
    $self->_put($item, $priority);
    return $self->{count};
}

#-------------------------------------------------------------------------------
# Blocks until an item is available in the queue, then returns that item.
#-------------------------------------------------------------------------------
sub get {
    my $self = shift;
    $self->reprioritize;
    $self->{sem}->down;

    foreach my $pri (PRI_MAX .. PRI_MIN) {
        if (@{$self->{queues}[$pri]} > 0) {
            my $item = shift @{$self->{queues}[$pri]};
            delete $self->{item}{$item};
            --$self->{count};
            return $item;
        }
    }

    return;
}

#-------------------------------------------------------------------------------
# Reprioritizes items in the queue. Any item which has remained in its own
# queue for more than $self->{check} seconds gets placed in the next highest
# priority queue. This method will not perform its work more often than once
# every $self->{check} seconds.
#-------------------------------------------------------------------------------
sub reprioritize {
    my $self = shift;
    my $now  = time;

    return unless defined $self->{check}
               && $now >= $self->{last_check} + $self->{check};

    my @msgids = grep { $now - $self->{item}{$_}[2] >= $self->{check} }
                 keys %{$self->{item}};

    my %prune;
    @prune{@msgids} = (1) x @msgids;
    foreach my $pri (PRI_MIN .. PRI_MAX) {
        $self->{queues}[$pri] = [ grep { !$prune{$_} } @{$self->{queues}[$pri]} ];
    }

    $self->{count} -= scalar @msgids;

    foreach my $msgid (@msgids) {
        $self->_put(
            $self->{item}{$msgid}[0],
            $self->{item}{$msgid}[1] - 1,
        );

        delete $self->{item}{$msgid};
    }

    $self->{last_check} = $now;
}

1;