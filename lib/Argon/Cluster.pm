package Argon::Cluster;

use strict;
use warnings;
use Carp;

use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

use Coro;
use List::Util qw/first/;
use Argon::Stream;
use Argon::Server;
use Argon::NodeTracker;
use Argon qw/LOG K :commands/;

extends 'Argon::Server';

#-------------------------------------------------------------------------------
# Stores nodes as a hash of address => stream.
#-------------------------------------------------------------------------------
has 'node' => (
    is       => 'ro',
    isa      => 'HashRef[Argon::Stream]',
    init_arg => undef,
    default  => sub {{}},
    traits   => ['Hash'],
    handles  => {
        set_node   => 'set',
        get_node   => 'get',
        del_node   => 'delete',
        has_node   => 'exists',
        nodes      => 'values',
        node_pairs => 'kv',
        node_addrs => 'keys',
        num_nodes  => 'count',
    }
);

#-------------------------------------------------------------------------------
# Stores NodeTrackers for each node address.
#-------------------------------------------------------------------------------
has 'tracking' => (
    is       => 'ro',
    isa      => 'HashRef[Argon::NodeTracker]',
    init_arg => undef,
    default  => sub {{}},
    traits   => ['Hash'],
    handles  => {
        set_tracking => 'set',
        get_tracking => 'get',
        del_tracking => 'delete',
        has_tracking => 'exists',
    }
);

#-------------------------------------------------------------------------------
# Configures responders
#-------------------------------------------------------------------------------
sub BUILD {
    my $self = shift;
    $self->respond_to(CMD_ADD_NODE, K('request_add_node', $self));
    $self->respond_to(CMD_QUEUE,    K('request_queue',    $self));
}

#-------------------------------------------------------------------------------
# Adds a little logging to start up.
#-------------------------------------------------------------------------------
before 'start' => sub {
    my $self = shift;
    LOG('Starting cluster manager');
};

#-------------------------------------------------------------------------------
# Returns the next "most available" node, based on current load and average
# processing time for each node.
#-------------------------------------------------------------------------------
sub next_node {
    my $self  = shift;
    my @nodes = sort {
            $self->get_tracking($a)->avg_proc_time
        <=> $self->get_tracking($b)->avg_proc_time
    } $self->nodes;
    return first { $self->get_tracking($_)->capacity > 0 } @nodes;
}

#-------------------------------------------------------------------------------
# Registers a worker node. Note that workers are keyed to the host and port on
# which they listen for requests themselves, rather than the host and port with
# which they actually connected to the cluster. This is because the connecting
# host and port can vary wildly but the listening address uniquely identifies
# the node.
#-------------------------------------------------------------------------------
sub register_node {
    my ($self, $stream, $address, $workers) = @_;

    # If the node is already registered, it signifies that the node was
    # disconnected and the cluster has not yet detected it. In that case, the
    # node's existing records may be transferred.
    if (exists $self->node->{$address}) {
        $self->unregister_node($stream);
    }

    $self->set_node($address, $stream);
    $self->set_tracking($stream, Argon::NodeTracker->new(
        workers  => $workers,
        tracking => $Argon::TRACK_MESSAGES,
    ));

    LOG('Registered worker node %s', $address);

    $stream->monitor(K('unregister_node', $self));
}

#-------------------------------------------------------------------------------
# Unregisters a stream as a node.
#-------------------------------------------------------------------------------
sub unregister_node {
    my ($self, $stream) = @_;
    my $address = first { $self->get_node($_) eq $stream } $self->node_addrs;
    if (defined $address) {
        $self->del_tracking($stream);
        $self->del_node($address);
        $stream->close;
        LOG('Unregistered worker node %s', $address);
    }
}

#-------------------------------------------------------------------------------
# Request handler for CMD_ADD_NODE.
#-------------------------------------------------------------------------------
sub request_add_node {
    my ($self, $msg, $stream) = @_;
    my $payload = $msg->get_payload;
    my $address = $payload->{address};
    my $workers = $payload->{workers};

    eval { $self->register_node($stream, $address, $workers) };

    if ($@) {
        my $reply = $msg->reply(CMD_ERROR);
        $reply->set_payload($@);
        return $reply;
    } else {
        $self->stop_service($stream->address);
        return $msg->reply(CMD_ACK);
    }
}

#-------------------------------------------------------------------------------
# Request handler for CMD_QUEUE. Forwards messages to the most available node.
#-------------------------------------------------------------------------------
sub request_queue {
    my ($self, $msg, $stream) = @_;

    if ($self->num_nodes == 0) {
        my $reply = $msg->reply(CMD_ERROR);
        $reply->set_payload('Unable to service requests: no worker nodes are registered.');
        return $reply;
    }

    if (defined(my $node = $self->next_node)) {
        $self->get_tracking($node)->start_request($msg->id);
        my $address = $node->address;
        my $reply   = eval { $node->send($msg) };

        # An error signifies a lost connection to the node. Unregister
        # the node, then send an error response to the client (since there
        # is no way to know whether or not the request was successfully
        # processed before the connection dropped.)
        if ($@) {
            my $error = $@;
            LOG('Error (%s): %s', $address, $@)
                unless Argon::Stream::is_connection_error($@);

            $self->unregister_node($node);
            $reply = $msg->reply(CMD_ERROR);
            $reply->set_payload(sprintf(
<<END
Lost connection to worker node while processing request. Verify task state and
retry if necessary. Error: %s
END
                , $error
            ));
        } else {
            $self->get_tracking($node)->end_request($msg->id);
        }

        return $reply;
    } else {
        my $reply = $msg->reply(CMD_REJECTED);
        $reply->set_payload('No workers available to handle request. Please try again after a short delay.');
        return $reply;
    }
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;