package Argon::Test;

use strict;
use warnings;
use Test2::Bundle::Extended;
use AnyEvent::Impl::Perl;
use AnyEvent::Util;
use Argon::Channel;
use Const::Fast;

use parent 'Exporter';

our @EXPORT = qw(
  ar_test
  channel_pair
);

const our $DEFAULT_TIMEOUT => 30;
const our $KEY => 'how now brown bureaucrat';

sub ar_test {
  my ($name, $timeout, $code);

  if (@_ == 2) {
    ($name, $code) = @_;
    $timeout = $DEFAULT_TIMEOUT;
  } else {
    ($name, $timeout, $code) = @_;
  }

  subtest $name => sub {
    my $cv = AnyEvent->condvar;
    my $guard = AnyEvent::Util::guard { $cv->send };

    my $timer = AnyEvent->timer(
      after => $timeout,
      cb => sub { $cv->croak("Failsafe timeout triggered after $timeout seconds") },
    );

    $code->($cv);

    undef $timer;
  };
}

sub channel_pair {
  my ($handlers1, $handlers2) = @_;
  $handlers1 ||= {};
  $handlers2 ||= {};

  my ($fh1, $fh2) = AnyEvent::Util::portable_socketpair;
  AnyEvent::Util::fh_nonblocking($fh1, 1);
  AnyEvent::Util::fh_nonblocking($fh2, 1);

  my $ch1 = Argon::Channel->new(
    key      => $KEY,
    fh       => $fh1,
    on_msg   => $handlers1->{on_msg},
    on_close => $handlers1->{on_close},
    on_err   => $handlers1->{on_err},
  );

  my $ch2 = Argon::Channel->new(
    key      => $KEY,
    fh       => $fh2,
    on_msg   => $handlers2->{on_msg},
    on_close => $handlers2->{on_close},
    on_err   => $handlers2->{on_err},
  );

  return ($ch1, $ch2);
}

1;
