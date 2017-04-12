package Argon::Queue;
# ABSTRACT: Bounded, prioritized queue class

use strict;
use warnings;
use Carp;
use Data::Dumper;
use Argon::Constants qw(:priorities);
use Argon::Tracker;
use Argon::Log;
use Argon::Util qw(param);

sub new {
  my ($class, %param) = @_;
  my $max = param 'max',  %param, 0;

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

  croak 'usage: $queue->put($msg)'
    unless defined $msg
        && (ref $msg || '') eq 'Argon::Message';

  $self->promote;

  croak 'queue full' if $self->is_full;

  push @{$self->{msgs}[$msg->pri]}, $msg;

  $self->{tracker}->start($msg);

  ++$self->{count};

  log_trace 'put: %s', $msg->explain;

  $self->{count};
}

sub get {
  my $self = shift;
  return if $self->is_empty;

  --$self->{count};

  foreach my $pri ($HIGH, $NORMAL, $LOW) {
    my $queue = $self->{msgs}[$pri];

    if (@$queue) {
      my $msg = shift @$queue;
      $self->{tracker}->finish($msg);
      log_trace 'get: %s', $msg->explain;
      return $msg;
    }
  }
}

sub promote {
  my $self = shift;
  my $avg  = $self->{tracker}->avg_time;
  my $max  = $avg * 1.5;
  return 0 unless time - $self->{balanced} >= $max;

  my $moved = 0;

  foreach my $pri ($LOW, $NORMAL) {
    while (my $msg = shift @{$self->{msgs}[$pri]}) {
      if ($self->{tracker}->age($msg) > $max) {
        push @{$self->{msgs}[$pri - 1]}, $msg;
        $self->{tracker}->touch($msg);
        ++$moved;
      } else {
        unshift @{$self->{msgs}[$pri]}, $msg;
        last;
      }
    }
  }

  log_trace 'promoted %d msgs', $moved
    if $moved;

  return $moved;
}

1;
