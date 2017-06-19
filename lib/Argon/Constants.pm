package Argon::Constants;
# ABSTRACT: Constants used by Argon classes

=head1 DESCRIPTION

Constants used by Argon.

=cut

use strict;
use warnings;
use Const::Fast;
use parent 'Exporter';

=head1 EXPORT TAGS

=head2 :defaults

=head3 $EOL

End of line character (C<"\015\012">).

=cut

#-------------------------------------------------------------------------------
# Defaults
#-------------------------------------------------------------------------------
const our $EOL => "\015\012";

=head2 :priorities

Priority levels for L<Argon::Message>s.

=head3 $HIGH

=head3 $NORMAL

=head3 $LOW

=cut

#-------------------------------------------------------------------------------
# Priorities
#-------------------------------------------------------------------------------
const our $HIGH   => 0;
const our $NORMAL => 1;
const our $LOW    => 2;

=head2 :commands

Command verbs used in the Argon protocol.

=head3 $ID

Used by L<Argon::SecureChannel> to identify itself to the other side of the
line.

=head3 $PING

Used internally to identify when a worker or the manager becomes unavailable.

=head3 $ACK

Response when affirming a prior command. Used in response to C<$HIRE> and
C<$PING>.

=head3 $ERROR

Response when the prior command failed due to an error. Generally used only
with C<$QUEUE>.

=head3 $QUEUE

Queues a message with the manager. If the service is at capacity, elicits a
response of C<$DENY>.

=head3 $DENY

Response sent after an attempt to C<$QUEUE> when the system is at max capacity.

=head3 $DONE

Response sent after C<$QUEUE> when the task has been completed without error.

=head3 $HIRE

Used internally by the L<Argon::Worker> to announce its capacity when
registering with the L<Argon::Manager>.

=cut

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
