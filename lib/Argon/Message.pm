package Argon::Message;
# ABSTRACT: Encodable message structure used for cross-system coordination

use strict;
use warnings;
use Carp;
use Moose;
use Data::UUID;
use Argon::Constants qw(:priorities :commands);
use Argon::Types;
use Argon::Util qw(param);

has id => (
  is  => 'ro',
  isa => 'Str',
  default => sub { Data::UUID->new->create_str },
);

has cmd => (
  is  => 'ro',
  isa => 'Ar::Command',
  required => 1,
);

has pri => (
  is  => 'ro',
  isa => 'Ar::Priority',
  default => $NORMAL,
);

has info => (
  is  => 'ro',
  isa => 'Any',
);

has token => (
  is  => 'rw',
  isa => 'Maybe[Str]',
);

sub failed { $_[0]->cmd eq $ERROR }
sub denied { $_[0]->cmd eq $DENY }
sub copy   { $_[0]->reply(id => Data::UUID->new->create_str) }

sub reply {
  my ($self, %param) = @_;
  Argon::Message->new(
    %$self,         # copy $self
    token => undef, # remove token (unless in %param)
    %param,         # add caller's parameters
  );
}

sub error {
  my ($self, $error, %param) = @_;
  $self->reply(%param, cmd => $ERROR, info => $error);
}

sub result {
  my $self = shift;
  return $self->failed ? croak($self->info)
       : $self->denied ? croak($self->info)
       : $self->cmd eq $ACK ? 1
       : $self->info;
}

sub explain {
  my $self = shift;
  sprintf '[P%d %5s %s %s]', $self->pri, $self->cmd, $self->token || '-', $self->id;
}

__PACKAGE__->meta->make_immutable;

1;
