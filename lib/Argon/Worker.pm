package Argon::Worker;
# ABSTRACT: Argon worker node providing capacity to an Argon::Manager

use strict;
use warnings;
use Carp;
use Class::Load qw(load_class);
use AnyEvent;
use AnyEvent::Util qw(fork_call);
use Argon::Client;
use Argon::Constants qw(:commands);
use Argon::Log;
use Argon::Message;
use Argon::Server;
use Argon::Util qw(:encoding K param);

use parent 'Argon::Server';

sub new {
  my ($class, %param) = @_;
  my $capacity = param 'capacity', %param;
  my $mgr_host = param 'mgr_host', %param;
  my $mgr_port = param 'mgr_port', %param;

  my $self = $class->SUPER::new(%param);

  $self->{capacity} = $AnyEvent::Util::MAX_FORKS = $capacity;
  $self->{mgr_host} = $mgr_host;
  $self->{mgr_port} = $mgr_port;
  $self->{timer}    = undef;
  $self->{tries}    = 0;

  $self->connect;

  $self->handles($QUEUE, K('_queue', $self));

  return $self;
}

sub connect {
  my $self = shift;
  ++$self->{tries};
  $self->{mgr} = Argon::Client->new(
    host   => $self->{mgr_host},
    port   => $self->{mgr_port},
    opened => K('_connected', $self),
    closed => K('_disconnected', $self),
  );
}

sub _connected {
  my $self = shift;
  $self->{tries} = 0;
  $self->register;
}

sub _disconnected {
  my $self = shift;
  $self->reconnect;
}

sub reconnect {
  my $self = shift;
  ++$self->{tries};
  my $intvl = 3 + log($self->{tries}) / log(10);
  log_debug 'Reconection attempt in %0.2fs', $intvl;
  $self->{timer} = AnyEvent->timer(after => $intvl, cb => K('connect', $self));
}

sub monitor {
  my $self = shift;
  my $ping = K('ping', $self->{mgr}, K('_check', $self));
  $self->{timer} = AnyEvent->timer(after => 5, cb => $ping);
}

sub _check {
  my ($self, $msg) = @_;

  if ($msg->cmd eq $ERROR) {
    $self->reconnect;
  } else {
    log_info '[%s] Pong!', $self->addr;
    $self->monitor;
  }
}

sub register {
  my $self = shift;
  $self->{conn}->recv;

  log_trace 'Registering with manager';

  my $msg = Argon::Message->new(
    cmd => $HIRE,
    info => {
      host => $self->{host},
      port => $self->{port},
      capacity => $self->{capacity},
    },
  );

  $self->{mgr}->send($msg, K('_mgr_registered', $self));
}

sub _mgr_registered {
  my ($self, $msg) = @_;
  if ($msg->cmd eq $ERROR) {
    log_error 'Failed to register with manager: %s', $msg->info;
  } else {
    log_info 'Accepting tasks';
  }
}

sub _queue {
  my ($self, $msg) = @_;
  my ($class, @args) = @{$msg->info};
  fork_call { _task($class, @args) } K('_result', $self, $msg);
}

sub _task {
  my ($class, @args) = @_;
  load_class $class;
  $class->new(@args)->run;
}

sub _result {
  my $self = shift;
  my $msg  = shift;

  my $reply = @_ == 0
    ? $msg->reply(cmd => $ERROR, info => $@ || "errno: $!")
    : $msg->reply(cmd => $DONE,  info => shift);

  $self->send($reply);
}

1;
