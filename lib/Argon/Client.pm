package Argon::Client;

use strict;
use warnings;
use Carp;
use Storable 'nfreeze';
use AnyEvent;
use AnyEvent::Socket qw(tcp_connect);
use Argon;
use Argon::Constants qw(:commands :priorities);
use Argon::Channel;
use Argon::Log;
use Argon::Message;
use Argon::Util qw(K param);

sub new {
  my ($class, %param) = @_;
  my $host   = param 'host',   %param;
  my $port   = param 'port',   %param;
  my $opened = param 'opened', %param, undef;
  my $closed = param 'closed', %param, undef;
  my $notify = param 'notify', %param, undef;
  my $ping   = param 'ping',   %param, undef;

  my $self = bless {
    host    => $host,
    port    => $port,
    intvl   => $ping,
    opened  => $opened,
    closed  => $closed,
    notify  => $notify,
    channel => undef,
    timer   => undef,
    conn    => AnyEvent->condvar,
    done    => AnyEvent->condvar,
    cb      => {},
  }, $class;

  $self->connect;

  return $self;
}

sub addr { sprintf '%s:%d', $_[0]->{host}, $_[0]->{port} }

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
  $self->{conn}->recv;
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

  my $code = do {
    no warnings 'once';
    local $Storable::Deparse = 1;
    local $Storable::forgive_me = 1;
    nfreeze($code_ref);
  };

  $self->queue('Argon::Task', [$code, $args], $cb);
}

sub connect {
  my $self = shift;
  tcp_connect $self->{host}, $self->{port},
    K('_connected',  $self);
}

sub _connected {
  my ($self, $fh) = @_;
  if ($fh) {
    log_debug 'Connected to %s:%d', $self->{host}, $self->{port};

    $self->{channel} = Argon::Channel->new(
      fh       => $fh,
      on_msg   => K('_notify', $self),
      on_err   => K('_error', $self),
      on_close => K('_close', $self),
    );

    $self->{done} = AnyEvent->condvar;
    $self->{conn}->send;
    $self->{opened}->() if $self->{opened};
  }
  else {
    log_debug 'Connection attempt failed with: %s', $!;
    log_error 'Connection to manager failed';
  }

  if ($self->{intvl} && !$self->{timer}) {
    $self->{timer} = AnyEvent->timer(
      interval => $self->{intvl},
      after => $self->{intvl},
      cb => K('_monitor', $self),
    );
  }
}

sub _monitor {
  my $self = shift;
  if ($self->{channel}) {
    $self->ping(K('_check', $self));
  } else {
    log_info 'Reconnecting to manager';
    $self->connect;
  }
}

sub _check {
  my ($self, $msg) = @_;
  if ($msg->cmd eq $ERROR) {
    $self->cleanup;
    log_error 'Lost connection to manager';
  }
}

sub cleanup {
  my $self = shift;
  $self->{closed}->() if $self->{closed};
  undef $self->{channel};
  $self->{conn} = AnyEvent->condvar;

  $self->stop;

  my $msg = Argon::Message->new(
    cmd  => $ERROR,
    info => 'Remote host was disconnected before task completed',
  );

  foreach my $msg_id (keys %{$self->{cb}}) {
    $self->{cb}{$msg_id}->($msg->reply(id => $msg_id));
  }
}

sub _error {
  my ($self, $error) = @_;
  log_error $error;
  $self->cleanup;
}

sub _close {
  my $self = shift;
  log_debug 'Remote host disconnected';
  $self->cleanup;
}

sub _notify {
  my ($self, $msg) = @_;
  my $cb = delete $self->{cb}{$msg->id};
  if ($cb) {
    $cb->($msg);
  } elsif ($self->{notify}) {
    $self->{notify}->($msg);
  }
}

1;
