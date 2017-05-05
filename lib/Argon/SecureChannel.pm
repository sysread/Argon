package Argon::SecureChannel;
# ABSTRACT: Encrypted Argon::Channel

use strict;
use warnings;
use Carp;
use Moose;
use Argon::Log;
use Argon::Constants qw(:commands);

extends qw(Argon::Channel);
with qw(Argon::Encryption);

has on_ready => (
  is      => 'rw',
  isa     => 'Ar::Callback',
  default => sub { sub{} },
);

has remote => (
  is  => 'rw',
  isa => 'Maybe[Str]',
);

sub BUILD {
  my ($self, $args) = @_;
  $self->identify;
}

around encode_msg => sub {
  my ($orig, $self, $msg) = @_;
  $self->encrypt($self->$orig($msg));
};

around decode_msg => sub {
  my ($orig, $self, $line) = @_;
  $self->$orig($self->decrypt($line));
};

around send => sub {
  my ($orig, $self, $msg) = @_;
  $msg->token($self->token);
  $self->$orig($msg);
};

around recv => sub {
  my ($orig, $self, $msg) = @_;

  if ($msg->cmd eq $ID) {
    if ($self->is_ready) {
      my $error = 'Remote channel ID received out of sequence';
      log_error $error;
      $self->send($msg->error($error));
    }
    else {
      log_trace 'remote host identified as %s', $msg->token;
      $self->remote($msg->token);
      $self->on_ready->();
    }
  }
  elsif ($self->_validate($msg)) {
    $self->$orig($msg);
  }
};

sub is_ready {
  my $self = shift;
  defined $self->remote;
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

sub identify {
  my $self = shift;
  log_trace 'sending identity %s', $self->token;
  $self->send(Argon::Message->new(cmd => $ID));
}

__PACKAGE__->meta->make_immutable;
1;
