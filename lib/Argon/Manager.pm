package Argon::Manager;
# ABSTRACT: Entry-point Argon service providing intelligent task routing

use strict;
use warnings;
use Carp;
use AnyEvent;
use Argon::Client;
use Argon::Constants qw(:commands);
use Argon::Log;
use Argon::Queue;
use Argon::Server;
use Argon::Tracker;
use Argon::Util qw(K param);

use parent 'Argon::Server';

sub new {
  my ($class, %param) = @_;
  my $self = $class->SUPER::new(%param);

  $self->{assigned} = {};
  $self->{worker}   = {};
  $self->{tracker}  = {self => Argon::Tracker->new(capacity => 0)};
  $self->{queue}    = Argon::Queue->new(0);

  $self->handles($HIRE,  K('_hire',  $self));
  $self->handles($QUEUE, K('_queue', $self));

  return $self;
}

sub capacity { $_[0]->{tracker}{self}->capacity }
sub has_capacity { $_[0]->{tracker}{self}->has_capacity }

sub next_worker {
  my $self = shift;

  my @workers =
    sort { $self->{tracker}{$a}->load <=> $self->{tracker}{$b}->load }
    grep { $self->{tracker}{$_}->has_capacity }
    keys %{$self->{worker}};

  shift @workers;
}

sub process_queue {
  my $self = shift;
  while ($self->has_capacity && !$self->{queue}->is_empty) {
    my $token = $self->next_worker;
    my $msg = $self->{queue}->get->reply(token => $token);
    $self->{worker}{$token}->send($msg);
    $self->{tracker}{$token}->start($msg);
    $self->{tracker}{self}->start($msg);
    $self->{assigned}{$msg->id} = $token;
    log_debug 'worker %s assigned %s', $token, $msg->explain;
  }
}

sub _queue {
  my ($self, $msg) = @_;
  if ($self->{queue}->is_full) {
    $self->send($msg->reply(cmd => $DENY, info => "No available capacity. Please try again later."));
  }
  else {
    $self->{queue}->put($msg);
    $self->process_queue;
  }
}

sub _collect {
  my ($self, $msg) = @_;
  my $token = delete $self->{assigned}{$msg->id};
  $self->{tracker}{$token}->finish($msg);
  $self->{tracker}{self}->finish($msg);
  $self->send($msg);
  $self->process_queue;
}

sub _hire {
  my ($self, $msg) = @_;
  $self->send($msg->reply(cmd => $ACK));

  my $token = $msg->token || croak 'Missing token: ' . $msg->explain;
  my $cap   = $msg->info->{capacity};
  my $host  = $msg->info->{host};
  my $port  = $msg->info->{port};

  my $worker = Argon::Client->new(
    key    => $self->{key},
    host   => $host,
    port   => $port,
    notify => K('_collect', $self),
    closed => K('_fire', $self, $token, $cap),
  );

  $self->{worker}{$token} = $worker;
  $self->{tracker}{$token} = Argon::Tracker->new(capacity => $cap);
  $self->{tracker}{self}->add_capacity($cap);
  $self->{queue}->max($self->capacity * 2);

  log_info 'New worker with identity %s (%s:%d) added %d capacity (%d total)',
    $token, $host, $port, $cap, $self->capacity;
}

sub _fire {
  my ($self, $worker, $capacity) = @_;
  $self->{tracker}{self}->remove_capacity($capacity);
  delete $self->{worker}{$worker};
  delete $self->{tracker}{$worker};

  my @msgids = grep { $self->{assigned}{$_} eq $worker }
    keys %{$self->{assigned}};

  if (@msgids) {
    my $msg = 'The worker assigned to this task disconnected before completion.';
    $self->send(Argon::Message->error($msg, id => $_))
      foreach @msgids;
  }

  log_info 'Worker %s disconnected; max capacity is down to %d',
    $worker,
    $self->capacity;
}

1;
