package Argon::Tracker;

use strict;
use warnings;
use Carp;
use List::Util  qw(sum0);
use Time::HiRes qw(time);
use Argon::Util qw(param);

sub new {
  my ($class, %param) = @_;
  my $capacity = param 'capacity', %param;
  my $history  = param 'history',  %param, 20;

  return bless {
    capacity => $capacity,
    length   => $history,
    assigned => 0,
    started  => {},
    history  => [],
    avg_time => 0,
  }, $class;
}

sub assigned { $_[0]->{assigned} }
sub avg_time { $_[0]->{avg_time} }
sub capacity { $_[0]->{capacity} }
sub available_capacity  { $_[0]->capacity - $_[0]->assigned }
sub has_capacity { $_[0]->available_capacity > 0 }
sub add_capacity { $_[0]->{capacity} += $_[1] }
sub remove_capacity { $_[0]->{capacity} -= $_[1] }
sub load { ($_[0]->assigned + 1) * $_[0]->avg_time }

sub is_tracked { exists $_[0]->{started}{$_[1]->{id}} }

sub start {
  my ($self, $msg) = @_;
  croak 'no capacity' unless $self->has_capacity;
  croak "msg id $msg->{id} is already tracked" if $self->is_tracked($msg);
  $self->{started}{$msg->id} = time;
  ++$self->{assigned};
}

sub finish {
  my ($self, $msg) = @_;
  croak "msg id $msg->{id} is not tracked" unless $self->is_tracked($msg);
  --$self->{assigned};
  $self->_add_to_history(time - delete $self->{started}{$msg->id});
  $self->_update_avg_time;
}

sub _add_to_history {
  my ($self, $taken) = @_;
  push @{$self->{history}}, $taken;
  while (@{$self->{history}} > $self->{length}) {
    shift @{$self->{history}};
  }
}

sub _update_avg_time {
  my $self = shift;
  my $total = sum0 @{$self->{history}};
  $self->{avg_time} = $total == 0 ? 0 : $total / @{$self->{history}};
}

1;
