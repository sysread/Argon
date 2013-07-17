#-------------------------------------------------------------------------------
# Argon::Node is a TCP/IP server which accepts Argon::Messages and processes
# them within a configurable process pool.
#-------------------------------------------------------------------------------
package Argon::Node;

use strict;
use warnings;
use Carp;

use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

use Coro;
use Coro::AnyEvent;
use AnyEvent;

use Argon::Process;
use Argon qw/K :commands :logging/;

extends 'Argon::Server';

#-------------------------------------------------------------------------------
# Number of worker processes to maintain
#-------------------------------------------------------------------------------
has 'concurrency' => (
    is        => 'ro',
    isa       => 'Int',
    required  => 1,
);

#-------------------------------------------------------------------------------
# Max requests per worker process before restarting the process to reclaim
# memory
#-------------------------------------------------------------------------------
has 'max_requests' => (
    is        => 'ro',
    isa       => 'Int',
    predicate => 'counts_requests',
);

#-------------------------------------------------------------------------------
# Argon::Cluster to notify of availability
#-------------------------------------------------------------------------------
has 'manager' => (
    is        => 'ro',
    isa       => 'Str',
    predicate => 'is_managed',
);

#-------------------------------------------------------------------------------
# Maintains the pool of worker processes, allowing code to block until a
# worker is available to handle a job
#-------------------------------------------------------------------------------
has 'pool' => (
    is        => 'rw',
    isa       => 'Coro::Channel',
    init_arg  => undef,
    handles   => {
        'checkin'  => 'put',
        'checkout' => 'get',
        'workers'  => 'size',
    }
);

#-------------------------------------------------------------------------------
# Configure responders
#-------------------------------------------------------------------------------
sub BUILD {
    my $self = shift;
    $self->respond_to(CMD_QUEUE, K('request_queue', $self));
}

#-------------------------------------------------------------------------------
# Initializes the Node and starts worker processes.
#-------------------------------------------------------------------------------
before 'start' => sub {
    my $self = shift;
    INFO 'Starting node with %d workers', $self->concurrency;

    $self->pool(Coro::Channel->new($self->concurrency + 1));
    $self->checkin($self->start_worker)
        for 1 .. $self->concurrency;

    if ($self->is_managed) {
        INFO 'Notifying manager of availability';
        $self->notify;
    }
};

#-------------------------------------------------------------------------------
# Shut down workers
# TODO fail pending tasks
#-------------------------------------------------------------------------------
before 'shutdown' => sub {
    my $self = shift;
    INFO 'Shutting down workers';
    while ($self->workers > 0) {
        my $worker = $self->checkout;
        $self->stop_worker($worker, 1);
    }
};

#-------------------------------------------------------------------------------
# Sends notifications to configured manager.
#-------------------------------------------------------------------------------
sub notify {
    my $self = shift;
    my ($host, $port) = split ':', $self->manager;

    async {
        INFO 'Connecting to manager: %s', $self->manager;
        my $is_connected = 0;
        my $attempts     = 0;
        my $address      = sprintf '%s:%d', $self->host, $self->port;
        my $last_error   = ''; # prevent the same connection error from being reported multiple times

        until ($is_connected) {
            ++$attempts;

            # Connect to manager
            my $stream = eval { Argon::Stream->connect(host => $host, port => $port) };
            my $error;

            if ($@) {
                $error = sprintf 'Unable to reach manager (%s): %s', $address, $@;
            } else {
                # Send registration packet
                my $reply;
                eval {
                    my $msg = Argon::Message->new(command => CMD_ADD_NODE);

                    $msg->set_payload({
                        address => $address,
                        workers => $self->concurrency,
                    });

                    $reply = $stream->send($msg);
                };

                # Connection errors show up during transmission on non-blocking
                # sockets.
                if ($@) {
                    $error = sprintf 'Error connecting to manager: %s', $@;
                    die $error;
                }
                # Check validity of response
                elsif ($reply->command == CMD_ACK) {
                    INFO 'Connected to manager: %s', $self->manager;
                    $is_connected = 1;
                    $self->service($stream);

                    $stream->monitor(sub {
                        my ($stream, $reason) = @_;
                        WARN 'Lost connection to manager';
                        $self->notify;
                    });
                }
                # Error response
                elsif ($reply->command == CMD_ERROR) {
                    my $error = $reply->get_payload;
                    if ($error =~ /node is already registered/) {
                        INFO 'Re-registered with manager';
                        $is_connected = 1;
                    } else {
                        ERROR 'Manager reported registration error: %s', $error;
                    }
                }
                # Unknown response
                else {
                    my $msg = $reply->get_payload || '<empty>';
                    ERROR 'Unexpected response from manager: (%d) %s', $reply->command, $msg;
                }
            }

            if (defined $error && $error ne $last_error) {
                ERROR $error;
                $last_error = $error;
            }

            # Schedule another retry
            unless ($is_connected) {
                my $delay = log($attempts);
                Coro::AnyEvent::sleep($delay);
            }
        }
    };
}

