requires 'AnyEvent'                  => '';
requires 'Carp'                      => '';
requires 'Class::Load'               => '';
requires 'Crypt::CBC'                => '';
requires 'Crypt::Rijndael'           => '';
requires 'Const::Fast'               => '';
requires 'Data::UUID'                => '';
requires 'JSON::XS'                  => '';
requires 'List::Util'                => '';
requires 'MIME::Base64'              => '';
requires 'Scalar::Util'              => '';
requires 'Storable'                  => '';
requires 'Time::HiRes'               => '';
requires 'Getopt::Long::Descriptive' => '';

on test => sub {
  requires 'Test2::Bundle::Extended' => 0;
  requires 'Test::Pod'               => '1.41';
};
