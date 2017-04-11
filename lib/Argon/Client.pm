package Argon::Client;
# ABSTRACT: Client-side connection class for Argon systems

use strict;
use warnings;
use Carp;
use Storable 'nfreeze';
use AnyEvent;
use AnyEvent::Socket qw(tcp_connect);
use Data::Dump::Streamer;
use Path::Tiny 'path';
use Try::Tiny;
use Argon;
use Argon::Constants qw(:commands :priorities);
use Argon::Channel;
use Argon::Log;
use Argon::Message;
use Argon::Util qw(K param);

sub new {
  my ($class, %param) = @_;
  my $host    = param 'host',    %param;
  my $port    = param 'port',    %param;
  my $opened  = param 'opened',  %param, undef;
  my $failed  = param 'failed',  %param, undef;
  my $closed  = param 'closed',  %param, undef;
  my $notify  = param 'notify',  %param, undef;
  my $keyfile = param 'keyfile', %param, undef;

  my $key = defined $keyfile
    ? path($keyfile)->slurp_raw
    : param 'key', %param;

  my $self = bless {
    key     => $key,
    host    => $host,
    port    => $port,
    opened  => $opened,
    failed  => $failed,
    closed  => $closed,
    notify  => $notify,
    channel => undef,
    conn    => AnyEvent->condvar,
    done    => AnyEvent->condvar,
    cb      => {},
  }, $class;

  $self->connect;

  return $self;
}

sub addr { sprintf '%s:%d', $_[0]->{host}, $_[0]->{port} }

sub connect {
  my $self = shift;
  tcp_connect $self->{host}, $self->{port}, K('_connected',  $self);
}

sub _connected {
  my ($self, $fh) = @_;

  if ($fh) {
    log_debug '[%s] Connection established', $self->addr;

    $self->{channel} = Argon::Channel->new(
      fh       => $fh,
      key      => $self->{key},
      on_msg   => K('_notify', $self),
      on_err   => K('_error', $self),
      on_close => K('_close', $self),
    );

    $self->{done} = AnyEvent->condvar;
    $self->{conn}->send;
    $self->{opened}->() if $self->{opened};
  }
  else {
    log_error '[%s] Connection attempt failed', $self->addr;
    $self->cleanup;
    $self->{failed}->($!) if $self->{failed};
  }
}

sub run {
  my $self = shift;
  $self->{done}->recv;
}

sub stop {
  my $self = shift;
  $self->{done}->send;
}

sub send {
  my ($self, $msg, $cb) = @_;

  try {
    $self->{conn}->recv;
  } catch {
    Carp::confess($_);
  };

  $self->{cb}{$msg->id} = $cb;
  $self->{channel}->send($msg);
  return $msg->id;
}

sub ping {
  my ($self, $cb) = @_;
  $self->send(Argon::Message->new(cmd => $PING), $cb)
}

sub queue {
  my ($self, $class, $args, $cb) = @_;
  $self->send(Argon::Message->new(cmd => $QUEUE, info => [$class, @$args]), $cb);
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
  $self->{closed}->() if $self->{closed};
  undef $self->{channel};

  $self->stop;
  $self->{conn} = AnyEvent->condvar;

  my $msg = Argon::Message->new(
    cmd  => $ERROR,
    info => 'Remote host was disconnected before task completed',
  );

  foreach my $msg_id (keys %{$self->{cb}}) {
    $self->{cb}{$msg_id}->($msg->reply(id => $msg_id));
  }
}

sub _error {
  my ($self, $channel, $error) = @_;
  log_error '[%s] %s', $self->addr, $error;
  $self->cleanup;
}

sub _close {
  my ($self, $channel) = @_;
  log_debug '[%s] Remote host disconnected', $self->addr;
  $self->cleanup;
}

sub _notify {
  my ($self, $channel, $msg) = @_;
  my $cb = delete $self->{cb}{$msg->id};
  if ($cb) {
    $cb->($msg);
  } elsif ($self->{notify}) {
    $self->{notify}->($msg);
  }
}

1;
