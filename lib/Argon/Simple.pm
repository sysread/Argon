package Argon::Simple;
# ABSTRACT Utilities for concisely writing Argon client applications

=head1 DESCRIPTION

=head1 SYNOPSIS

  use Argon::Simple;

  Argon {
    remote 'some.argon-host.com:4242', keyfile => '/path/to/secret';

    async my $task => sub { run_task(@_) }, @task_parameters;
    sync $task;

    send { run_task($_[0]) } @task_parameters,
      sub { log_completion($_[0]->result) };
  };

=cut

use strict;
use warnings;
use Carp;
use AnyEvent;
use Try::Tiny;
use Argon;
use Argon::Client;
use Argon::Constants qw(:commands);
use Argon::Log;
use Argon::Util qw(param);

use parent 'Exporter';

our @EXPORT = qw(
  Argon remote
  sync async try_async
  send
);

our $ARGON;

sub Argon (&) {
  my $code = shift;

  my $context = {
    _argon => 1,
    client => undef,
    async  => {},
    sent   => AnyEvent->condvar,
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

sub try_async (\$&;@) {
  assert_client;
  my ($var, $code, @args) = @_;
  my $cv = AnyEvent->condvar;
  $ARGON->{async}{$var} = $cv;
  $ARGON->{client}->process($code, \@args, sub {
    my $reply = shift;
    my $result;
    my $error;

    if ($reply->denied) {
      try   { $result = $code->(@args) }
      catch { $error  = $_ };
    } else {
      try   { $result = $reply->result }
      catch { $error  = $_ };
    }

    if ($error) {
      $cv->croak($error);
    } else {
      $cv->send($result);
    }
  });
}

sub sync (;\[$@]) {
  assert_client;

  if (@_) {
    my $var = shift;
    return unless exists $ARGON->{async}{$var};
    $$var = $ARGON->{async}{$var}->recv;
    delete $ARGON->{async}{$var};
    return $$var;
  }
  else {
    $ARGON->{sent}->recv;
    $ARGON->{sent} = AnyEvent->condvar;
  }
}

sub send (&@) {
  assert_client;
  my $code = shift;
  my $cb   = pop;
  my @args = @_;
  $ARGON->{sent}->begin;
  $ARGON->{client}->process(
    $code,
    [@args],
    sub { $ARGON->{sent}->end; $cb->(@_) },
  );
}

1;
