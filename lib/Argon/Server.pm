package Argon::Server;
# ABSTRACT: Base class for Argon server objects

use strict;
use warnings;
use Carp;
use Moose;
use Try::Tiny;
use AnyEvent;
use AnyEvent::Socket qw(tcp_server);
use Path::Tiny 'path';
use Argon::Channel;
use Argon::Constants qw(:commands);
use Argon::Log;
use Argon::Message;
use Argon::Util qw(K param);

with qw(Argon::Encryption);

has host => (
  is  => 'rw',
  isa => 'Maybe[Str]',
);

has port => (
  is  => 'rw',
  isa => 'Maybe[Int]',
);

has fh => (
  is  => 'rw',
  isa => 'FileHandle',
  init_arg => undef,
);

has handler => (
  is  => 'rw',
  isa => 'HashRef',
  default => sub {{}},
);

has client => (
  is  => 'rw',
  isa => 'HashRef',
  default => sub {{}},
);

has addr => (
  is  => 'rw',
  isa => 'HashRef',
  default => sub {{}},
);

sub listen {
  my $self = shift;
  $self->configure;

  tcp_server $self->host, $self->port,
    K('_accept',  $self),
    K('_prepare', $self);
}

sub configure {
  my $self = shift;
  $self->handles($PING, K('_ping', $self));
}

sub handles {
  my ($self, $cmd, $cb) = @_;
  $self->handler->{$cmd} ||= [];
  push @{$self->handler->{$cmd}}, $cb;
}

sub get_addr {
  my ($self, $msg) = @_;
  exists $self->addr->{$msg->id}
      && $self->addr->{$msg->id};
}

sub send {
  my ($self, $msg) = @_;
  my $addr = $self->get_addr($msg);

  unless ($addr) {
    log_debug 'message %s (%s) has no connected client', $msg->id, $msg->cmd;
    return;
  }

  try {
    $self->client->{$addr}->send($msg);
  }
  catch {
    log_note 'unable to send message %s (%s) to %s: %s', $msg->id, $msg->cmd, $addr, $_;
    $self->unregister_client($addr);
  };

  delete $self->addr->{$msg->id};
}

sub register_client {
  my ($self, $addr, $fh) = @_;
  $self->client->{$addr} = Argon::Channel->new(
    fh       => $fh,
    key      => $self->key,
    on_msg   => K('_on_client_msg',   $self, $addr),
    on_err   => K('_on_client_err',   $self, $addr),
    on_close => K('_on_client_close', $self, $addr),
  );
}

sub unregister_client {
  my ($self, $addr) = @_;
  delete $self->client->{$addr};

  foreach (keys %{$self->addr}) {
    if ($self->addr->{$_} eq $addr) {
      delete $self->addr->{$_};
    }
  }
}

sub _prepare {
  my ($self, $fh, $host, $port) = @_;
  if ($fh) {
    log_info 'Listening on %s:%d', $host, $port;
    $self->host($host);
    $self->port($port);
    $self->fh($fh);
  } else {
    croak "socket error: $!";
  }

  return;
}

sub _accept {
  my ($self, $fh, $host, $port) = @_;
  my $addr = "$host:$port";
  log_trace 'New connection from %s', $addr;
  $self->register_client($addr, $fh);
  return;
}

sub _on_client_msg {
  my ($self, $addr, $msg) = @_;
  $self->addr->{$msg->id} = $addr;
  $_->($addr, $msg) foreach @{$self->handler->{$msg->cmd}};
}

sub _on_client_err {
  my ($self, $addr, $err) = @_;
  log_info '[client %s] error: %s', $addr, $err;
  $self->unregister_client($addr);
}

sub _on_client_close {
  my ($self, $addr) = @_;
  log_debug '[client %s] disconnected', $addr;
  $self->unregister_client($addr);
}

sub _ping {
  my ($self, $addr, $msg) = @_;
  $self->send($msg->reply(cmd => $ACK));
}

__PACKAGE__->meta->make_immutable;

1;
