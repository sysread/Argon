package Argon;

our $VERSION = '0.001';

use strict;
use warnings;
use Carp;

require Exporter;
use base qw/Exporter/;

our %EXPORT_TAGS = (
    # Defaults and parameters
    'defaults' => [qw/
        LISTEN_QUEUE_SIZE
        SOCKET_TIMEOUT
        CHUNK_SIZE
        EOL
        NO_ID
        MESSAGE_SEPARATOR
    /],

    # Priorities
    'priorities' => [qw/PRI_REAL PRI_HIGH PRI_NORMAL PRI_LOW PRI_IGNORE/],

    # Command verbs
    'commands'   => [qw/CMD_ACK/],
);

our @EXPORT_OK = map { @$_ } values %EXPORT_TAGS;

#-------------------------------------------------------------------------------
# Defaults
#-------------------------------------------------------------------------------
use constant LISTEN_QUEUE_SIZE  => 128;
use constant SOCKET_TIMEOUT     => 30;
use constant CHUNK_SIZE         => 1024 * 4;
use constant EOL                => "\015\012";
use constant NO_ID              => 0;
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
use constant CMD_ACK => 0;

1;
