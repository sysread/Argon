package Argon::Encryption;
# ABSTRACT: Role providing methods and attributes to encrypt Argon::Message traffic

use strict;
use warnings;
use Carp;
use Moose::Role;
use Moose::Util::TypeConstraints;
use Crypt::CBC;
use Path::Tiny qw(path);
use Argon::Types;

my %CIPHER;

has keyfile => (
  is  => 'ro',
  isa => 'Ar::FilePath',
);

has key => (
  is      => 'ro',
  isa     => 'Str',
  lazy    => 1,
  builder => '_build_key',
);

sub _build_key {
  my $self = shift;
  croak 'keyfile required if key is not specified'
    unless $self->keyfile;
  path($self->keyfile)->slurp_raw;
}

has cipher => (
  is      => 'ro',
  isa     => 'Crypt::CBC',
  lazy    => 1,
  builder => '_build_cipher',
  handles => {
    encrypt => 'encrypt_hex',
    decrypt => 'decrypt_hex',
  },
);

sub _build_cipher {
  my $self = shift;

  $CIPHER{$self->key} ||= Crypt::CBC->new(
    -key    => $self->key,
    -cipher => 'Rijndael',
    -salt   => 1,
  );

  $CIPHER{$self->key};
}

has token => (
  is      => 'ro',
  isa     => 'Str',
  lazy    => 1,
  builder => 'create_token',
);

sub create_token {
  my $self = shift;
  unpack 'H*', $self->cipher->random_bytes(8);
}

1;
