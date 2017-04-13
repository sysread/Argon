package Argon::Util;
# ABSTRACT: Utilities used in Argon classes

use strict;
use warnings;
use Carp;
use AnyEvent;
use Crypt::CBC;
use Scalar::Util qw(weaken);
use Sereal::Decoder qw(sereal_decode_with_object);
use Sereal::Encoder qw(SRL_SNAPPY sereal_encode_with_object);
use Argon::Log;

use parent 'Exporter';

our %EXPORT_TAGS = (
  'encoding' => [qw(
    encrypt
    decrypt
    encode
    decode
    encode_msg
    decode_msg
    token
    cipher
  )],
);

our @EXPORT_OK = (
  qw(K param interval),
  map { @$_ } values %EXPORT_TAGS,
);

our $ENC = Sereal::Encoder->new({compress => SRL_SNAPPY});
our $DEC = Sereal::Decoder->new();

sub K {
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

sub token {
  my $cipher = shift;
  unpack 'H*', $cipher->random_bytes(8);
}

sub encrypt {
  my ($cipher, $string) = @_;
  $cipher->encrypt_hex($string);
}

sub decrypt {
  my ($cipher, $string) = @_;
  $cipher->decrypt_hex($string);
}

sub encode {
  my ($cipher, $obj) = @_;
  my $sereal = sereal_encode_with_object($ENC, $obj);
  encrypt($cipher, $sereal);
}

sub decode {
  my ($cipher, $line) = @_;
  my $sereal = decrypt($cipher, $line);
  sereal_decode_with_object($DEC, $sereal);
}

sub encode_msg {
  my ($cipher, $msg) = @_;
  my %data = %$msg;
  encode($cipher, \%data);
}

sub decode_msg {
  my ($cipher, $line) = @_;
  my $data = decode($cipher, $line);
  bless $data, 'Argon::Message';
}

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
