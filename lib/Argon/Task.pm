package Argon::Task;
# ABSTRACT: Base interface for Argon-runnable tasks

use strict;
use warnings;
use Storable 'thaw';
use Argon;
use Argon::Log;

sub new {
  my ($class, $code, $args) = @_;
  bless [$code, $args], $class;
}

sub run {
  Argon::ASSERT_EVAL_ALLOWED;
  my $self = shift;

  my $code = do {
    no warnings 'once';
    local $Storable::Eval = 1;
    thaw($self->[0]);
  };

  return $code->(@{$self->[1]});
}

1;
