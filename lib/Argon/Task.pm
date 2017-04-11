package Argon::Task;
# ABSTRACT: Base interface for Argon-runnable tasks

use strict;
use warnings;
use Argon;
use Argon::Log;

sub new {
  my ($class, $code, $args) = @_;
  bless [$code, $args], $class;
}

sub run {
  Argon::ASSERT_EVAL_ALLOWED;
  my ($str_code, $args) = @{$_[0]};
  log_trace 'Executing code: do { %s }', $str_code;
  my $code = eval "do { $str_code };";
  $code->(@$args);
}

1;
