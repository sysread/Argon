#-------------------------------------------------------------------------------
# Nodes manage a pool of Worker processes. Like a Cluster, they route tasks to
# Workers (without worrying about each processes' speed, since they are local),
# and store the results.
#-------------------------------------------------------------------------------
package Argon::Node;

use Moose;
use Carp;
use namespace::autoclean;
use Sys::Hostname;
use Argon qw/LOG :commands/;

require Argon::Client;
require Argon::Pool;

extends 'Argon::MessageProcessor';
with    'Argon::Role::Server';
with    'Argon::Role::MessageServer';
with    'Argon::Role::ManagedServer';
with    'Argon::Role::QueueManager';

# These are used to configure the Argon::Pool
has 'concurrency'  => (is => 'ro', isa => 'Int', required => 1);
has 'max_requests' => (is => 'ro', isa => 'Int', default  => 0);

has 'pool' => (
    is       => 'ro',
    isa      => 'Argon::Pool',
    init_arg => undef,
    lazy     => 1,
    default  => sub {
        my $self = shift;
        my $pool = Argon::Pool->new(
            concurrency  => $self->concurrency,
            max_requests => $self->max_requests,
        );

        return $pool;
    }
);

has 'int_handler'  => ( is => 'rw', init_arg => undef );
has 'term_handler' => ( is => 'rw', init_arg => undef );

#-------------------------------------------------------------------------------
# Initializes the node
#-------------------------------------------------------------------------------
after 'start' => sub {
    my $self = shift;
    LOG('Starting node with %d workers on port %d', $self->concurrency, $self->port);

    $self->pool->start;

    # Notify upstream managers
    $self->notify;

    # Add signal handlers
    $self->int_handler(AnyEvent->signal(signal => 'INT',  cb => sub { $self->shutdown }));
    $self->term_handler(AnyEvent->signal(signal => 'INT', cb => sub { $self->shutdown }));
};

#-------------------------------------------------------------------------------
# Shuts down
#-------------------------------------------------------------------------------
sub shutdown {
    my $self = shift;
    LOG('Shutting down.');
    $self->pool->shutdown;
    exit 0;
}

#-------------------------------------------------------------------------------
# Attempts to assign the message to the next free worker process. If no
# processes are free, returns false.
#-------------------------------------------------------------------------------
sub assign_message {
    my ($self, $message) = @_;
    $self->pool->assign($message, sub { $self->msg_complete(shift) });
    return 1;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
