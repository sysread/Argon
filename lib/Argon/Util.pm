package Argon::Util;
# ABSTRACT: Utilities used in Argon classes

use strict;
use warnings;
use Carp;
use Crypt::CBC;
use JSON::XS qw(encode_json decode_json);
use Scalar::Util 'weaken';
use Argon::Log;

use parent 'Exporter';

our %EXPORT_TAGS = (
  'encoding' => [qw(encode decode)],
);

our @EXPORT_OK = (
  qw(K param cipher),
  map { @$_ } values %EXPORT_TAGS,
);

sub K {
  my ($fn, @args) = @_;

  if (ref $fn && ref $fn eq 'CODE') {
    return sub { $fn->(@args, @_) };
  }
  else {
    my $self = shift @args;

    my $method = $self->can($fn)
      or croak "method $fn not found";

    weaken $self;
    return sub { $method->($self, @args, @_) };
  }
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

sub decode ($) { goto \&decode_json }
sub encode ($) { goto \&encode_json }

my %ciphers;

sub cipher {
  my $key = shift;

  $ciphers{$key} ||= Crypt::CBC->new(
    -key    => $key,
    -cipher => 'Rijndael',
    -salt   => 1,
  );

  return $ciphers{$key};
}

1;
