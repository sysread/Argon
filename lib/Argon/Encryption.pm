package Argon::Encryption;
# ABSTRACT: Role providing methods and attributes to encrypt Argon::Message traffic

use strict;
use warnings;
use Carp;
use Moose::Role;
use Moose::Util::TypeConstraints;
use Crypt::CBC;
use Path::Tiny qw(path);
use Sereal::Decoder qw(sereal_decode_with_object);
use Sereal::Encoder qw(SRL_SNAPPY sereal_encode_with_object);
use Argon::Types;

my $ENC = Sereal::Encoder->new({compress => SRL_SNAPPY});
my $DEC = Sereal::Decoder->new();
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
  builder => '_build_token',
);

sub _build_token {
  my $self = shift;
  unpack 'H*', $self->cipher->random_bytes(8);
}

sub encode { $_[0]->encrypt(sereal_encode_with_object($ENC, $_[1])) }
sub decode { sereal_decode_with_object($DEC, $_[0]->decrypt($_[1])) }

sub encode_msg {
  my ($self, $msg) = @_;
  my %data = %$msg;
  $self->encode(\%data);
}

sub decode_msg {
  my ($self, $line) = @_;
  my $data = $self->decode($line);
  bless $data, 'Argon::Message';
}

1;
