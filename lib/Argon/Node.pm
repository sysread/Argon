#-------------------------------------------------------------------------------
# Nodes manage a pool of Worker processes. Like a Cluster, they route tasks to
# Workers (without worrying about each processes' speed, since they are local),
# and store the results.
#-------------------------------------------------------------------------------
package Argon::Node;

use Moose;
use Carp;
use namespace::autoclean;

require Argon::WorkerProcess;

extends 'Argon::MessageProcessor';
with    'Argon::MessageServer';
with    'Argon::QueueManager';

has 'concurrency' => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

has 'workers' => (
    is       => 'rw',
    isa      => 'ArrayRef',
    init_arg => undef,
    lazy     => 1,
    builder  => 'initialize_workers',
);

#-------------------------------------------------------------------------------
# Spawns a single worker process and returns the Argon::WorkerProcess instance.
# Passes parameters unchanged to Argon::WorkerProcess->spawn.
#-------------------------------------------------------------------------------
sub spawn_worker {
    my $self   = shift;
    my $worker = Argon::WorkerProcess->new(endline => $self->endline);
    $worker->spawn(@_);
    return $worker;
}

#-------------------------------------------------------------------------------
# Initializes by starting workers processes.
# TODO Determine and implement correct behavior when spawning initial processes
#      is unsuccessful. Is this behavior different from an error spawning a
#      worker process when already running?
#-------------------------------------------------------------------------------
sub initialize_workers {
    my $self = shift;
    for (1 .. $self->concurrency) {
        $self->spawn_worker(
            on_success => sub {
                push @{$self->workers}, shift;
            },
            on_error => sub {
                warn "Bad exit status when spawning worker process.";
            },
        );
    }
}

#-------------------------------------------------------------------------------
# Attempts to assign the message to the next free worker process. If no
# processes are free, returns false.
#-------------------------------------------------------------------------------
sub assign_message {
    my ($self, $message) = @_;
    foreach my $worker (@{$self->workers}) {
        unless ($worker->has_pending) {
            $worker->send($message, sub { $self->msg_complete(shift) });
            return 1;
        }
    }

    return 0;
}

__PACKAGE__->meta->make_immutable;

1;