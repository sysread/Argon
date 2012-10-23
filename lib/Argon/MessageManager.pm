#-------------------------------------------------------------------------------
# MessageManagers forward tasks to a series of servers. Essentially, they act
# as a pool of client objects. The targets may be any kind of MessageServer
# service. Managers track the speed and responsiveness of their servers and
# route tasks to the most available server.
#-------------------------------------------------------------------------------
package Argon::MessageManager;

use Moose;
use Carp;
use namespace::autoclean;
use Argon      qw/:commands TRACK_MESSAGES/;
use List::Util qw/sum/;

require Time::HiRes;
require Argon::Client;

extends 'Argon::MessageProcessor';

# List of Argon::Client instances
has 'servers' => (
    is       => 'rw',
    isa      => 'ListRef',
    default  => sub { [] },
    init_arg => undef,
);

# Hash of msg id => server; tracks what messages are assigned where
has 'assigned_to' => (
    is       => 'ro',
    isa      => 'HashRef',
    default  => sub { {} },
    init_arg => undef,
);

# Hash of server => list of msg ids; tracks assignments to a server
has 'assignments' => (
    is       => 'ro',
    isa      => 'HashRef',
    default  => sub { {} },
    init_arg => undef,
);

# Hash of server => list of last N processing times
has 'processing_times' => (
    is       => 'ro',
    isa      => 'HashRef',
    default  => sub { {} },
    init_arg => undef,
);

# Hash of server => precalculated avg processing time
has 'avg_processing_time' => (
    is       => 'ro',
    isa      => 'HashRef',
    default  => sub { {} },
    init_arg => undef,
);

#-------------------------------------------------------------------------------
# Adds a new client object to the manager.
#-------------------------------------------------------------------------------
sub add_client {
    my ($self, $client) = @_;
    $client->connect(sub {
        push @{$self->servers}, $client;
        $self->assignments->{$client}         = [];
        $self->processing_times->{$client}    = [];
        $self->avg_processing_time->{$client} = 0;
    });
}

#-------------------------------------------------------------------------------
# Removes a client object from the manager.
#-------------------------------------------------------------------------------
sub del_client {
    my ($self, $client) = @_;

    foreach my $id (@{$self->assignments->{$client}}) {
        my $msg   = $self->message->{$id};
        my $reply = $msg->reply(CMD_ERROR);
        $self->msg_complete($reply);
    }

    $self->servers([ map {$_ ne $client} @{$self->servers} ]);
    undef $self->assignments->{client};
    undef $self->processing_times->{$client};
    undef $self->avg_processing_time->{$client};
    $client->destroy;
}

#-------------------------------------------------------------------------------
# Calculates the amount of processing time required by a tracked service to
# process all items currently assigned to it.
#-------------------------------------------------------------------------------
sub estimated_processing_time {
    my ($self, $client) = @_;
    return $self->avg_processing_time->{$client}
         * scalar(@{$self->assignments->{$client}});
}

#-------------------------------------------------------------------------------
# Returns the next most available server.
# TODO account for servers which may be inaccessible
#-------------------------------------------------------------------------------
sub next_server {
    my $self = shift;

    my %time;
    $time{$_} = $self->estimated_processing_time($_) foreach @{$self->servers};

    my $least;
    foreach my $server (@{$self->servers}) {
        if (!defined $least || $time{$server} < $time{$least}) {
            $least = $server;
        }
    }

    return $least;
}

#-------------------------------------------------------------------------------
# Assigns a message to the selected server.
#-------------------------------------------------------------------------------
sub assign {
    my ($self, $msg, $server) = @_;
    push @{$self->assignments->{$server}}, $msg->id;

    $self->msg_assigned($msg);
    my $sent = Time::HiRes::time();

    $server->send($msg, sub {
        my $msg = shift;

        push @{$self->processing_times->{$server}}, (Time::HiRes::time() - $sent);
        shift @{$self->processing_times->{$server}}
            if @{$self->processing_times->{$server}} > TRACK_MESSAGES;

        $self->avg_processing_time->{$server} = sum(@{$self->processing_times->{$server}}) / TRACK_MESSAGES;
        $self->msg_complete($msg);
    });
}

__PACKAGE__->meta->make_immutable;

1;