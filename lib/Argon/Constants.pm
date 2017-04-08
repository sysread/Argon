package Argon::Constants;
# ABSTRACT: Constants used by Argon classes

use strict;
use warnings;
use Const::Fast;
use parent 'Exporter';

#-------------------------------------------------------------------------------
# Defaults
#-------------------------------------------------------------------------------
const our $EOL => "\015\012";

#-------------------------------------------------------------------------------
# Priorities
#-------------------------------------------------------------------------------
const our $PRI_HI => '1';
const our $PRI_NO => '2';
const our $PRI_LO => '3';

#-------------------------------------------------------------------------------
# Commands
#-------------------------------------------------------------------------------
const our $PING  => 'PING';
const our $ACK   => 'ACK';
const our $ERROR => 'ERROR';
const our $QUEUE => 'QUEUE';
const our $DENY  => 'DENY';
const our $DONE  => 'DONE';
const our $HIRE  => 'HIRE';

#-------------------------------------------------------------------------------
# Exports
#-------------------------------------------------------------------------------
our %EXPORT_TAGS = (
  defaults   => [qw($EOL)],
  priorities => [qw($PRI_HI $PRI_NO $PRI_LO)],
  commands   => [qw($PING $ACK $ERROR $QUEUE $DENY $DONE $HIRE)],
);

our @EXPORT_OK = map { @$_ } values %EXPORT_TAGS;


1;
