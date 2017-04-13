package Argon::Task;
# ABSTRACT: Base interface for Argon-runnable tasks

use strict;
use warnings;
use Argon;

sub new {
  my ($class, $code, $args) = @_;
  bless [$code, $args], $class;
}

sub run {
  Argon::ASSERT_EVAL_ALLOWED;
  my $self = shift;
  my ($str_code, $args) = @$self;
  my $code = eval "do { $str_code };";
  $code->(@$args);
}

1;
