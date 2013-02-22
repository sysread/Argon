#-------------------------------------------------------------------------------
# MessageManagers forward tasks to a series of servers. Essentially, they act
# as a pool of client objects. The targets may be any kind of MessageServer
# service. Managers track the speed and responsiveness of their servers and
# route tasks to the most available server.
#
# TODO Track message stats with a time slice rather than the last n messages
# TODO Higher resolution in tracking to deal with very small/fast jobs
#-------------------------------------------------------------------------------
package Argon::MessageManager;

use Moose;
use Carp;
use namespace::autoclean;
use List::Util   qw/sum reduce/;
use Scalar::Util qw/weaken/;
use Time::HiRes  qw/time/;
use Argon        qw/:commands LOG TRACK_MESSAGES/;

require Argon::Channel;

extends 'Argon::MessageProcessor';

# List of Argon::Channel instances
has 'clients' => (
    is       => 'rw',
    isa      => 'HashRef[Argon::Channel]',
    default  => sub { {} },
    init_arg => undef,
    traits   => ['Hash'],
    handles  => {
        client_set    => 'set',
        client_get    => 'get',
        client_del    => 'delete',
        all_clients   => 'values',
        num_clients   => 'count',
        client_exists => 'exists',
    },
);

# Hash of server => msg id => 1; tracks assignments to a server
has 'assignments' => (
    is       => 'ro',
    isa      => 'HashRef[Argon::Message]',
    default  => sub { {} },
    init_arg => undef,
);

# Hash of msg id => start time
has 'start_time' => (
    is       => 'ro',
    isa      => 'HashRef[Num]',
    default  => sub { {} },
    init_arg => undef,
    traits   => ['Hash'],
    handles  => {
        'set_start_time' => 'set',
        'get_start_time' => 'get',
        'del_start_time' => 'delete',
    }
);

# Hash of server => list of last N processing times
has 'processing_times' => (
    is       => 'ro',
    isa      => 'HashRef[ArrayRef[Num]]',
    default  => sub { {} },
    init_arg => undef,
);

# Hash of server => precalculated avg processing time
has 'avg_processing_time' => (
    is       => 'ro',
    isa      => 'HashRef[Num]',
    default  => sub { {} },
    init_arg => undef,
    traits   => ['Hash'],
    handles  => {
        'set_avg_proc_time' => 'set',
        'get_avg_proc_time' => 'get',
        'del_avg_proc_time' => 'delete',
    }
);

#-------------------------------------------------------------------------------
# Alters the behavior of msg_accept to assign the message to the next available
# client. If no client is available, returns false and does not accept the
# message.
#-------------------------------------------------------------------------------
around 'msg_accept' => sub {
    my ($orig, $self, $msg) = @_;
    my $client = $self->next_client;
    if ($client) {
        $self->$orig($msg);
        $self->assign_message($msg, $client);
    } else {
        croak 'No node is available to process the request';
    }
};

sub on_disconnect {
    my ($self, $client) = @_;
    if ($self->client_exists($client)) {
        $self->del_client($client);
    }
}

#-------------------------------------------------------------------------------
# Assigns a message to a client. By default, this method is called directly
# from msg_accept.
#-------------------------------------------------------------------------------
sub assign_message {
    my ($self, $msg, $client) = @_;
    $self->assignments->{$client}{$msg->id} = 1;
    $self->set_start_time($msg->id, time);
    $self->msg_assigned($msg);
    $client->queue($msg);
}

sub on_msg_complete {
    my ($self, $reply, $client) = @_;

    if ($reply->command ne CMD_ERROR) {
        my $start_time = $self->get_start_time($reply->id);

        push @{$self->processing_times->{$client}}, time - $start_time;
        shift @{$self->processing_times->{$client}}
            if @{$self->processing_times->{$client}} > TRACK_MESSAGES;

        $self->set_avg_proc_time($client, sum(@{$self->processing_times->{$client}}) / TRACK_MESSAGES);
    }

    $self->msg_complete($reply);
    $self->del_start_time($reply->id);
    delete $self->assignments->{$client}{$reply->id};
}

#-------------------------------------------------------------------------------
# Adds a new client object to the manager.
#-------------------------------------------------------------------------------
sub add_client {
    my ($self, $client) = @_;
    $client->add_connect_callbacks(sub { $self->_add_client(@_) });
    $client->add_disconnect_callbacks(sub { $self->del_client(@_) });
    $client->on_complete(sub { $self->on_msg_complete(@_) });
    $client->connect;
    weaken $self;
}

sub _add_client {
    my ($self, $client) = @_;
    LOG("Remote host %s:%d connected.", $client->host, $client->port);
    $self->client_set($client, $client);
    $self->assignments->{$client} = {};
    $self->processing_times->{$client} = [];
    # Note: an arbitrary value is used for avg_processing_time to allow the
    # ranking algorithm to properly evaluate newly attached clients.
    $self->set_avg_proc_time($client, 0.0005);
    weaken $self;
    weaken $client;
}

#-------------------------------------------------------------------------------
# Removes a client object from the manager.
#-------------------------------------------------------------------------------
sub del_client {
    my ($self, $client) = @_;
    LOG("Remote host %s:%d disconnected.", $client->host, $client->port);

    # Fail any tasks assigned to a client that has disconnected. There is no
    # way to know if the task was actually run or not, because the client did
    # not communicate this to us (e.g. from a clean shutdown).
    foreach my $id (keys %{$self->assignments->{$client}}) {
        my $msg   = $self->message->{$id};
        my $error = $msg->reply(CMD_ERROR);
        $error->set_payload('Connection lost to the worker processing the task.');
        $self->msg_complete($error);
    }

    $self->client_del($client);
    $self->del_avg_proc_time($client);
    delete $self->assignments->{$client};
    delete $self->processing_times->{$client};
    $client->close;
}

#-------------------------------------------------------------------------------
# Calculates the amount of processing time required by a tracked service to
# process all items currently assigned to it (+1 for a newly assigned task).
#-------------------------------------------------------------------------------
sub estimated_processing_time {
    my ($self, $client) = @_;
    return $self->get_avg_proc_time($client)
         * (1 + scalar(keys %{$self->assignments->{$client}}));
}

#-------------------------------------------------------------------------------
# Returns the next most available client.
# TODO account for servers which may be inaccessible
#-------------------------------------------------------------------------------
sub next_client {
    my $self = shift;

    my %time;
    $time{$_} = $self->estimated_processing_time($_)
        foreach $self->all_clients;

    return reduce { $time{$a} < $time{$b} ? $a : $b } $self->all_clients;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
