#-------------------------------------------------------------------------------
# Worker pool.
#-------------------------------------------------------------------------------
package Argon::Pool;

use Moose;
use Carp;
use namespace::autoclean;
use Argon qw/CMD_COMPLETE CMD_ERROR/;
require AnyEvent::Worker;

has 'concurrency' => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

#-------------------------------------------------------------------------------
# The maximum number of requests that may be handled by any individual worker
# process before the process is terminated and replaced with a fresh process.
# If not specified (or set to zero), processes will not be restarted.
#-------------------------------------------------------------------------------
has 'max_requests' => (
    is       => 'ro',
    isa      => 'Int',
    default  => 0,
);

#-------------------------------------------------------------------------------
# Tracks the number of requests each process has handled. Counts are indexed
# to each workers PID (AnyEvent::Worker->{child_pid}).
#-------------------------------------------------------------------------------
has 'request_count' => (
    is       => 'rw',
    isa      => 'HashRef[Int]',
    init_arg => undef,
    default  => sub { {} },
);

has 'is_running' => (
    is       => 'rw',
    isa      => 'Int',
    init_arg => undef,
    default  => 0,
);

has 'pool' => (
    traits   => ['Array'],
    is       => 'rw',
    isa      => 'ArrayRef[AnyEvent::Worker]',
    init_arg => undef,
    default  => sub { [] },
    handles  => {
        'workers'    => 'elements',
        'checkout'   => 'shift',
        'checkin'    => 'push',
        'idle'       => 'count',
        'clear_pool' => 'clear',
    },
);

has 'pending' => (
    traits   => ['Array'],
    is       => 'rw',
    isa      => 'ArrayRef[ArrayRef[Argon::Message, CodeRef]]',
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
    my $self = shift;
    my $worker = AnyEvent::Worker->new(sub {
        my ($self, $message) = @_;
        my ($class, $params) = @{$message->get_payload};

        my $result = eval {
            require "$class.pm";
            $class->new(@$params)->run;
        };

        my $reply;
        if ($@) {
            my $error = $@;
            $reply = $message->reply(CMD_ERROR);
            $reply->set_payload($error);
        } else {
            $reply = $message->reply(CMD_COMPLETE);
            $reply->set_payload($result);
        }

        return $reply;
    });

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
    my $pid = $worker->{child_pid};
    undef $self->request_count->{$pid};
    $worker->kill_child;
}

#-------------------------------------------------------------------------------
# Launches the worker pool and processes any queued tasks.
#-------------------------------------------------------------------------------
sub start {
    my $self = shift;
    $self->start_worker foreach (1 .. $self->concurrency);
    $self->is_running(1);
    $self->assign_pending;
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

    my ($message, $callback) = @{$self->queue_get};
    my $worker = $self->checkout;

    $worker->do($message, sub {
        eval { $callback->(shift) };
        $@ && carp $@;

        if ($self->is_running) {
            # Check if worker ought to be restarted
            if ($self->max_requests != 0) {
                my $pid = $worker->{child_pid};
                $self->request_count->{$pid} ||= 0; # init count if necessary
                if (++$self->request_count->{$pid} >= $self->max_requests) {
                    undef $self->request_count->{$pid};
                    $worker->kill_child;
                }
            }

            # Check worker back in and trigger assign_pending again
            $self->checkin($worker);
            $self->assign_pending;
        } else {
            # System is shut down - stop worker
            $self->stop_worker($worker);
        }
    });
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

__PACKAGE__->meta->make_immutable;

1;