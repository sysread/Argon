package Argon;

our $VERSION = '0.10';

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
