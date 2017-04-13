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
use Argon::Util qw(K param interval);

sub new {
  my ($class, %param) = @_;
  my $host    = param 'host',    %param;
  my $port    = param 'port',    %param;
  my $opened  = param 'opened',  %param, undef;
  my $failed  = param 'failed',  %param, undef;
  my $closed  = param 'closed',  %param, undef;
  my $notify  = param 'notify',  %param, undef;
  my $keyfile = param 'keyfile', %param, undef;
  my $retry   = param 'retry',   %param, undef;
  my $token   = param 'token',   %param, undef;
  my $remote  = param 'remote',  %param, undef;

  my $key = defined $keyfile
    ? path($keyfile)->slurp_raw
    : param 'key', %param;

  my $self = bless {
    token   => $token,
    remote  => $remote,
    key     => $key,
    host    => $host,
    port    => $port,
    opened  => $opened,
    failed  => $failed,
    closed  => $closed,
    notify  => $notify,
    retry   => $retry,
    channel => undef,
    msg     => {},
  }, $class;

  $self->connect;

  return $self;
}

sub addr   { sprintf '%s:%d', $_[0]->{host}, $_[0]->{port} }
sub cipher { Argon::Util::cipher($_[0]->{key}) }
sub token  { $_[0]->{token} || $_[0]->{channel}->token }

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
      token    => $self->{token},
      remote   => $self->{remote},
      on_msg   => K('_notify', $self),
      on_err   => K('_error', $self),
      on_close => K('_close', $self),
    );

    $self->{opened}->($self) if $self->{opened};
  }
  else {
    log_debug '[%s] Connection attempt failed: %s', $self->addr, $!;
    $self->cleanup;
    $self->{failed}->($!) if $self->{failed};
  }
}

sub send {
  my ($self, $msg, $cb) = @_;

  if (!$self->{channel}) {
    log_warn 'send: not connected';
    return;
  }

  $self->{channel}->send($msg);

  $self->{msg}{$msg->id} ||= {
    orig  => $msg,
    cb    => $cb,
    intvl => interval(1),
  };

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

  my $msg = Argon::Message->new(
    cmd  => $ERROR,
    info => 'Remote host was disconnected before task completed',
  );

  foreach my $msg_id (keys %{$self->{cb}}) {
    next unless $self->{cb}{$msg_id};
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
  my $info = delete $self->{msg}{$msg->id};

  if ($msg->denied && $self->{retry}) {
    my $copy  = $info->{orig}->copy;
    my $intvl = $info->{intvl}->();
    log_debug 'Retrying message in %0.2fs: %s', $intvl, $info->{orig}->explain;

    $self->{msg}{$copy->id} = {
      orig  => $copy,
      cb    => $info->{cb},
      intvl => $info->{intvl},
      timer => AnyEvent->timer(after => $intvl, cb => K('send', $self, $copy)),
    };

    return;
  }

  $info->{cb}
    ? $info->{cb}->($msg)
    : $self->{notify}->($msg);
}

1;
