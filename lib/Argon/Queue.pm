package Argon::Queue;
# ABSTRACT: Bounded, prioritized queue class

use strict;
use warnings;
use Carp;
use Argon::Constants ':priorities';
use Argon::Tracker;
use Argon::Log;

sub new {
  my ($class, $max) = @_;
  defined $max or croak 'expected parameter $max';

  my $tracker = Argon::Tracker->new(
    capacity => $max,
    history  => $max * $max,
  );

  my $queue = [];
  $queue->[$HIGH]   = [];
  $queue->[$NORMAL] = [];
  $queue->[$LOW]    = [];

  return bless {
    max      => $max,
    tracker  => $tracker,
    msgs     => $queue,
    count    => 0,
    balanced => time,
  }, $class;
}

sub max {
  if (@_ == 2) {
    $_[0]->{max} = $_[1];
    $_[0]->{tracker}{capacity} = $_[1];
  }

  $_[0]->{max};
}

sub count    { $_[0]->{count} }
sub is_empty { $_[0]->count == 0 }
sub is_full  { $_[0]->count >= $_[0]->max }

sub put {
  my ($self, $msg) = @_;

  croak 'usage: $queue->insert($msg)'
    unless defined $msg
        && (ref $msg || '') eq 'Argon::Message';

  $self->promote;

  croak 'queue full' if $self->is_full;

  $self->{msgs}[$msg->pri] ||= [];
  push @{$self->{msgs}[$msg->pri]}, $msg;

  $self->{tracker}->start($msg);

  ++$self->{count};

  $self->{count};
}

sub get {
  my $self = shift;
  return if $self->is_empty;

  --$self->{count};

  for (0 .. $#{$self->{msgs}}) {
    if (@{$self->{msgs}[$_]}) {
      my $msg = shift @{$self->{msgs}[$_]};
      $self->{tracker}->finish($msg);
      return $msg;
    }
  }
}

sub promote {
  my $self = shift;
  my $avg  = $self->{tracker}->avg_time;
  my $max  = $avg * 1.5;
  return 0 unless time - $self->{balanced} >= $max;

  my @queue = ([], [], []);
  my $moved = 0;

  foreach my $pri ($LOW, $NORMAL) {
    my @stay;
    my @move;

    foreach (@{$self->{msgs}[$pri]}) {
      if ($self->{tracker}->age($_) > $max) {
        push @move, $_;
        ++$moved;
      } else {
        push @stay, $_;
      }
    }

    push @{$queue[$pri]}, @stay;
    push @{$queue[$pri - 1]}, @move;
  }

  $self->{msgs} = [@queue];
  $self->{balanced} = time;
  return $moved;
}

1;
