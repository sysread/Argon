package Argon::Marshal;
# ABSTRACT: routines for serializing messages

=head1 DESCRIPTION

Provides routines to serialize and deserialize data and L<Argon::Message>s.

=head1 SYNOPSIS

  use Argon::Marshal;

  my $data = ['fnord'];
  my $encoded = encode($data);
  my $decoded = decode($encoded);

  my $msg = Argon::Message->new(...);
  my $encoded = encode_msg($msg);
  my $decoded = decode_msg($encoded);

=cut

use strict;
use warnings;
use Carp;
use Sereal::Decoder qw(sereal_decode_with_object);
use Sereal::Encoder qw(SRL_SNAPPY sereal_encode_with_object);
use MIME::Base64    qw(encode_base64 decode_base64);

use parent 'Exporter';
our @EXPORT = qw(encode decode encode_msg decode_msg);

my $ENC = Sereal::Encoder->new({compress => SRL_SNAPPY});
my $DEC = Sereal::Decoder->new();

sub encode     { encode_base64(sereal_encode_with_object($ENC, $_[0]), '') }
sub decode     { sereal_decode_with_object($DEC, decode_base64($_[0])) }
sub encode_msg { encode(\%{$_[0]}) }
sub decode_msg { bless decode($_[0]), 'Argon::Message' }

1;
