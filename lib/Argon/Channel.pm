package Argon::Channel;

use strict;
use warnings;
use Carp;
use AnyEvent;
use AnyEvent::Handle;
use Argon::Constants ':defaults';
use Argon::Log;
use Argon::Message;
use Argon::Util qw(K);

sub new {
  my ($class, %param) = @_;
  my $fh       = $param{fh}       || croak 'expected parameter "fh"';
  my $on_msg   = $param{on_msg}   || croak 'expected parameter "on_msg"';
  my $on_close = $param{on_close} || sub {};
  my $on_err   = $param{on_err}   || sub {};

  my $self = bless {
    on_msg   => $on_msg,
    on_close => $on_close,
    on_err   => $on_err,
  }, $class;

  $self->{handle} = AnyEvent::Handle->new(
    fh       => $fh,
    on_read  => K('_read',  $self),
    on_eof   => K('_eof',   $self),
    on_error => K('_error', $self),
  );

  return $self;
}

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

sub _read {
  my ($self, $handle) = @_;
  $handle->push_read(line => $EOL, K('_readline', $self));
}

sub _readline {
  my ($self, $handle, $line) = @_;
  my $msg = Argon::Message->decode($line);
  $self->{on_msg}->($msg);
}

sub disconnect {
  my $self = shift;
  $self->{handle}->push_shutdown;
}

sub send {
  my ($self, $msg) = @_;
  my $line = $msg->encode;
  $self->{handle}->push_write($line);
  $self->{handle}->push_write($EOL);
}

1;
