package Argon::Log;
# ABSTRACT: Simple logging wrapper

use strict;
use warnings;
use Carp;
use Time::HiRes 'time';
use AnyEvent::Log;

use parent 'Exporter';

our @EXPORT = qw(
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

  foreach my $i (0 .. (@_ - 1)) {
    if (!defined $_[$i]) {
      croak sprintf('format parameter %d is uninitialized', $i + 1);
    }
  }

  sprintf "[%d] $msg", $$, @_;
}

sub log_trace ($;@) { @_ = ('trace', msg(@_)); goto &AE::log }
sub log_debug ($;@) { @_ = ('debug', msg(@_)); goto &AE::log }
sub log_info  ($;@) { @_ = ('info' , msg(@_)); goto &AE::log }
sub log_note  ($;@) { @_ = ('note' , msg(@_)); goto &AE::log }
sub log_warn  ($;@) { @_ = ('warn' , msg(@_)); goto &AE::log }
sub log_error ($;@) { @_ = ('error', msg(@_)); goto &AE::log }
sub log_fatal ($;@) { @_ = ('fatal', msg(@_)); goto &AE::log }

1;
