use strict;
use warnings;
use Carp;

use Test::More qw/no_plan/;
use Argon::Message;
use Argon qw/:logging :commands/;

require_ok('Argon::Process');
use_ok('Argon::Process');
use Argon::Process;

my $proc = Argon::Process->new(
    class => 'TestProcessClass',
    args  => [1,2,3],
    inc   => [],
);

ok($proc->spawn, 'process spawns');

ok(!$!, 'process spawns without error') or die $!;
ok(!$?, 'process does not immediately quit');

my $msg = Argon::Message->new(command => CMD_QUEUE);
$msg->set_payload('Hello world');
my $reply = $proc->send($msg);

ok(defined $reply, 'process ipc functions');
ok($reply->get_payload eq 'You said "Hello world"', 'proces ipc is accurate');

my $term = Argon::Message->new(command => CMD_QUEUE);
$term->set_payload('EXIT');
$proc->send($term);