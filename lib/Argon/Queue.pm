package Argon::Queue;
# ABSTRACT: Bounded, prioritized queue class

use strict;
use warnings;
use Carp;
use Moose;
use Argon::Constants qw(:priorities);
use Argon::Tracker;
use Argon::Log;

has max => (
  is      => 'rw',
  isa     => 'Int',
  default => 0,
);

has tracker => (
  is      => 'ro',
  isa     => 'Argon::Tracker',
  lazy    => 1,
  builder => '_build_tracker',
  handles => {
  },
);

sub _build_tracker {
  my $self = shift;
  Argon::Tracker->new(
    capacity => $self->max,
    length   => $self->max * $self->max,
  );
}

has msgs => (
  is      => 'ro',
  isa     => 'ArrayRef[ArrayRef[Argon::Message]]',
  default => sub { [[], [], []] },
);

has count => (
  is      => 'rw',
  isa     => 'Int',
  default => 0,
  traits  => ['Counter'],
  handles => {
    inc_count => 'inc',
    dec_count => 'dec',
  }
);

has balanced => (
  is      => 'rw',
  isa     => 'Int',
  default => sub { time },
);

after max => sub {
  my $self = shift;
  if (@_) {
    $self->tracker->capacity($self->max);
    $self->tracker->length($self->max * $self->max);
  }
};

sub is_empty { $_[0]->count == 0 }
sub is_full  { $_[0]->count >= $_[0]->max }

sub put {
  my ($self, $msg) = @_;

  croak 'usage: $queue->put($msg)'
    unless defined $msg
        && (ref $msg || '') eq 'Argon::Message';

  $self->promote;

  croak 'queue full' if $self->is_full;

  push @{$self->msgs->[$msg->pri]}, $msg;

  $self->tracker->start($msg);
  $self->inc_count;
  $self->count;
}

sub get {
  my $self = shift;
  return if $self->is_empty;

  foreach my $pri ($HIGH, $NORMAL, $LOW) {
    my $queue = $self->msgs->[$pri];

    if (@$queue) {
      my $msg = shift @$queue;
      $self->tracker->finish($msg);
      $self->dec_count;

      return $msg;
    }
  }
}

sub promote {
  my $self = shift;
  my $avg  = $self->tracker->avg_time;
  my $max  = $avg * 1.5;
  return 0 unless time - $self->balanced >= $max;

  my $moved = 0;

  foreach my $pri ($LOW, $NORMAL) {
    while (my $msg = shift @{$self->msgs->[$pri]}) {
      if ($self->tracker->age($msg) > $max) {
        push @{$self->msgs->[$pri - 1]}, $msg;
        $self->tracker->touch($msg);
        ++$moved;
      } else {
        unshift @{$self->msgs->[$pri]}, $msg;
        last;
      }
    }
  }

  log_trace 'promoted %d msgs', $moved
    if $moved;

  return $moved;
}

__PACKAGE__->meta->make_immutable;

1;
