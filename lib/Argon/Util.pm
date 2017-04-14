package Argon::Util;
# ABSTRACT: Utilities used in Argon classes

use strict;
use warnings;
use Carp;
use AnyEvent;
use Scalar::Util qw(weaken);
use Argon::Log;

use parent 'Exporter';

our @EXPORT_OK = (
  qw(K param interval),
);

sub K ($$;@) {
  my $name = shift;
  my $self = shift;
  my @args = @_;

  my $method = $self->can($name);

  unless ($method) {
    croak "method $name not found";
  }

  weaken $self;
  weaken $method;

  sub { $method->($self, @args, @_) };
}

sub param ($\%;$) {
  my $key   = shift;
  my $param = shift;
  if (!exists $param->{$key} || !defined $param->{$key}) {
    if (@_ == 0) {
      croak "expected parameter '$key'";
    }
    else {
      my $default = shift;
      return (ref $default && ref $default eq 'CODE')
        ? $default->()
        : $default;
    }
  }
  else {
    return $param->{$key};
  }
}

sub interval (;$) {
  my $intvl = shift || 1;
  my $count = 0;

  return sub {
    my $reset = shift;

    if ($reset) {
      $count = 0;
      return;
    }

    my $inc = log($intvl * ($count + 1));
    ++$count;

    return $intvl + $inc;
  };
}

1;
