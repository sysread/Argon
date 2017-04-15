package Argon::Worker;
# ABSTRACT: Argon worker node providing capacity to an Argon::Manager

use strict;
use warnings;
use Carp;
use Moose;
use AnyEvent;
use AnyEvent::Util qw(fork_call);
use Argon;
use Argon::Constants qw(:commands);
use Argon::Log;
use Argon::Types;
use Argon::Util qw(K param interval);
require Argon::Client;
require Argon::Message;

with qw(Argon::Encryption);

has capacity => (
  is       => 'ro',
  isa      => 'Int',
  required => 1,
);

has mgr_host => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
);

has mgr_port => (
  is       => 'ro',
  isa      => 'Int',
  required => 1,
);

has timer => (
  is  => 'rw',
  isa => 'Any',
);

has tries => (
  is      => 'rw',
  isa     => 'Int',
  default => 0,
);

has intvl => (
  is       => 'ro',
  isa      => 'CodeRef',
  default  => sub { interval(1) },
  init_arg => undef,
);

has mgr => (
  is  => 'rw',
  isa => 'Argon::Client',
);

sub BUILD {
  my ($self, $args) = @_;
  $self->connect unless $self->mgr;
}

sub connect {
  my $self = shift;

  $self->tries($self->tries + 1);

  my $client = Argon::Client->new(
    key    => $self->key,
    token  => $self->token,
    host   => $self->mgr_host,
    port   => $self->mgr_port,
    ready  => K('_connected', $self),
    closed => K('_disconnected', $self),
    notify => K('_queue', $self),
  );

  $client->connect;

  $self->mgr($client);
}

sub _connected {
  my $self = shift;
  $self->timer(undef);
  $self->intvl->(1); # reset
  $self->register;
}

sub _disconnected {
  my $self = shift;
  log_note 'Manager disconnected' unless $self->timer;
  $self->reconnect;
}

sub reconnect {
  my $self = shift;
  my $intvl = $self->intvl->();
  $self->timer(AnyEvent->timer(after => $intvl, cb => K('connect', $self)));
  log_debug 'Reconection attempt in %0.4fs', $intvl;
}

sub register {
  my $self = shift;
  log_trace 'Registering with manager';

  my $msg = Argon::Message->new(
    cmd  => $HIRE,
    info => {capacity => $self->capacity},
  );

  $self->mgr->send($msg);
  $self->mgr->reply_cb($msg, K('_mgr_registered', $self));
}

sub _mgr_registered {
  my ($self, $msg) = @_;
  if ($msg->failed) {
    log_error 'Failed to register with manager: %s', $msg->info;
  }
  else {
    log_info 'Accepting tasks';
    log_note 'Direct code execution is permitted'
      if $Argon::ALLOW_EVAL;
  }
}

sub _queue {
  my ($self, $msg) = @_;
  my ($class, @args) = @{$msg->info};
  fork_call { _task($class, @args) } K('_result', $self, $msg);
}

sub _task {
  require Class::Load;
  my ($class, @args) = @_;
  Class::Load::load_class($class);
  $class->new(@args)->run;
}

sub _result {
  my $self = shift;
  my $msg  = shift;

  my $reply = @_ == 0
    ? $msg->reply(cmd => $ERROR, info => $@ || "errno: $!")
    : $msg->reply(cmd => $DONE,  info => shift);

  $self->mgr->send($reply);
}

__PACKAGE__->meta->make_immutable;

1;
