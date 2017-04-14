package Argon::Tracker;
# ABSTRACT: Internal class used to track node capacity

use strict;
use warnings;
use Carp;
use Moose;
use List::Util  qw(sum0);
use Time::HiRes qw(time);
use Argon::Util qw(param);

has capacity => (
  is      => 'rw',
  isa     => 'Int',
  default => 0,
  traits  => ['Counter'],
  handles => {
    add_capacity    => 'inc',
    remove_capacity => 'dec',
  },
);

has length => (
  is      => 'rw',
  isa     => 'Int',
  default => 20,
);

has started => (
  is      => 'rw',
  isa     => 'HashRef[Num]',
  default => sub {{}},
  traits  => ['Hash'],
  handles => {
    track      => 'set',
    untrack    => 'delete',
    start_time => 'get',
    is_tracked => 'exists',
    assigned   => 'count',
  },
);

has history => (
  is      => 'rw',
  isa     => 'ArrayRef[Num]',
  default => sub {[]},
  traits  => ['Array'],
  handles => {
    record        => 'push',
    record_count  => 'count',
    prune_records => 'shift',
  },
);

has avg_time => (
  is      => 'rw',
  isa     => 'Num',
  default => 0,
);

sub available_capacity { $_[0]->capacity - $_[0]->assigned }
sub has_capacity { $_[0]->available_capacity > 0 }
sub load { ($_[0]->assigned + 1) * $_[0]->avg_time }

sub age {
  my ($self, $msg) = @_;
  return unless $self->is_tracked($msg->id);
  time - $self->start_time($msg->id);
}

sub start {
  my ($self, $msg) = @_;
  croak 'no capacity' unless $self->has_capacity;
  croak "msg id $msg->id is already tracked" if $self->is_tracked($msg->id);
  $self->track($msg->id, time);
}

sub finish {
  my ($self, $msg) = @_;
  croak "msg id $msg->id is not tracked" unless $self->is_tracked($msg->id);
  --$self->{assigned};
  $self->_add_to_history(time - $self->untrack($msg->id));
  $self->_update_avg_time;
}

sub touch {
  my ($self, $msg) = @_;
  croak "msg id $msg->id is not tracked" unless $self->is_tracked($msg->id);
  $self->track($msg->id, time);
}

sub _add_to_history {
  my ($self, $taken) = @_;
  $self->record($taken);
  while ($self->record_count > $self->length) {
    $self->prune_records;
  }
}

sub _update_avg_time {
  my $self = shift;
  my $total = sum0 @{$self->{history}};
  $self->{avg_time} = $total == 0 ? 0 : $total / @{$self->{history}};
}

__PACKAGE__->meta->make_immutable;

1;
