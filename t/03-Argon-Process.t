#-------------------------------------------------------------------------------
# Because Argon::Process is tied to Argon::Worker (Argon::Process is hard-coded
# to run an Argon::Worker), Argon::Worker is exersized here a bit via the
# Test::DoublerTask.
#-------------------------------------------------------------------------------
use strict;
use warnings;
use Carp;

use Test::More tests => 31;

use POSIX      qw/:sys_wait_h/;
use Argon      qw/:commands/;
use Argon::Message;

unshift @INC, 't';

use_ok('Argon::Process');
require_ok('Test::DoublerTask');

# Test basic usage
{
    my $proc = new_ok('Argon::Process');
    ok(!$proc->is_running, 'process does not run initially');

    ok(my $pid = $proc->spawn, 'spawn process');
    ok($pid =~ /\d+/, 'pid is correctly set');

    ok($proc->is_running, 'process running after spawn');

    for my $i (0 .. 9) {
        my $msg = Argon::Message->new(command => CMD_QUEUE);
        $msg->set_payload(['Test::DoublerTask', [n => $i]]);

        my $expected = $i * 2;
        my $reply    = $proc->process($msg);
        my $payload  = $reply->get_payload;

        ok($reply->command eq CMD_COMPLETE, "process task ($i)");
        ok($payload eq $expected, "received expected result ($expected)");
    }

    ok($proc->kill(1), 'kill process');
    ok(!$proc->is_running, 'process not running');
}

# Test automatic shutdown of a process when it goes out of scope
{
    my $proc = new_ok('Argon::Process');
    my $pid  = $proc->spawn;
    undef $proc;
    ok(!kill(0, $pid), 'process self-terminated on DESTROY');
}
