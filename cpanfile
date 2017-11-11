requires 'perl', '5.010';

requires 'AnyEvent'                  => 0;
requires 'Carp'                      => 0;
requires 'Class::Load'               => 0;
requires 'Const::Fast'               => 0;
requires 'Crypt::CBC'                => 0;
requires 'Crypt::Rijndael'           => 0;
requires 'Data::Dump::Streamer'      => 1.11;
requires 'Data::UUID'                => 0;
requires 'Getopt::Long::Descriptive' => 0;
requires 'List::Util'                => 0;
requires 'Moose'                     => 0;
requires 'Path::Tiny'                => 0.097;
requires 'Scalar::Util'              => 0;
requires 'Sereal::Encoder'           => 0;
requires 'Sereal::Decoder'           => 0;
requires 'Time::HiRes'               => 0;
requires 'Try::Tiny'                 => 0;

on test => sub {
  requires 'Test2::Bundle::Extended' => 0;
  requires 'Test::Pod'               => 1.41;
  requires 'Path::Tiny'              => 0.097;
  requires 'Test::Refcount'          => 0;
  requires 'Devel::Refcount'         => 0;
};
