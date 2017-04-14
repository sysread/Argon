package TestClass;
use Moose;
use Argon::Encryption;
with 'Argon::Encryption';
__PACKAGE__->meta->make_immutable;
1;

package main;
use Test2::Bundle::Extended;
use Argon::Message;
use Argon::Constants qw(:commands :priorities);

my $payload = [1, 2, 3];

ok my $obj = TestClass->new(key => 'foo'), 'consumer';
ok my $data = $obj->encode($payload), 'encode';
is $obj->decode($data), $payload, 'decode';

my $msg = Argon::Message->new(cmd => $QUEUE, pri => $NORMAL, info => $payload);
ok my $line = $obj->encode_msg($msg), 'encode_msg';
is $obj->decode_msg($line), $msg, 'decode_msg';

done_testing;
