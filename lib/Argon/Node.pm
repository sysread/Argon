#-------------------------------------------------------------------------------
# Nodes manage a pool of Worker processes. Like a Cluster, they route tasks to
# Workers (without worrying about each processes' speed, since they are local),
# and store the results.
#
# TODO
#   * Reconnect/register to manager if disconnected
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
    isa      => 'HashRef[ArrayRef]',
    init_arg => undef,
    default  => sub {{}},
);

has 'manager' => (
    is       => 'rw',
    isa      => 'HashRef[Argon::Client]',
    init_arg => undef,
    default  => sub {{}},
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
    $self->managers->{"$host:$port"} = [$host, $port];
}

#-------------------------------------------------------------------------------
# Registers node with configured upstream managers.
#-------------------------------------------------------------------------------
sub notify {
    my $self = shift;
    my $port = $self->server->port;
    my $host = $self->server->host || hostname;
    my $node = [$host, $port];

    foreach my $manager (keys %{$self->managers}) {
        my ($host, $port) = @{$self->managers->{$manager}};
        my $client = Argon::Client->new(host => $host, port => $port);
        my $msg    = Argon::Message->new(command => CMD_ADD_NODE);
        $msg->set_payload($node);

        my $respond = Argon::Respond->new();

        $respond->to(CMD_ACK, sub {
            LOG("Registration complete with manager %s:%d", $host, $port);
            $self->manager->{$manager} = $client;
        });

        $respond->to(CMD_ERROR, sub {
            LOG("Unable to register with manager %s:%d - %s", $host, $port, shift);
            $client->close;
            del $self->managers->{$manager};
        });

        LOG("Connecting to manager %s", $manager);
        $client->connect(sub {
            LOG("Notification sent to manager %s", $manager);
            $client->send($msg, $respond);
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
