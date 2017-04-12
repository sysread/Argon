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
const our $HIGH   => 0;
const our $NORMAL => 1;
const our $LOW    => 2;

#-------------------------------------------------------------------------------
# Commands
#-------------------------------------------------------------------------------
const our $ID    => 'ID';
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
  priorities => [qw($HIGH $NORMAL $LOW)],
  commands   => [qw($ID $PING $ACK $ERROR $QUEUE $DENY $DONE $HIRE)],
);

our @EXPORT_OK = map { @$_ } values %EXPORT_TAGS;


1;
