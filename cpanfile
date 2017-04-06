requires 'AnyEvent'     => '';
requires 'Carp'         => '';
requires 'Class::Load'  => '';
requires 'Const::Fast'  => '';
requires 'Data::UUID'   => '';
requires 'JSON::XS'     => '';
requires 'List::Util'   => '';
requires 'MIME::Base64' => '';
requires 'Scalar::Util' => '';
requires 'Storable'     => '';
requires 'Time::HiRes'  => '';

on test => sub {
  requires 'Test2::Bundle::Extended' => 0;
};