#-------------------------------------------------------------------------------
# Returns a new AnyEvent::Process configured to handle Argon::Message tasks.
#-------------------------------------------------------------------------------
sub start_worker {
    my $self   = shift;
    my $worker = Argon::Process->new();
    $worker->spawn();
    return $worker;
}

#-------------------------------------------------------------------------------
# Kills an individual worker process and removes it from internal tracking.
# Assumes that the worker process has been checked out of the pool. If the
# worker process is still in the pool, the results could be unexpected!
#-------------------------------------------------------------------------------
sub stop_worker {
    my ($self, $worker, $block) = @_;
    $worker->kill($block);
}

#-------------------------------------------------------------------------------
# Accepts a message and processes it in the pool.
#-------------------------------------------------------------------------------
sub request_queue {
    my ($self, $msg, $stream) = @_;
    my $worker = $self->checkout;

    # Replace worker if necessary
    if (   $self->counts_requests
        && $worker->request_count >= $self->max_requests)
    {
        $self->stop_worker($worker, 0);
        $worker = $self->start_worker;
    }

    # Process the task in a worker
    my $reply = $worker->process($msg);

    # Return worker to the pool
    $self->checkin($worker);

    return $reply;
}

;
__PACKAGE__->meta->make_immutable;

=pod

=head1 NAME

Argon::Node

=head1 SYNOPSIS

    use EV; # use libev as event loop (see AnyEvent for details)
    use Argon::Node;

    my $node = Argon::Node->new(
        port         => 8000,
        host         => 'localhost',
        queue_limit  => 128,
        concurrency  => 8,
        max_requests => 512,
        manager      => 'otherhost:8000',
    );

    $node->start;

=head1 DESCRIPTION

Argon::Node is the workhorse of an Argon cluster. It maintains a pool of worker
processes to which it delegates incoming requests. Nodes may be configured as a
standalone service or as a member of a larger Argon cluster.

Nodes monitor their connection to the cluster and will automatically reconnect
when a cluster becomes temporarily unavailable.

Argon::Node inherits Argon::Server.

=head1 METHODS

=head2 new(host => ..., port => ...)

Creates a new Argon::Node. The node does not automatically start listening.

Parameters:

=over

=item host

Required. Hostname of the device to listen on.

=item port

Required. Port number on which to listen.

=item queue_limit

Required. Size of the message queue. Any messages that come in after the queue
has been filled with be rejected. It is up to the client to retry rejected
messages.

Setting a large queue_limit will decrease the number of rejected messages but
will make the server vulnerable to spikes in traffic density (e.g. a DOS attack
or an unanticipated increase in traffic). Setting a lower queue_limit ensures
that high traffic volumes do not cause the server to become bogged down and
unresponsive. Note that in either case, the client will be waiting a longer
time for a response; in the second case, however, the server will bounce back
from traffic spikes much more quickly than in the first.

=item concurrency

Required. Number of worker processes to maintain.

=item max_requests

Optional. Maximum number of requests any worker process may handle before it is
terminated and a new process is spawned to replace it. This saves memory but may
result in spiky responsiveness if set too low.

=item manager

Optional. Configures the Node to notify a manager of its availability to handle
requests. Without this parameter, the Node is configured as a standalone server.

=back

=head2 start

Starts the server. Blocks until I<shutdown> is called.

=head2 shutdown

Causes the server to stop at the next available cycle. Onced called, each client
will be disconnected and any pending messages will be failed.

=head1 AUTHOR

Jeff Ober L<mailto:jeffober@gmail.com>

=head1 LICENSE

BSD license

=cut

1;
