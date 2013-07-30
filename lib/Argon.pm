#-------------------------------------------------------------------------------
# TODO
#   * Habeus Corpus
#   * Worker API for other languages/platforms
#   * Track ping times and report lag between cluster/node
#     * Adjust cluster's node selection to account for lag time
#-------------------------------------------------------------------------------
package Argon;

our $VERSION = '0.04';

use strict;
use warnings;
use Carp;
use namespace::autoclean;

use Coro;
use Coro::Channel;
use AnyEvent::Util qw/fh_nonblocking/;
use POSIX          qw/strftime/;
use Scalar::Util   qw/weaken/;

require Exporter;
use base qw/Exporter/;

our %EXPORT_TAGS = (
    'priorities' => [qw/
        PRI_MAX
        PRI_HIGH
        PRI_NORMAL
        PRI_LOW
        PRI_MIN
    /],

    # Command verbs and responses
    'commands' => [qw/
        CMD_ACK
        CMD_QUEUE
        CMD_REJECTED
        CMD_COMPLETE
        CMD_ERROR
        CMD_ADD_NODE
        CMD_PING
    /],

    'logging' => [qw/
        INFO
        WARN
        ERROR
    /],
);

our @EXPORT_OK = map { @$_ } values %EXPORT_TAGS;
our @EXPORT    = qw/K/;

#-------------------------------------------------------------------------------
# Returns a new function suitable for use as a callback. This is useful to pass
# instance methods as callbacks without leaking references.
#
# Inputs:
#     $fn      : CODE reference or function name
#     $context : class name or object instance
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
#-------------------------------------------------------------------------------
sub K {
    my ($fn, $context) = @_;

    croak "unknown method $fn"
        if !ref $context
        || !$context->can($fn);

    my $callback = sub {
        $context->can($fn)->($context, @_);
    };

    weaken $context;
    return $callback;
}

#-------------------------------------------------------------------------------
# Defaults
#-------------------------------------------------------------------------------
our $LISTEN_QUEUE_SIZE  = 128;      # queue size for listening sockets
our $TIMEOUT            = 3;        # number of seconds to wait for a read/write op on a socket
our $CHUNK_SIZE         = 1024 * 4; # number of bytes to read at a time
our $EOL                = "\n";     # end of line/message character(s)
our $MESSAGE_SEPARATOR  = ' ';      # separator between parts of a message (command, priority, payload, etc)
our $TRACK_MESSAGES     = 10;       # number of message times to track for computing avg processing time at a host
our $POLL_INTERVAL      = 2;        # number of seconds between polls for connectivity between cluster/node
our $CHAOS_MONKEY       = 0;        # percent chance of causing service to die every 30 seconds (set to zero to disable)
                                    # See: http://www.codinghorror.com/blog/2011/04/working-with-the-chaos-monkey.html

#-------------------------------------------------------------------------------
# Debug levels
#-------------------------------------------------------------------------------
use constant DEBUG_INFO  => 1 << 0;
use constant DEBUG_WARN  => 1 << 1;
use constant DEBUG_ERROR => 1 << 2;

#-------------------------------------------------------------------------------
# Commands
#-------------------------------------------------------------------------------
use constant CMD_ACK      => 0;  # Acknowledgement (respond OK)
use constant CMD_QUEUE    => 1;  # Queue a message
use constant CMD_COMPLETE => 2;  # Response - message is complete
use constant CMD_REJECTED => 3;  # Response - message was rejected
use constant CMD_ERROR    => 4;  # Response - error processing message or invalid message format
use constant CMD_ADD_NODE => 5;  # Add a node to a cluster
use constant CMD_PING     => 6;  # Add a node to a cluster

#-------------------------------------------------------------------------------
# Priorities
#-------------------------------------------------------------------------------
use constant PRI_MAX    => 0;
use constant PRI_HIGH   => 1;
use constant PRI_NORMAL => 2;
use constant PRI_LOW    => 3;
use constant PRI_MIN    => 4;

