package Argon::Channel;
# ABSTRACT: Line protocol API for non-blocking sockets

use strict;
use warnings;
use Carp;
use Moose;
use AnyEvent;
use AnyEvent::Handle;
use Argon::Constants qw(:defaults :commands);
use Argon::Log;
use Argon::Types;
use Argon::Util qw(K);
require Argon::Message;

with qw(Argon::Encryption);

has fh => (
  is       => 'ro',
  isa      => 'FileHandle',
  required => 1,
);

has on_msg => (
  is     => 'rw',
  isa    => 'Ar::Callback',
  default => sub { sub{} },
);

has on_ready => (
  is      => 'rw',
  isa     => 'Ar::Callback',
  default => sub { sub{} },
);

has on_close => (
  is      => 'rw',
  isa     => 'Ar::Callback',
  default => sub { sub{} },
);

has on_err => (
  is      => 'rw',
  isa     => 'Ar::Callback',
  default => sub { sub{} },
);

has remote => (
  is  => 'rw',
  isa => 'Maybe[Str]',
);

has handle => (
  is      => 'ro',
  isa     => 'Maybe[AnyEvent::Handle]',
  lazy    => 1,
  builder => '_build_handle',
  handles => {
    disconnect => 'push_shutdown',
  },
);

sub _build_handle {
  my $self = shift;
  AnyEvent::Handle->new(
    fh       => $self->fh,
    on_read  => K('_read',  $self),
    on_eof   => K('_eof',   $self),
    on_error => K('_error', $self),
  );
}

sub BUILD {
  my ($self, $args) = @_;
  $self->identify;
}

sub _eof {
  my ($self, $handle) = @_;
  $self->on_close->();
  undef $self->{handle};
}

sub _error {
  my ($self, $handle, $fatal, $msg) = @_;
  log_debug 'Network error: %s', $msg;
  $self->on_err->($msg);
  $self->disconnect;
}

sub _validate {
  my ($self, $msg) = @_;
  return 1 unless defined $self->remote;
  return 1 if $self->remote eq $msg->token;
  log_error 'token mismatch';
  log_error 'expected %s', $self->remote;
  log_error '  actual %s', $msg->token;
  $self->disconnect;
  return;
}

sub _read {
  my $self = shift;
  $self->handle->push_read(line => $EOL, K('_readline', $self));
}

sub _readline {
  my ($self, $handle, $line) = @_;
  my $msg = $self->decode_msg($line);
  log_trace 'recv: %s', $msg->explain;

  if ($msg->cmd eq $ID) {
    if (!$self->remote || $self->_validate($msg)) {
      $self->remote($msg->token);
      $self->on_ready->();
    }
  }
  elsif ($self->_validate($msg)) {
    $self->on_msg->($msg);
  }
}

sub send {
  my ($self, $msg) = @_;
  $msg->token($self->token);
  log_trace 'send: %s', $msg->explain;

  my $line = $self->encode_msg($msg);

  eval {
    $self->handle->push_write($line);
    $self->handle->push_write($EOL);
  };

  if (my $error = $@) {
    log_error 'send: remote host disconnected';
    log_debug 'error was: %s', $error;
    $self->_eof;
  };
}

sub identify {
  my $self = shift;
  $self->send(Argon::Message->new(cmd => $ID));
}

__PACKAGE__->meta->make_immutable;

1;
