package Argon::Channel;
# ABSTRACT: Line protocol API for non-blocking sockets

use strict;
use warnings;
use Carp;
use AnyEvent;
use AnyEvent::Handle;
use Argon::Constants qw(:defaults :commands);
use Argon::Log;
use Argon::Message;
use Argon::Util qw(K param encode_msg decode_msg);

sub new {
  my ($class, %param) = @_;
  my $fh       = param 'fh',       %param;
  my $key      = param 'key',      %param;
  my $on_msg   = param 'on_msg',   %param;
  my $on_close = param 'on_close', %param, sub {};
  my $on_err   = param 'on_err',   %param, sub {};

  my $cipher = Argon::Util::cipher($key);
  my $token  = param 'token',  %param, Argon::Util::token($cipher);
  my $remote = param 'remote', %param, undef;

  my $channel = {
    cipher   => $cipher,
    token    => $token,
    remote   => $remote,
    on_msg   => $on_msg,
    on_close => $on_close,
    on_err   => $on_err,
  };

  my $self = bless $channel, $class;

  $self->{handle} = AnyEvent::Handle->new(
    fh       => $fh,
    on_read  => K('_read',  $self),
    on_eof   => K('_eof',   $self),
    on_error => K('_error', $self),
  );

  $self->identify;

  return $self;
}

sub token  { $_[0]->{token}  }
sub remote { $_[0]->{remote} }

sub fh { $_[0]->{handle}->fh }

sub _eof {
  my ($self, $handle) = @_;
  $self->{on_close}->();
  undef $self->{handle};
}

sub _error {
  my ($self, $handle, $fatal, $msg) = @_;
  log_debug 'Network error: %s', $msg;
  $self->{on_err}->($msg);
  $self->disconnect;
}

sub _validate {
  my ($self, $msg) = @_;
  return 1 unless defined $self->{remote};
  return 1 if $self->{remote} eq $msg->token;
  log_error 'token mismatch';
  log_error 'expected %s', $self->{remote};
  log_error '  actual %s', $msg->token;
  $self->disconnect;
  return;
}

sub _read {
  my ($self, $handle) = @_;
  $handle->push_read(line => $EOL, K('_readline', $self));
}

sub _readline {
  my ($self, $handle, $line) = @_;
  my $msg = $self->decode($line);
  log_trace 'recv: %s', $msg->explain;

  if ($msg->cmd eq $ID) {
    $self->{remote} ||= $msg->token;
  } elsif ($self->_validate($msg)) {
    $self->{on_msg}->($msg);
  }
}

sub disconnect {
  my $self = shift;
  $self->{handle}->push_shutdown;
}

sub encode {
  my ($self, $msg) = @_;
  encode_msg($self->{cipher}, $msg);
}

sub decode {
  my ($self, $line) = @_;
  decode_msg($self->{cipher}, $line);
}

sub send {
  my ($self, $msg) = @_;
  $msg->{token} = $self->{token};
  log_trace 'send: %s', $msg->explain;

  my $line = $self->encode($msg);

  eval {
    $self->{handle}->push_write($line);
    $self->{handle}->push_write($EOL);
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

1;