#-------------------------------------------------------------------------------
# DEBUG bitmask
#-------------------------------------------------------------------------------
our $DEBUG = DEBUG_INFO | DEBUG_WARN | DEBUG_ERROR;

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

#-------------------------------------------------------------------------------
# Emits a message to STDERR in a consistent fashion. Accepts arguments
# identically to sprintf. Messages are queued until the output handle is
# writable.
#
# TODO: more configurable
#-------------------------------------------------------------------------------
sub LOG ($@) {
    my ($format, @args) = @_;

    if ($format =~ /(?<!%)%/) {
        foreach my $arg (@args) {
            carp 'Use of uninitialized value in LOG'
                unless defined $arg;
        }
    }

    chomp $format;
    my $msg = error(sprintf($format, @args));
    my $ts  = strftime("%F %T", localtime);
    warn sprintf("[%s] [%d] %s\n", $ts, $$, $msg);
}

#-------------------------------------------------------------------------------
# Logging functions
#-------------------------------------------------------------------------------
sub INFO  ($@) { goto \&LOG if $DEBUG & DEBUG_INFO  }
sub WARN  ($@) { goto \&LOG if $DEBUG & DEBUG_WARN  }
sub ERROR ($@) { goto \&LOG if $DEBUG & DEBUG_ERROR }

#-------------------------------------------------------------------------------
# Chaos monkey
#-------------------------------------------------------------------------------
sub CHAOS {
    if ($CHAOS_MONKEY) {
        srand time;
        while (1) {
            Coro::AnyEvent::sleep(30);
            my $chance = rand 100;
            if ($chance <= $CHAOS_MONKEY) {
                ERROR 'The chaos moneky strikes! (rolled %d)', $chance;
                exit 1;
            } else {
                INFO 'Chaos monkey rolled %d', $chance;
            }
        }
    }
}

1;
=pod

=head1 NAME

Argon

=head1 SYNOPSIS

    # Start a manager on port 8000
    cluster -p 8000
    
    # Start a stand-alone node with 4 workers on port 8000
    node -w 4 -p 8000
    
    # Start a node and attach to a manager
    node -w 4 -p 8001 -m somehost:8000

=head1 DESCRIPTION

Argon is a multi-platform distributed task processing system, designed with the
goal of making the creation of a robust system simple.

=head1 USAGE

Argon systems are build from two pieces: managers and nodes. A manager (or
cluster) is a process that manages one or more nodes. A node is a process that
manages a pool of worker processes. A node can be stand-alone (unmanaged) or
have a single manager. A manager does not need to know about nodes underneath
it; nodes that are started with the -m parameter register their presence with
the manager. If the node goes down or becomes unavailable, the manager will
automatically account for this and route tasks to other nodes.

=head2 Stand-alone nodes

A stand-alone node does not register with a manager. It can accept tasks
directly from clients. Tasks will be assigned or queued to worker processes.
The number of worker processes is controlled with the -w parameter.

To start a basic node with 4 worker processes, listening on port 8000, use:

    node -w 4 -p 8000

Note that by default, 4 workers are started, so -w isn't truly necessary here.

A node must know where to find any code that is used in the tasks it is given.
This is accomplished with the -i parameter:

    node -p 8000 -i /path/to/libs -i /path/to/otherlibs

As with any long-running process, workers started by the node may end up
consuming a significant amount of memory. To address this, the node accepts the
-r parameter, which controls the max number of tasks a worker may handle before
it is restarted to release any memory it is holding. By default, workers may
handle an indefinite number of tasks.

    node -p 8000 -i /path/to/libs -r 250

=head2 Managed nodes

A managed node is one that registers itself with a manager/cluster process. The
manager is added with the -m parameter:

    node -p 8000 -i /path/to/libs -r 250 -m manager:8000

