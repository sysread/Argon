#-------------------------------------------------------------------------------
# TODO
#   * Debug levels (higher levels log less, remove stack traces from warnings, etc.)
#   * Clearing out completed messages that were never picked up
#   * Chaos monkey
#-------------------------------------------------------------------------------
package Argon;

our $VERSION = '0.001';

use strict;
use warnings;
use Carp;
use namespace::autoclean;
use POSIX qw/strftime/;

require Exporter;
use base qw/Exporter/;

our %EXPORT_TAGS = (
    # Defaults and parameters
    'defaults' => [qw/
        LISTEN_QUEUE_SIZE
        SOCKET_TIMEOUT
        CHUNK_SIZE
        EOL
        MESSAGE_SEPARATOR
        TRACK_MESSAGES
        POLL_INTERVAL
    /],

    # Priorities
    'priorities' => [qw/PRI_REAL PRI_HIGH PRI_NORMAL PRI_LOW PRI_IGNORE/],

    'statuses' => [qw/STATUS_QUEUED STATUS_ASSIGNED STATUS_COMPLETE/],

    # Command verbs and responses
    'commands'   => [qw/
        CMD_ACK
        CMD_ID
        CMD_QUEUE
        CMD_REJECTED
        CMD_COMPLETE
        CMD_ERROR
        CMD_ADD_NODE
        CMD_DEL_NODE
        CMD_SHUTDOWN
    /],
);

our @EXPORT_OK = map { @$_ } values %EXPORT_TAGS;
our @EXPORT    = qw/LOG/;

sub LOG {
    my ($format, @args) = @_;
    chomp $format;
    my $ts = strftime("%Y-%m-%d %H:%M:%S", localtime);
    warn sprintf("[%d] [%s] $format\n", $$, $ts, @args);
}

#-------------------------------------------------------------------------------
# Defaults
#-------------------------------------------------------------------------------
use constant LISTEN_QUEUE_SIZE  => 128;
use constant SOCKET_TIMEOUT     => 30;
use constant CHUNK_SIZE         => 1024 * 4;
use constant EOL                => "\015\012";
use constant MESSAGE_SEPARATOR  => ' ';
use constant TRACK_MESSAGES     => 10;   # number of message times to track for computing avg processing time at a host
use constant POLL_INTERVAL      => 0.20; # seconds between polls for backlog (client)

#-------------------------------------------------------------------------------
# Priorities
#-------------------------------------------------------------------------------
use constant PRI_REAL    => 0;
use constant PRI_HIGH    => 1;
use constant PRI_NORMAL  => 2;
use constant PRI_LOW     => 3;
use constant PRI_IGNORE  => 4;

#-------------------------------------------------------------------------------
# Message states
#-------------------------------------------------------------------------------
use constant STATUS_QUEUED   => 0;
use constant STATUS_ASSIGNED => 1;
use constant STATUS_COMPLETE => 2;

#-------------------------------------------------------------------------------
# Commands
#-------------------------------------------------------------------------------
use constant CMD_ACK      => 0;  # Acknowledgement (respond OK)
use constant CMD_QUEUE    => 1;  # Queue a message
use constant CMD_COMPLETE => 2;  # Response - message is complete
use constant CMD_REJECTED => 3;  # Response - message was rejected
use constant CMD_ERROR    => 4;  # Response - error processing message or invalid message format
use constant CMD_ADD_NODE => 5;  # Add a node to a cluster
use constant CMD_DEL_NODE => 6;  # Remove a node from a cluster
use constant CMD_SHUTDOWN => 7;  # Shutdown a worker process

1;