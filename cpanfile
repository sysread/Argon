requires 'perl', '5.010';

requires 'AnyEvent'                  => '7.14';
requires 'Carp'                      => '0';
requires 'Class::Load'               => '0';
requires 'Const::Fast'               => '0';
requires 'Crypt::CBC'                => '0';
requires 'Crypt::Rijndael'           => '0';
requires 'Data::Dump::Streamer'      => '2.40';
requires 'Data::UUID::MT'            => '0';
requires 'Getopt::Long::Descriptive' => '0';
requires 'List::Util'                => '0';
requires 'Moose'                     => '0';
requires 'Path::Tiny'                => '0.104';
requires 'Scalar::Util'              => '0';
requires 'Sereal::Decoder'           => '4.002';
requires 'Sereal::Encoder'           => '4.002';
requires 'Test2::Bundle::Extended'   => '0';
requires 'Time::HiRes'               => '0';
requires 'Try::Catch'                => '0';
requires 'parent'                    => '0';

on test => sub {
  requires 'Devel::Refcount'         => '0';
  requires 'Path::Tiny'              => '0.097';
  requires 'Test2::Bundle::Extended' => '0';
  requires 'Test::Pod'               => '0';
  requires 'Test::Refcount'          => '0';
};
