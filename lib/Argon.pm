#-------------------------------------------------------------------------------
# TODO
#   * Worker API for other languages/platforms
#   * Track ping times and report lag between cluster/node
#     * Adjust cluster's node selection to account for lag time
#-------------------------------------------------------------------------------
package Argon;

our $VERSION = '0.01';

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