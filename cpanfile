requires 'AnyEvent'                  => '';
requires 'Carp'                      => '';
requires 'Class::Load'               => '';
requires 'Const::Fast'               => '';
requires 'Crypt::CBC'                => '';
requires 'Crypt::Rijndael'           => '';
requires 'Data::UUID'                => '';
requires 'Getopt::Long::Descriptive' => '';
requires 'JSON::XS'                  => '';
requires 'List::Util'                => '';
requires 'MIME::Base64'              => '';
requires 'Path::Tiny'                => '';
requires 'Scalar::Util'              => '';
requires 'Storable'                  => '';
requires 'Time::HiRes'               => '';

on test => sub {
  requires 'Test2::Bundle::Extended' => 0;
  requires 'Test::Pod'               => '1.41';
};
