use strict;
use warnings;

use Argon::Message;
use Argon::Respond;
use Argon        qw/:commands/;
use Test::More   tests => 5;

my $msg_ack = Argon::Message->new(command => CMD_ACK);
my $msg_q   = Argon::Message->new(command => CMD_QUEUE);
my $msg_x   = Argon::Message->new(command => CMD_COMPLETE);

my $respond = Argon::Respond->new();
$respond->to(CMD_ACK, sub { ok(shift == $msg_ack, 'msg is correctly dispatched') });
$respond->to(CMD_QUEUE, sub { ok(shift == $msg_q, 'msg is correctly dispatched') });

ok($respond->dispatch($msg_ack), 'dispatch msg');
ok($respond->dispatch($msg_q), 'dispatch msg');
ok(!$respond->dispatch($msg_x), 'dispatch unregistered msg');