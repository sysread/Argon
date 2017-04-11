package Argon::Channel;
# ABSTRACT: Line protocol API for non-blocking sockets

use strict;
use warnings;
use Carp;
use AnyEvent;
use AnyEvent::Handle;
use Data::Dumper;
use Argon::Constants ':defaults';
use Argon::Log;
use Argon::Message;
use Argon::Util qw(K param);

sub new {
  my ($class, %param) = @_;
  my $fh       = param 'fh',       %param;
  my $key      = param 'key',      %param;
  my $on_msg   = param 'on_msg',   %param;
  my $on_close = param 'on_close', %param, sub {};
  my $on_err   = param 'on_err',   %param, sub {};

  my $self = bless {
    cipher   => Argon::Util::cipher($key),
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
  $self->{on_close}->($self);
  undef $self->{handle};
}

sub _error {
  my ($self, $handle, $fatal, $msg) = @_;
  log_debug 'Network error: %s', $msg;
  $self->{on_err}->($self, $msg);
  $self->disconnect;
}

sub _read {
  my ($self, $handle) = @_;
  $handle->push_read(line => $EOL, K('_readline', $self));
}

sub _readline {
  my ($self, $handle, $line) = @_;
  my $msg = $self->decode($line);
  log_trace 'received %s', sub { _dump($msg) };
  $self->{on_msg}->($self, $msg);
}

sub disconnect {
  my $self = shift;
  $self->{handle}->push_shutdown;
}

sub send {
  my ($self, $msg) = @_;
  my $line = $self->encode($msg);
  $self->{handle}->push_write($line);
  $self->{handle}->push_write($EOL);
  log_trace 'sent %s', sub { _dump($msg) };
}

sub _dump {
  my $msg = shift;
  local $Data::Dumper::Indent  = 0;
  local $Data::Dumper::Varname = 'MSG';
  Dumper($msg);
}

sub encode {
  my ($self, $msg) = @_;
  my %data = %$msg;
  my $line = Argon::Util::encode(\%data);
  $self->{cipher}->encrypt_hex($line);
}

sub decode {
  my ($self, $line) = @_;
  my $data = $self->{cipher}->decrypt_hex($line);
  bless Argon::Util::decode($data), 'Argon::Message';
}

1;
