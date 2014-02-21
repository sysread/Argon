package Argon;

our $VERSION = '0.07';

use strict;
use warnings;
use namespace::autoclean;
use Carp;
use AnyEvent::Log;
use Const::Fast;
use Coro;
use Scalar::Util qw(weaken);
use POSIX qw(strftime);

require Exporter;
use base qw/Exporter/;

our %EXPORT_TAGS = (
    # Priorities
    priorities => [qw($PRI_HIGH $PRI_NORMAL $PRI_LOW)],

    # Command verbs and responses
    commands => [qw(
        $CMD_PING $CMD_QUEUE $CMD_REGISTER
        $CMD_ACK $CMD_COMPLETE $CMD_ERROR $CMD_REJECTED
    )],

    logging => [qw(DEBUG INFO WARN ERROR)],
);

our @EXPORT_OK = ('K', map { @$_ } values %EXPORT_TAGS);

#-------------------------------------------------------------------------------
# Returns a new function suitable for use as a callback. This is useful to pass
# instance methods as callbacks without leaking references.
#
# Inputs:
#     $fn      : CODE reference or function name
#     $context : class name or object instance
#     @args    : other arguments to pass to $fn
#
# Output:
#     CODE reference
#
# Examples:
#     # Using a function reference
#     my $cb = K(\&on_connection);
#
#     # Using an instance method
#     my $cb = K('on_connection', $client);
#
#     # Using a class method
#     my $cb = K('on_connection', 'ClientClass');
#
#     # With extra arguments
#     my $cb = K('on_connection', $client, 'x', 'y', 'z');
#-------------------------------------------------------------------------------
sub K {
    my ($fn, $context, @args) = @_;

    croak "unknown method $fn"
        if !ref $context
        || !$context->can($fn);

    weaken $context;
    my $k = $context->can($fn);

    return sub {
        unshift @_, $context, @args;
        goto $k;
    };
}

#-------------------------------------------------------------------------------
# Defaults
#-------------------------------------------------------------------------------
our $EOL             = "\n"; # end of line/message character(s)
our $MSG_SEPARATOR   = ' ';  # separator between parts of a message (command, priority, payload, etc)
our $TRACK_MESSAGES  = 10;   # number of message times to track for computing avg processing time at a host
our $POLL_INTERVAL   = 5;    # number of seconds between polls for connectivity between cluster/node
our $CONNECT_TIMEOUT = 5;    # number of seconds after which a stream times out attempting to connect

#-------------------------------------------------------------------------------
# Priorities
#-------------------------------------------------------------------------------
const our $PRI_HIGH   => Coro::PRIO_HIGH;
const our $PRI_NORMAL => Coro::PRIO_NORMAL;
const our $PRI_LOW    => Coro::PRIO_MIN;

#-------------------------------------------------------------------------------
# Commands
#-------------------------------------------------------------------------------
const our $CMD_PING     => 0;  # Add a node to a cluster
const our $CMD_QUEUE    => 1;  # Queue a message
const our $CMD_REGISTER => 2;  # Add a node to a cluster

const our $CMD_ACK      => 3;  # Acknowledgement (respond OK)
const our $CMD_COMPLETE => 4;  # Response - message is complete
const our $CMD_ERROR    => 5;  # Response - error processing message or invalid message format
const our $CMD_REJECTED => 6;  # Response - no available capacity for handling tasks

#-------------------------------------------------------------------------------
# Strips an error message of line number and file information.
#-------------------------------------------------------------------------------
sub error {
    my $msg = shift;
    $msg =~ s/ at (.+?) line \d+.//gsm;
    $msg =~ s/eval {...} called$//gsm;
    $msg =~ s/\s+$//gsm;
    $msg =~ s/^\s+//gsm;
    return $msg;
}

const our $LOG_ERROR => 1;
const our $LOG_WARN  => 2;
const our $LOG_INFO  => 4;
const our $LOG_DEBUG => 8;

our $LOG_LEVEL = $LOG_ERROR | $LOG_WARN | $LOG_INFO;

