package Argon::Log;
# ABSTRACT: Simple logging wrapper

=head1 DESCRIPTION

Simple wrapper around AnyEvent::Log.

=head1 SYNOPSIS

  use Argon::Log;

  log_level 'trace';

  log_trace 'something happened: %s', $msg;
  log_debug 'something happened: %s', $msg;
  log_info  'something happened: %s', $msg;
  log_note  'something happened: %s', $msg;
  log_warn  'something happened: %s', $msg;
  log_error 'something happened: %s', $msg;
  log_fatal 'something happened: %s', $msg;

=cut

use strict;
use warnings;
use Carp;
use Time::HiRes 'time';
use AnyEvent::Log;

use parent 'Exporter';

our @EXPORT = qw(
  log_level
  log_trace
  log_debug
  log_info
  log_note
  log_warn
  log_error
  log_fatal
);

$Carp::Internal{'Argon::Log'} = 1;

sub msg {
  my $msg = shift or croak 'expected $msg';
  my @args = @_;

  foreach my $i (0 .. (@args - 1)) {
    if (!defined $args[$i]) {
      croak sprintf('format parameter %d is uninitialized', $i + 1);
    }
  }

  sub {
    if (@args == 1 && (ref($args[0]) || '') eq 'CODE') {
      my $val = $args[0]->();
      @args = ($val);
    }

    sprintf "[%d] $msg", $$, @args;
  };
}

sub log_trace ($;@) { @_ = ('trace', msg(@_)); goto &AE::log }
sub log_debug ($;@) { @_ = ('debug', msg(@_)); goto &AE::log }
sub log_info  ($;@) { @_ = ('info' , msg(@_)); goto &AE::log }
sub log_note  ($;@) { @_ = ('note' , msg(@_)); goto &AE::log }
sub log_warn  ($;@) { @_ = ('warn' , msg(@_)); goto &AE::log }
sub log_error ($;@) { @_ = ('error', msg(@_)); goto &AE::log }
sub log_fatal ($;@) { @_ = ('fatal', msg(@_)); goto &AE::log }

sub log_level { $AnyEvent::Log::FILTER->level(@_) }

1;
