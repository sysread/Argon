package Argon::Server;
# ABSTRACT: Base class for Argon server objects

use strict;
use warnings;
use Carp;
use Try::Tiny;
use AnyEvent;
use AnyEvent::Socket qw(tcp_server);
use Path::Tiny 'path';
use Argon::Channel;
use Argon::Constants qw(:commands);
use Argon::Log;
use Argon::Message;
use Argon::Util qw(K param);

sub new {
  my ($class, %param) = @_;
  my $host    = param 'host', %param, undef;
  my $port    = param 'port', %param, undef;
  my $keyfile = param 'keyfile', %param, undef;

  my $key = defined $keyfile
    ? path($keyfile)->slurp_raw
    : param 'key', %param;

  my $self = bless {
    key      => $key,
    host     => $host,
    port     => $port,
    handlers => {},
    client   => {},
    addr     => {},
  }, $class;

  $self->handles($PING, K('_ping', $self));

  tcp_server $host, $port,
    K('_accept',  $self),
    K('_prepare', $self);

  return $self;
}

sub cipher {
  my $self = shift;
  Argon::Util::cipher($self->{key});
}

sub handles {
  my ($self, $cmd, $cb) = @_;
  $self->{handlers}{$cmd} ||= [];
  push @{$self->{handlers}{$cmd}}, $cb;
}

sub client {
  my ($self, $addr) = @_;
  $self->{client}{$addr};
}

sub addr {
  my ($self, $msg) = @_;
  exists $self->{addr}{$msg->id} && $self->{addr}{$msg->id};
}

sub send {
  my ($self, $msg) = @_;
  my $addr = exists $self->{addr}{$msg->id} && $self->{addr}{$msg->id};

  unless ($addr) {
    log_debug 'message %s (%s) has no connected client', $msg->id, $msg->cmd;
    return;
  }

  try {
    $self->client($addr)->send($msg);
  }
  catch {
    log_note 'unable to send message %s (%s) to %s: %s', $msg->id, $msg->cmd, $addr, $_;
    $self->unregister_client($addr);
  };

  delete $self->{addr}{$msg->id};
}

sub register_client {
  my ($self, $addr, $fh) = @_;
  $self->{client}{$addr} = Argon::Channel->new(
    fh       => $fh,
    key      => $self->{key},
    on_msg   => K('_on_client_msg',   $self, $addr),
    on_err   => K('_on_client_err',   $self, $addr),
    on_close => K('_on_client_close', $self, $addr),
  );
}

sub unregister_client {
  my ($self, $addr) = @_;
  delete $self->{client}{$addr};

  foreach (keys %{$self->{addr}}) {
    if ($self->{addr}{$_} eq $addr) {
      delete $self->{addr}{$_};
    }
  }
}

sub _prepare {
  my ($self, $fh, $host, $port) = @_;
  if ($fh) {
    log_debug 'Listening on %s:%d', $host, $port;
    $self->{host} = $host;
    $self->{port} = $port;
    $self->{fh}   = $fh;
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
  my ($self, $addr, $channel, $msg) = @_;
  $self->{addr}{$msg->id} = $addr;
  $_->($addr, $msg) foreach @{$self->{handlers}{$msg->cmd}};
}

sub _on_client_err {
  my ($self, $addr, $channel, $err) = @_;
  log_info '[client %s] error: %s', $addr, $err;
  $self->unregister_client($addr);
}

sub _on_client_close {
  my ($self, $addr, $channel) = @_;
  log_debug '[client %s] disconnected', $addr;
  $self->unregister_client($addr);
}

sub _ping {
  my ($self, $addr, $msg) = @_;
  $self->send($msg->reply(cmd => $ACK));
}

1;