sub LOG {
    my $lvl = shift;
    my $msg = error(sprintf(shift, @_));
    my $pid = $$;
    my $ts  = strftime("%Y-%m-%d %H:%M:%S", localtime);
    warn sprintf("[%s] [% 6d] [%s] %s\n", $ts, $pid, $lvl, $msg);
}

sub DEBUG { LOG('DEBUG', @_) if $LOG_LEVEL & $LOG_DEBUG }
sub INFO  { LOG('INFO',  @_) if $LOG_LEVEL & $LOG_INFO  }
sub WARN  { LOG('WARN',  @_) if $LOG_LEVEL & $LOG_WARN  }
sub ERROR { LOG('ERROR', @_) if $LOG_LEVEL & $LOG_ERROR }

1;
__DATA__

=head1 NAME

Argon

=head1 RATIONALE

Argon is a distributed processing platform built for Perl. It is built to
provide a simple system for building radically scalable software while at the
same time ensuring a high level of robustness and redundancy.

=head1 MANAGERS

Managers are entry points into the distributed network. They accept tasks from
clients and route them to workers, then deliver the results back to the client.

Managers keep track of the nodes available on the network, ensuring that work
is distributed in a balanced and efficient manner to achieve the highest
throughput. If a worker becomes unavailable, the load is automatically shifted
to the rest of the network. If the worker becomes available again, it will be
picked up and the manager will start shifting load to it as necessary.

Managers are started with C<argon>:

    argon --manager --port 8000 --host mgrhost

See L<bin/argon>.

=head1 WORKERS

Workers are essentially a managed pool of Perl processes. Managers route tasks
to workers, who distribute them among their pool of Perl processes, then return
the results to the manager (who in turn ensures it gets back to the client).

Once started, the worker notifies the manager that it is available and can
immediately start handling tasks as needed. If for any reason the worker loses
its connection to the manager, it will attempt to reestablish the connection
until it is again in contact with its manager.

Argon workers are uniform. There are no "channels" for individual types of
tasks. All workers can handle any type of task. This ensures that no classes of
task are starved of resources while other types have underutilized workers.

Workers are started with C<argon>:

    argon --worker --port 8001 --host workerhost --manager somehost:8000

By default, a worker will start a number of Perl processes that correlates to
the number of CPUs on the system. This can be overridden with the C<--workers>
option.

    argon --worker --port 8001 --host workerhost --manager somehost:8000 --workers 8

See L<bin/argon>.

=head1 CLIENTS

Clients connect to the manager (or, if desired, directly to a "stand-alone"
worker that was started without the C<--manager> option). Tasks can be
launched in two different ways.

The first method is to send a task and wait for the results. Note that
Argon uses Coro, so "waiting" for the result means that the current thread
of execution yields until the result is ready, at which point it is awoken.

    use Argon::Client;

    my $client = Argon::Client->new(host => "mgrhost", port => 8000);
    my $result = $client->queue(
        # Code to execute
        sub {
            my ($x, $y) = @_;
            return $x + $y;
        },
        # Arguments to pass that code
        [4, 7],
    );

Tasks can also be sent off to the network in the background, allowing the
thread of execution to continue until a point where synchronization is
required.

    use Argon::Client;

    my $client = Argon::Client->new(host => "mgrhost", port => 8000);

    # Ship the task off and get a function that, when called, waits for
    # the result and returns it.
    my $deferred = $client->defer(
        # Code to execute
        sub {
            my ($x, $y) = @_;
            return $x + $y;
        },
        # Arguments to pass that code
        [4, 7],
    );

    # Synchronize to get the result
    my $result = $deferred->();

Errors thrown in the execution of the task are trapped and re-thrown by
the client when the result is returned. In the case of C<queue> that is done
when call returns. In the case of C<defer>, it happens when the deferred
result is synchronized.

See L<Argon::Client>.

=head1 SCALABILITY

Argon is designed to make scalability simple and easy. Simply add more workers
to boost the resources available to all applications utilizing the network.

Because Argon workers are all uniform, adding a new worker node guarantees a
linear boost in resources available to all client applications. For example,
given identical tasks on a network with two worker nodes, each running the same
number of processes, adding another worker would increase throughput by 50%.
Doubling the number of workers would increase throughput by 100%.

=head1 AUTHOR

Jeff Ober <jeffober@gmail.com>
