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

use Argon::Worker;
use Argon::Queue;
use Argon qw/LOG K :commands :defaults/;

extends 'Argon::Server';

has 'concurrency' => (
    is        => 'ro',
    isa       => 'Int',
    required  => 1,
);

has 'max_requests' => (
    is        => 'ro',
    isa       => 'Int',
    predicate => 'counts_requests',
);

has 'manager' => (
    is        => 'ro',
    isa       => 'Str',
    required  => 0,
    predicate => 'is_managed',
);

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

has 'sigint' => (
    is        => 'rw',
    init_arg  => undef,
);

#-------------------------------------------------------------------------------
# Configure responders
#-------------------------------------------------------------------------------
sub BUILD {
    my $self = shift;
    $self->respond_to(CMD_QUEUE, K('request_queue', $self));

    # Add watcher for sigint
    $self->sigint(AnyEvent->signal(
        signal => 'INT',
        cb     => sub {
            LOG('Shutting down workers');

            while ($self->workers > 0) {
                my $worker = $self->checkout;
                $worker->kill_child(1);
            }

            exit 0;
        }
    ));
}

#-------------------------------------------------------------------------------
# Initializes the Node and starts worker processes.
#-------------------------------------------------------------------------------
before 'start' => sub {
    my $self = shift;
    LOG('Starting node with %d workers', $self->concurrency);

    $self->pool(Coro::Channel->new($self->concurrency + 1));
    $self->checkin($self->start_worker)
        for 1 .. $self->concurrency;

    if ($self->is_managed) {
        LOG('Notifying manager of availability');
        $self->notify;
    }
};

#-------------------------------------------------------------------------------
# Sends notifications to configured manager.
#-------------------------------------------------------------------------------
sub notify {
    my $self = shift;
    my ($host, $port) = split ':', $self->manager;

    async {
        LOG('Connecting to manager: %s', $self->manager);
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
                    $msg->set_payload($address);
                    $reply = $stream->send($msg);
                };

                # Connection errors show up during transmission on non-blocking
                # sockets.
                if ($@) {
                    $error = sprintf 'Error connecting to manager: %s', $@;
                }
                # Check validity of response
                elsif ($reply->command == CMD_ACK) {
                    LOG('Connected to manager: %s', $self->manager);
                    $is_connected = 1;
                    $self->service($stream);

                    $stream->monitor(sub {
                        my ($stream, $reason) = @_;
                        LOG('Lost connection to manager');
                        $self->notify;
                    });
                }
                # Error response
                elsif ($reply->command == CMD_ERROR) {
                    my $error = $reply->get_payload;
                    LOG('Manager reported registration error: %s', $error);
                    $is_connected = 1
                        if $error =~ /node is already registered/;
                }
                # Unknown response
                else {
                    my $msg = $reply->get_payload || '<empty>';
                    LOG('Unexpected response from manager: (%d) %s', $reply->command, $msg);
                }
            }

            if (defined $error && $error ne $last_error) {
                LOG($error);
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
# Returns a new AnyEvent::Worker process configured to handle Argon::Message
# tasks.
#-------------------------------------------------------------------------------
sub start_worker {
    my $self   = shift;
    my $worker = Argon::Worker->new();
    $worker->start();
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
# Accepts a message and processes it in the pool.
#-------------------------------------------------------------------------------
sub request_queue {
    my ($self, $msg, $stream) = @_;

    my $worker = $self->checkout;

    # Replace worker if necessary
    if (   $self->counts_requests
        && $worker->request_count >= $self->max_requests)
    {
        $worker->kill_child;
        $worker = $self->start_worker;
    }

    # Process the task in a worker
    my $reply = $worker->process($msg);

    # Return worker to the pool
    $self->checkin($worker);

    return $reply;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;