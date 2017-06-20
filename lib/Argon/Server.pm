package Argon::Server;
# ABSTRACT: Base class for Argon server objects

=head1 DESCRIPTION

Provides TCP listener services for Ar classes.

=head1 SYNOPSIS

  use Moose;
  use Argon::Constants ':commands';
  use Argon::Server;

  extends 'Argon::Server';

  after configure => sub{
    my $self = shift;
    $self->handles($SOME_COMMAND, K('_handler_method_name', $self));
  };

=cut

use strict;
use warnings;
use Carp;
use Moose;
use Try::Tiny;
use AnyEvent;
use AnyEvent::Socket qw(tcp_server);
use Path::Tiny 'path';
use Argon::SecureChannel;
use Argon::Constants qw(:commands);
use Argon::Log;
use Argon::Message;
use Argon::Util qw(K param);

with qw(Argon::Encryption);

=head1 ATTRIBUTES

=head2 keyfile

Path to the file containing the encryption pass phrase. Inherited from
L<Argon::Encryption>.

=head2 host

The hostname or interface on which to listen. Defaults to C<127.0.0.1>.

=cut

has host => (
  is  => 'rw',
  isa => 'Maybe[Str]',
);

=head2 port

The port on which the server should listen. If not specified, an OS-assigned
port is used and the attribute is set once the listening socket has been
configured.

=cut

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

=head1 METHODS

=head2 start

Starts the manager.

=cut

sub start {
  my $self = shift;
  $self->listen;
}

=head2 listen

Creates the listener socket. Called by L</start>.

=cut

sub listen {
  my $self = shift;
  $self->configure;

  tcp_server $self->host, $self->port,
    K('_accept',  $self),
    K('_prepare', $self);
}

=head2 configure

Classes inheriting C<Argon::Server> register protocol verb handlers with
the L<Argon::Server/handles> method. The C<configure> method provides a
trigger for registering actions during start up.

  after configure => sub{
    my $self = shift;
    $self->handles($ACTION, K('_handler', $self));
  };

=cut

sub configure {
  my $self = shift;
  $self->handles($PING, K('_ping', $self));
}

=head2 handles

Registers a handler for a protocol command verb.

  $self->handles($ACTION, K('_handler_method'), $self));

See L<Argon::Constants/:commands>.

=cut

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

=head2 send

Sends a reply L<Argon::Message>. Emits a warning and returns early if the
message's id does not match one sent by an existing client.

=cut

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
  $self->client->{$addr} = Argon::SecureChannel->new(
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
