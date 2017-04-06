package Argon::Queue;

use strict;
use warnings;
use Carp;

sub new {
  my ($class, $max) = @_;
  defined $max or croak 'expected parameter $max';
  return bless {
    max   => $max,
    count => 0,
    msgs  => [[], [], []],
  }, $class;
}

sub max {
  $_[0]->{max} = $_[1] if @_ == 2;
  $_[0]->{max};
}

sub count { $_[0]->{count} }

sub is_empty { $_[0]->count == 0 }

sub is_full { $_[0]->count >= $_[0]->max }

sub put {
  my ($self, $msg) = @_;

  croak 'usage: $queue->insert($msg)'
    unless defined $msg
        && (ref $msg || '') eq 'Argon::Message';

  croak 'queue full' if $self->is_full;

  $self->{msgs}[$msg->pri] ||= [];
  push @{$self->{msgs}[$msg->pri]}, $msg;

  ++$self->{count};
}

sub get {
  my $self = shift;
  return if $self->is_empty;

  --$self->{count};

  for (0 .. $#{$self->{msgs}}) {
    if (@{$self->{msgs}[$_]}) {
      return shift(@{$self->{msgs}[$_]});
    }
  }
}

1;
