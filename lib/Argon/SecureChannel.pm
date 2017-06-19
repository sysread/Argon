package Argon::SecureChannel;
# ABSTRACT: Encrypted Argon::Channel

=head1 DESCRIPTION

An L<Argon::Channel> which implements L<Argon::Encryption> to encrypt all
messages sent. Additionally adds a unique identifier for the channel to assist
with the tracking of message circuits in the Ar network.

=cut

use strict;
use warnings;
use Carp;
use Moose;
use Argon::Log;
use Argon::Constants qw(:commands);

extends qw(Argon::Channel);
with qw(Argon::Encryption);

=head1 ATTRIBUTES

=head2 on_ready

C<SecureChannel> adds an additional setup step during initialization. The
C<on_ready> callback is triggered once that setup has completed and the channel
is ready for use.

=cut

has on_ready => (
  is      => 'rw',
  isa     => 'Ar::Callback',
  default => sub { sub{} },
);

=head2 remote

Holds the identifier for the speaker on the remote end of the channel. If not
provided, the channel will not be ready (see L</on_ready>) until the remote
side has identified itself. Any received messages whose L<Argon::Message/token>
does not match the expected value are rejected.

=cut

has remote => (
  is  => 'rw',
  isa => 'Maybe[Str]',
);

=head1 METHODS

=cut

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
      my $error = $self->remote ne $msg->token
        ? 'Remote channel ID did not match expected value'
        : 'Remote channel ID received out of sequence';

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

=head2 is_ready

Returns true once the remote side has identified itself (C<remote> has been
set).

=cut

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

=head2 identify

Identifies this side of the channel to the remote end by sending its
L<Argon::Encryption/token>.

=cut

sub identify {
  my $self = shift;
  log_trace 'sending identity %s', $self->token;
  $self->send(Argon::Message->new(cmd => $ID));
}

__PACKAGE__->meta->make_immutable;
1;
