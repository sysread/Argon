#-------------------------------------------------------------------------------
# TODO
#   * Change name
#   * Chaos monkey
#   * Better logging
#   * Better configuration:
#     * Change some parameters from constants to variables
#     * File-based config - for pre-packaged bin scripts
#   * Trap sigint for clean shutdown
#-------------------------------------------------------------------------------
package Argon;

our $VERSION = '0.001';

use strict;
use warnings;
use Carp;
use namespace::autoclean;
use POSIX        qw/strftime/;
use Scalar::Util qw/weaken/;

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
);

our @EXPORT_OK = map { @$_ } values %EXPORT_TAGS;
our @EXPORT    = qw/LOG K/;

#-------------------------------------------------------------------------------
# DEBUG flag
#-------------------------------------------------------------------------------
our $DEBUG = 0;

#-------------------------------------------------------------------------------
# Strips an error message of line number and file information.
#-------------------------------------------------------------------------------
sub error {
    my $msg = shift;
    $msg =~ s/ at (.+?) line \d+.//gsm;
    $msg =~ s/\s+$//gsm;
    $msg =~ s/^\s+//gsm;
    return $msg;
}

#-------------------------------------------------------------------------------
# Emits a message to STDERR in a consistent fashion. Accepts arguments
# identically to sprintf.
#-------------------------------------------------------------------------------
sub LOG {
    my ($format, @args) = @_;
    chomp $format;
    my $msg = error(sprintf($format, @args));
    my $ts  = strftime("%Y-%m-%d %H:%M:%S", localtime);
    warn sprintf("[%s] [%d] %s\n", $ts, $$, $msg);
}

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
our $LISTEN_QUEUE_SIZE  = 128;
our $CHUNK_SIZE         = 1024 * 4;
our $EOL                = "\0";
our $MESSAGE_SEPARATOR  = ' ';
our $TRACK_MESSAGES     = 10;   # number of message times to track for computing avg processing time at a host
our $POLL_INTERVAL      = 2;    # number of seconds between polls for connectivity between cluster/node

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

1;