Once started, the node will connect to the server I<manager> on port I<8000>
and attempt to register. Once registered, the node is immediately available to
begin handling requests from the manager.

Although the node will technically still accept requests directly from clients
in managed mode, this is bad practice and will cause inaccuracy in the
manager's routing algorithm.

=head2 Managers

Managers (also called clusters) are servers that route tasks to the most
available node. This is determined by analyzing the average processing time for
a given node and comparing it with the number of tasks it is currently
assigned.

Managers are started very simply:

    cluster -p 8000

Managers do not execute arbitrary code and therefore do not need to know where
any libraries are stored.

=head2 Queues

Nodes and managers both maintain a bounded queue. As requests come in, they are
added to the queue. If the queue is full, the task is rejected.

The reason for this is that when the system is under high load this avoids the
creation of a large backlog of tasks. A large backlog acts like a traffic jam,
affecting system responsiveness for a much longer period as the backlog is
cleared before it returns to normal operation.

Instead, rejected tasks are automatically retried by the client using an
algorithm designed to prevent overloading the system with retry requests. By
default, the client will retry an unlimited number of times (although this is
configurable).

The size of the queue is controlled with -l (lower-case L, for limit)
parameter. This parameter applies to both nodes and managers. By default, it is
set to 64, although this value may not be optimal for your hardware and worker
count. A good rule of thumb is to allow 8-16 slots in the queue per worker. For
a node, this means the number of workers directly managed by the ndoe. For a
cluster, this means the total number of workers expected to be available to it
through its registered nodes.

=head2 Clients

The L<Argon::Client> class provides a simple way to converse with an Argon
system:

    use Argon::Client;

    my $client = Argon::Client->new(port => 8000, host => 'some.host.name');
    $client->connect;
    my $result = $client->process(
        class  => 'Some::Class', # with Argon::Role::Task
        params => [ foo => 'bar', baz => 'bat' ],
    );

The only requirement is that all nodes in the system know where C<Some::Class>
is located. See the -i parameter above to node.

=head2 Multiplexing clients

L<Argon::Client/process> does not return until the task has been completed.
However, Argon is implemented using L<Coro>, allowing the process method to
yield to other threads while it waits for its result. This makes it extremely
simple to process multiple tasks through multiple clients at the same time.

    use Coro;
    use Argon::Client;

    # Assume a list of tasks, where each element is an array ref of C<[$class,
    # $params]>.
    my @tasks;

    # Create a simple pool of client objects
    my $clients = Coro::Channel->new();
    for (1 .. 4) {
        my $client = Argon::Client->new(port => 8000, host => 'some.host.name');
        $clients->put($client);
    }

    # Loop over the task list
    my @pending;
    while (my ($class, $params) = pop @tasks) {
        # Get the next available client. This blocks until a client is
        # available from the Coro::Channel ($clients).
        my $client = $clients->get();

        # Send the client the task in a Coro thread, storing the return value
        # in @pending.
        push @pending, async {
            # Send the task
            my $result = $client->process(
                class  => $class,
                params => $params,
            );

            # Release the client back into the pool
            $clients->put($client);

            # Do something with result
            ...
        };
    }

    # Wait on each thread to complete
    $_->join foreach @pending;

See bin/bench for a more robust implementation.

=head2 Task design

Tasks must use the L<Argon::Role::Task> class. Tasks will be created by
instantiating the class with the parameters provided to the
L<Argon::Client/process> method. Task classes must also have a C<run>
method which performs the task's work and returns the result.

=head2 CAVEATS

As with all such systems, performance is greatly affected by the size of the
messages sent. Therefore, it is recommended to keep as much data used by a task
as possible in a database or other network-accessible storage location. For
example, design your task such that it accepts an id that can be used to access
the task data from a database, and have it return an id which can be used to
access the result.

=head1 AUTHOR

Jeff Ober L<mailto:jeffober@gmail.com>

=head1 LICENSE

BSD license

=cut
