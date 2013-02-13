#-------------------------------------------------------------------------------
# Worker pool.
#-------------------------------------------------------------------------------
package Argon::Pool;

use Moose;
use Moose::Util::TypeConstraints;
use Carp;
use namespace::autoclean;
use Argon qw/LOG CMD_COMPLETE CMD_ERROR/;
require Argon::Pool::Worker;
require Argon::Message;

# Subtype describing a tuple of an Argon::Message and a CodeRef. See
# 'pending' below.
subtype 'PendingItem'
    => as 'ArrayRef',
    => where { $_->[0]->isa('Argon::Message') && ref $_->[1] eq 'CODE' },
    => message { 'Expected tuple of Argon::Message and CodeRef' };

# The number of worker processes to maintain.
has 'concurrency' => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

# The maximum number of requests that may be handled by any individual worker
# process before the process is terminated and replaced with a fresh process.
# If not specified (or set to zero), processes will not be restarted.
has 'max_requests' => (
    is       => 'ro',
    isa      => 'Int',
    default  => 0,
);

# Flags the pool as currently running.
has 'is_running' => (
    is       => 'rw',
    isa      => 'Bool',
    init_arg => undef,
    default  => 0,
);

# Array of worker instances. Workers are checked in and out as they are
# assigned to tasks, leaving the pool array empty when no workers are
# available.
has 'pool' => (
    traits   => ['Array'],
    is       => 'rw',
    isa      => 'ArrayRef[Argon::Pool::Worker]',
    init_arg => undef,
    default  => sub {[]},
    handles  => {
        'workers'    => 'elements',
        'checkout'   => 'shift',
        'checkin'    => 'push',
        'idle'       => 'count',
        'clear_pool' => 'clear',
    },
);

# FIFO queue of pending items.
has 'pending' => (
    traits   => ['Array'],
    is       => 'rw',
    isa      => 'ArrayRef[PendingItem]',
    init_arg => undef,
    default  => sub { [] },
    handles  => {
        'queue_get'    => 'shift',
        'queue_put'    => 'push',
        'queue_length' => 'count',
    },
);

#-------------------------------------------------------------------------------
# Returns a new AnyEvent::Worker process configured to handle Argon::Message
# tasks.
#-------------------------------------------------------------------------------
sub start_worker {
    my $self   = shift;
    my $worker = Argon::Pool::Worker->new();
    $self->checkin($worker);
    return $worker;
}

#-------------------------------------------------------------------------------
# Kills an individual worker process and removes it from internal tracking.
# Assumes that the worker process has been checked out of the pool. If the
# worker process is still in the pool, the results could be unexpected!
#-------------------------------------------------------------------------------
sub stop_worker {
    my ($self, $worker) = @_;
    $worker->kill_child;
}

#-------------------------------------------------------------------------------
# Launches the worker pool and processes any queued tasks.
#-------------------------------------------------------------------------------
sub start {
    my $self = shift;
    unless ($self->is_running) {
        $self->start_worker foreach (1 .. $self->concurrency);
        $self->is_running(1);
        $self->assign_pending;
    }
}

#-------------------------------------------------------------------------------
# Shuts down the worker pool. Any queued items remain in the queue and are
# processed the next time the pool is started up. Any workers currently
# processing tasks will complete their tasks and be terminated asynchronously.
#-------------------------------------------------------------------------------
sub shutdown {
    my $self = shift;
    $self->is_running(0);
    while (my $worker = $self->checkout) {
        $self->stop_worker($worker);
    }
}

#-------------------------------------------------------------------------------
# Assigns the next pending task, if any, the the next available worker process,
# if any. Returns immediately if there are no pending tasks, no available
# workers, or the pool is not currently running.
#-------------------------------------------------------------------------------
sub assign_pending {
    my $self = shift;
    return unless $self->is_running;
    return unless $self->queue_length > 0;
    return unless $self->idle         > 0;

    while ($self->queue_length > 0 && $self->idle > 0) {
        my ($message, $callback) = @{$self->queue_get};
        my $worker = $self->checkout;

        $worker->do($message, sub {
            # ARGS: worker, Message reply
            $worker  = shift;
            $message = Argon::Message::decode(shift);

            # Call task callback
            eval { $callback->($message) };
            $@ && carp $@;

            if ($self->is_running) {
                # Check if worker ought to be restarted
                if ($self->max_requests != 0
                 && $worker->inc >= $self->max_requests) {
                    $self->stop_worker($worker);
                    $worker = $self->start_worker; # implicitly checks in new workers
                } else {
                    $self->checkin($worker);
                }

                # Trigger assign_pending again
                $self->assign_pending;
            } else {
                # System is shut down - stop worker
                $self->stop_worker($worker);
            }
        });
    }
}

#-------------------------------------------------------------------------------
# Assigns a new task.
#-------------------------------------------------------------------------------
sub assign {
    my ($self, $message, $callback) = @_;
    $self->start unless $self->is_running;
    $self->queue_put([$message, $callback]);
    $self->assign_pending;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
