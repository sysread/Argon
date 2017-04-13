package Argon::Manager;
# ABSTRACT: Entry-point Argon service providing intelligent task routing

use strict;
use warnings;
use Carp;
use Path::Tiny qw(path);
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
  my $persist = param 'persist', %param, undef;
  my $self = $class->SUPER::new(%param);

  $self->{assigned} = {};
  $self->{worker}   = {};
  $self->{tracker}  = {self => Argon::Tracker->new(capacity => 0)};
  $self->{queue}    = Argon::Queue->new();
  $self->{persist}  = $persist ? path($persist) : undef;

  $self->handles($HIRE,  K('_hire',  $self));
  $self->handles($QUEUE, K('_queue', $self));

  $self->load_file;

  return $self;
}

sub save_file {
  my $self = shift;
  return unless $self->{persist};
  log_trace 'Saving copy of message queue';

  my $saved = {
    queue   => $self->{queue},
    tracker => $self->{tracker},
  };

  my $data = Argon::Util::encode($self->cipher, $saved);
  $self->{persist}->spew_raw($data);
}

sub load_file {
  my $self = shift;
  return unless $self->{persist};
  return unless $self->{persist}->exists;
  log_trace 'Loading message queue from saved copy';

  my $data  = $self->{persist}->slurp_raw;
  my $saved = Argon::Util::decode($self->cipher, $data);

  $self->{tracker} = $saved->{tracker};
  $self->{queue} = $saved->{queue};
  $self->{queue}->max($self->capacity);
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
    my $id  = $self->next_worker;
    my $msg = $self->{queue}->get;
    $self->{worker}{$id}->send($msg);
    $self->{tracker}{$id}->start($msg);
    $self->{tracker}{self}->start($msg);
    $self->{assigned}{$msg->id} = $id;
    log_debug 'worker %s assigned %s', $id, $msg->explain;
  }

  $self->save_file;
}

sub _queue {
  my ($self, $addr, $msg) = @_;
  if ($self->{queue}->is_full) {
    $self->send($msg->reply(cmd => $DENY, info => "No available capacity. Please try again later."));
  }
  else {
    $self->{queue}->put($msg);
    $self->process_queue;
  }
}

sub _collect {
  my ($self, $channel, $msg) = @_;
  my $id = delete $self->{assigned}{$msg->id};
  $self->{tracker}{$id}->finish($msg);
  $self->{tracker}{self}->finish($msg);
  $self->send($msg);
  $self->process_queue;
}

sub _hire {
  my ($self, $addr, $msg) = @_;
  $self->send($msg->reply(cmd => $ACK));

  my $id  = $msg->token || croak 'Missing token: ' . $msg->explain;
  my $cap = $msg->info->{capacity};

  my $worker = $self->client($addr);
  $worker->{on_msg}   = K('_collect', $self);
  $worker->{on_close} = K('_fire', $self, $id, $cap);

  $self->{worker}{$id} = $worker;
  $self->{tracker}{$id} = Argon::Tracker->new(capacity => $cap);
  $self->{tracker}{self}->add_capacity($cap);
  $self->{queue}->max($self->capacity * 2);

  log_info 'New worker with identity %s added %d capacity (%d total)',
    $id, $cap, $self->capacity;
}

sub _fire {
  my ($self, $worker, $capacity) = @_;
  $self->{tracker}{self}->remove_capacity($capacity);
  delete $self->{worker}{$worker};
  delete $self->{tracker}{$worker};

  $self->{queue}->max($self->capacity * 2);

  my @msgids = grep { $self->{assigned}{$_} eq $worker }
    keys %{$self->{assigned}};

  if (@msgids) {
    my $msg = 'The worker assigned to this task disconnected before completion.';
    $self->send(Argon::Message->error($msg, id => $_))
      foreach @msgids;
  }

  log_info 'Worker %s disconnected; capacity is down to %d',
    $worker,
    $self->capacity;
}

1;
