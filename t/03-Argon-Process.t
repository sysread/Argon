use strict;
use warnings;
use Carp;
use Test::More qw/no_plan/;
use Argon::Message;
use Argon qw/:commands/;

unshift @INC, 't';

use_ok('Argon::Process');
require_ok('Test::DoublerTask');

my $proc = new_ok('Argon::Process');
ok($proc->spawn, 'spawn process');

for my $i (0 .. 9) {
    my $msg = Argon::Message->new(command => CMD_QUEUE);
    $msg->set_payload(['Test::DoublerTask', [n => $i]]);
    
    my $expected = $i * 2;
    my $reply    = $proc->process($msg);
    my $payload  = $reply->get_payload;

    ok($reply->command eq CMD_COMPLETE, "process task ($i)");
    ok($payload eq $expected, "received expected result ($expected)");
}

ok($proc->kill, 'kill process');
ok(!$proc->is_running, 'process not running');