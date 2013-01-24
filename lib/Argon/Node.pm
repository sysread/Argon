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
with    'Argon::Role::MessageServer';
with    'Argon::Role::QueueManager';

# These are used to configure the Argon::Pool
has 'concurrency'  => (is => 'ro', isa => 'Int', required => 1);
has 'max_requests' => (is => 'ro', isa => 'Int', default  => 0);

has 'managers' => (
    is       => 'rw',
    isa      => 'ArrayRef[ArrayRef]',
    init_arg => undef,
    default  => sub { [] },
);

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

        $pool->start;
        return $pool;
    }
);

has 'int_handler'  => ( is => 'rw', init_arg => undef );
has 'term_handler' => ( is => 'rw', init_arg => undef );

#-------------------------------------------------------------------------------
# Initializes the node
#-------------------------------------------------------------------------------
sub initialize {
    my $self = shift;

    # Force creation of pool
    $self->pool->start;

    # Notify upstream managers
    $self->notify;

    # Add signal handlers
    $self->int_handler(AnyEvent->signal(signal => 'INT',  cb => sub { $self->shutdown }));
    $self->term_handler(AnyEvent->signal(signal => 'INT', cb => sub { $self->shutdown }));
}

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
# Selects a remote host to use as the manager for this node.
#-------------------------------------------------------------------------------
sub add_manager {
    my ($self, $host, $port) = @_;
    push @{$self->managers}, [$host, $port];
}

#-------------------------------------------------------------------------------
# Registers node with configured upstream managers.
#-------------------------------------------------------------------------------
sub notify {
    my $self = shift;
    my $port = $self->server->port;
    my $host = $self->server->host || hostname;
    my $node = [$host, $port];

    foreach my $manager (@{$self->managers}) {
        my ($host, $port) = @$manager;
        my $client = Argon::Client->new(host => $host, port => $port);
        my $msg    = Argon::Message->new(command => CMD_ADD_NODE);
        $msg->set_payload($node);

        LOG("Connecting to manager %s:%d", $host, $port);
        $client->connect(sub {
            LOG("Sent notification to manager %s:%d", $host, $port);
            $client->send($msg, sub {
                LOG("Registration complete with manager %s:%d", $host, $port);
                $client->close;
            });
        });
    }
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
