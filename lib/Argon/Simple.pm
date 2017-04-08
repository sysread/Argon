package Argon::Simple;
# ABSTRACT Utilities for concisely writing Argon client applications

=head1 DESCRIPTION

=head1 SYNOPSIS

  use Argon::Simple;

  Argon {
    remote 'some.argon-host.com:4242', keyfile => '/path/to/secret';

    async my $task => sub { run_task(@_) }, @task_parameters;

    sync $task;
  };

=cut

use strict;
use warnings;
use Carp;
use AnyEvent;
use Try::Tiny;
use Argon;
use Argon::Client;
use Argon::Log;
use Argon::Util qw(param);

use parent 'Exporter';

our @EXPORT = qw(
  Argon
  remote
  sync
  async
);

our $ARGON;

sub Argon (&) {
  my $code = shift;

  my $context = {
    _argon => 1,
    client => undef,
    async  => {},
  };

  local $ARGON = $context;
  local $Argon::ALLOW_EVAL = 1;

  $code->();
}

sub assert_context {
  croak 'not within an Argon context'
    unless defined $ARGON
        && (ref $ARGON || '') eq 'HASH'
        && exists $ARGON->{_argon};
}

sub assert_client {
  assert_context;
  croak 'not connected' unless defined $ARGON->{client};
}

sub remote ($;%) {
  assert_context;
  my ($addr, %param) = @_;
  my ($host, $port) = $addr =~ /^(.+?):(\d+)$/;
  $ARGON->{client} = Argon::Client->new(host => $host, port => $port, %param);
}

sub sync (\[$@]) {
  assert_client;
  my $var = shift;
  return unless exists $ARGON->{async}{$var};
  $$var = $ARGON->{async}{$var}->recv;
  delete $ARGON->{async}{$var};
  return 1;
}

sub async (\$&;@) {
  assert_client;
  my ($var, $code, @args) = @_;
  my $cv = AnyEvent->condvar;
  $ARGON->{async}{$var} = $cv;
  $ARGON->{client}->process($code, \@args, sub {
    my $reply = shift;
    if ($reply->failed) {
      $cv->croak($reply->info);
    } else {
      $cv->send($reply->info);
    }
  });
}

1;
