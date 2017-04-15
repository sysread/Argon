package Argon::Client;
# ABSTRACT: Client-side connection class for Argon systems

use strict;
use warnings;
use Carp;
use Moose;
use AnyEvent;
use AnyEvent::Socket qw(tcp_connect);
use Data::Dump::Streamer;
use Try::Tiny;
use Argon;
use Argon::Constants qw(:commands :priorities);
use Argon::Channel;
use Argon::Log;
use Argon::Message;
use Argon::Types;
use Argon::Util qw(K param interval);

with qw(Argon::Encryption);

has host => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
);

has port => (
  is       => 'ro',
  isa      => 'Int',
  required => 1,
);

has retry => (
  is      => 'ro',
  isa     => 'Bool',
  default => 0,
);

has opened => (
  is      => 'ro',
  isa     => 'Ar::Callback',
  default => sub { sub {} },
);

has ready => (
  is      => 'ro',
  isa     => 'Ar::Callback',
  default => sub { sub {} },
);

has failed => (
  is      => 'ro',
  isa     => 'Ar::Callback',
  default => sub { sub {} },
);

has closed => (
  is      => 'ro',
  isa     => 'Ar::Callback',
  default => sub { sub {} },
);

has notify => (
  is      => 'ro',
  isa     => 'Ar::Callback',
  default => sub { sub {} },
);

has remote => (
  is  => 'rw',
  isa => 'Maybe[Str]',
);

has msg => (
  is      => 'rw',
  isa     => 'HashRef',
  default => sub {{}},
  traits  => ['Hash'],
  handles => {
    has_msg => 'exists',
    get_msg => 'get',
    add_msg => 'set',
    del_msg => 'delete',
    msg_ids => 'keys',
    msgs    => 'values',
  },
);

has channel => (
  is      => 'rw',
  isa     => 'Maybe[Argon::Channel]',
  handles => [qw(send)],
);

has addr => (
  is      => 'ro',
  isa     => 'Str',
  lazy    => 1,
  builder => '_build_addr',
);

sub _build_addr {
  my $self = shift;
  join ':', $self->host, $self->port;
}

sub BUILD {
  my ($self, $args) = @_;
  $self->connect unless $self->channel;
}

sub connect {
  my $self = shift;
  log_debug 'Connecting to %s', $self->addr;
  tcp_connect $self->host, $self->port, K('_connected', $self);
}

sub _connected {
  my ($self, $fh) = @_;

  if ($fh) {
    log_debug '[%s] Connection established', $self->addr;

    my $channel = Argon::Channel->new(
      fh       => $fh,
      key      => $self->key,
      token    => $self->token,
      remote   => $self->remote,
      on_msg   => K('_notify', $self),
      on_ready => K('_ready', $self),
      on_err   => K('_error', $self),
      on_close => K('_close', $self),
    );

    $self->channel($channel);
    $self->opened->();
  }
  else {
    log_debug '[%s] Connection attempt failed: %s', $self->addr, $!;
    $self->cleanup;
    $self->failed->($!);
  }
}

sub reply_cb {
  my ($self, $msg, $cb, $retry) = @_;
  $self->add_msg($msg->id, {
    orig  => $msg,
    cb    => $cb,
    intvl => interval(1),
    retry => $retry,
  });
}

sub ping {
  my ($self, $cb) = @_;
  my $msg = Argon::Message->new(cmd => $PING);
  $self->send($msg);
  $self->reply_cb($msg, $cb);
}

sub queue {
  my ($self, $class, $args, $cb) = @_;
  my $msg = Argon::Message->new(cmd => $QUEUE, info => [$class, @$args]);
  $self->send($msg);
  $self->reply_cb($msg, $cb, $self->retry);
}

sub process {
  Argon::ASSERT_EVAL_ALLOWED;
  my ($self, $code_ref, $args, $cb) = @_;
  $args ||= [];

  my $code = Dump($code_ref)
    ->Purity(1)
    ->Declare(1)
    ->Out;

  $self->queue('Argon::Task', [$code, $args], $cb);
}

sub cleanup {
  my $self = shift;
  $self->closed->();
  $self->channel(undef);

  my $error = 'Remote host was disconnected before task completed';

  foreach my $id ($self->msg_ids) {
    my $info = $self->get_msg($id);
    my $cb   = $info->{cb} or next;
    my $msg  = $info->{orig};
    $cb->($msg->error($error));
  }
}

sub _ready { shift->ready->() }

sub _error {
  my ($self, $error) = @_;
  log_error '[%s] %s', $self->addr, $error;
  $self->cleanup;
}

sub _close {
  my ($self) = @_;
  log_debug '[%s] Remote host disconnected', $self->addr;
  $self->cleanup;
}

sub _notify {
  my ($self, $msg) = @_;

  if ($self->has_msg($msg->id)) {
    my $info = $self->del_msg($msg->id);

    if ($msg->denied && $info->{retry}) {
      my $copy  = $info->{orig}->copy;
      my $intvl = $info->{intvl}->();
      log_debug 'Retrying message in %0.2fs: %s', $intvl, $info->{orig}->explain;

      $self->add_msg($copy->id, {
        orig  => $copy,
        cb    => $info->{cb},
        intvl => $info->{intvl},
        retry => 1,
        timer => AnyEvent->timer(after => $intvl, cb => K('send', $self, $copy)),
      });

      return;
    }

    if ($info->{cb}) {
      $info->{cb}->($msg);
    }
    else {
      $self->notify->($msg);
    }
  }
  else {
    $self->notify->($msg);
  }
}

__PACKAGE__->meta->make_immutable;

1;
