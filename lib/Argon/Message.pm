package Argon::Message;
# ABSTRACT: Encodable message structure used for cross-system coordination

=head1 DESCRIPTION

Argon protocol messages.

=head1 SYNOPSIS

  use Argon::Message;
  use Argon ':commands', ':priorities';

  my $msg = Argon::Message->new(
    cmd  => $PING,
    pri  => $NORMAL,
    info => {thing => ['with', 'data', 'in', 'it']},
  );

  my $reply = $msg->reply(info => '...');
  my $error = $msg->error("some error message");

=cut

use strict;
use warnings;
use Carp;
use Moose;
use Data::UUID;
use Argon::Constants qw(:priorities :commands);
use Argon::Types;
use Argon::Util qw(param);

=head1 ATTRIBUTES

=head2 id

Unique identifier for the conversation. Used to track the course of a task from
the client to the manager to the worker and back.

=cut

has id => (
  is  => 'ro',
  isa => 'Str',
  default => sub { Data::UUID->new->create_str },
);

=head2 cmd

The command verb. See L<Argon::Constants/:commands>.

=cut

has cmd => (
  is  => 'ro',
  isa => 'Ar::Command',
  required => 1,
);

=head2 pri

The message priority. See L<Argon::Constants/:priorities>.

=cut

has pri => (
  is  => 'ro',
  isa => 'Ar::Priority',
  default => $NORMAL,
);

=head2 info

The data payload of the message. May be a string, reference, et al.

=cut

has info => (
  is  => 'ro',
  isa => 'Any',
);

=head2 token

Used internally by L<Argon::SecureChannel> to identify message senders.

=cut

has token => (
  is  => 'rw',
  isa => 'Maybe[Str]',
);

=head1 METHODS

=head2 failed

Returns true if the C<cmd> is C<$ERROR>.

=head2 denied

Returns true if the C<cmd> is C<$DENY>.

=head2 copy

Returns a shallow copy of the message with a new id and token.

=cut

sub failed { $_[0]->cmd eq $ERROR }
sub denied { $_[0]->cmd eq $DENY }
sub copy   { $_[0]->reply(id => Data::UUID->new->create_str) }

=head2 reply

Returns a copy of the message. Any additional parameters passed are passed
transparently to C<new>.

=cut

sub reply {
  my ($self, %param) = @_;
  Argon::Message->new(
    %$self,         # copy $self
    token => undef, # remove token (unless in %param)
    %param,         # add caller's parameters
  );
}

=head2 error

Returns a new message with the same id, C<cmd> set to C<$ERROR>, and C<info>
set to the supplied error message.

=cut

sub error {
  my ($self, $error, %param) = @_;
  $self->reply(%param, cmd => $ERROR, info => $error);
}

=head2 result

Returns the decoded data playload. If the message is an C<$ERROR> or C<$DENY>,
croaks with C<info> as the error message. If the message is an C<$ACK>, returns
true.

=cut

sub result {
  my $self = shift;
  return $self->failed ? croak($self->info)
       : $self->denied ? croak($self->info)
       : $self->cmd eq $ACK ? 1
       : $self->info;
}

=head2 explain

Returns a formatted string describing the message. Useful for debugging and
logging.

=cut

sub explain {
  my $self = shift;
  sprintf '[P%d %5s %s %s]', $self->pri, $self->cmd, $self->token || '-', $self->id;
}

__PACKAGE__->meta->make_immutable;

1;
