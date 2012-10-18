package Argon;

our $VERSION = '0.001';

use strict;
use warnings;
use Carp;
use namespace::autoclean;

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
    /],

    # Priorities
    'priorities' => [qw/PRI_REAL PRI_HIGH PRI_NORMAL PRI_LOW PRI_IGNORE/],

    # Command verbs and responses
    'commands'   => [qw/
        CMD_ACK
        CMD_ID
        CMD_QUEUE
        CMD_STATUS
        CMD_REJECTED
        CMD_PENDING
        CMD_COMPLETE
        CMD_ERROR
    /],
);

our @EXPORT_OK = map { @$_ } values %EXPORT_TAGS;

#-------------------------------------------------------------------------------
# Defaults
#-------------------------------------------------------------------------------
use constant LISTEN_QUEUE_SIZE  => 128;
use constant SOCKET_TIMEOUT     => 30;
use constant CHUNK_SIZE         => 1024 * 4;
use constant EOL                => "\015\012";
use constant MESSAGE_SEPARATOR  => ' ';

#-------------------------------------------------------------------------------
# Priorities
#-------------------------------------------------------------------------------
use constant PRI_REAL    => 0;
use constant PRI_HIGH    => 1;
use constant PRI_NORMAL  => 2;
use constant PRI_LOW     => 3;
use constant PRI_IGNORE  => 4;

#-------------------------------------------------------------------------------
# Commands
#-------------------------------------------------------------------------------
use constant CMD_ACK      => 0;  # Acknowledgement (respond OK)
use constant CMD_ID       => 1;  # Get a unique ID for a message
use constant CMD_QUEUE    => 2;  # Queue a message
use constant CMD_STATUS   => 3;  # Poll a message status
use constant CMD_PENDING  => 4;  # Response - message is in-progress
use constant CMD_COMPLETE => 5;  # Response - message is complete
use constant CMD_REJECTED => 6;  # Response - message was rejected
use constant CMD_ERROR    => 7;  # Response - error processing message or invalid message format

1;
