#-------------------------------------------------------------------------------
# Because Argon::Process is tied to Argon::Worker (Argon::Process is hard-coded
# to run an Argon::Worker), Argon::Worker is exersized here a bit via the
# Test::DoublerTask.
#-------------------------------------------------------------------------------
use strict;
use warnings;
use Carp;

use Test::More;

use POSIX      qw/:sys_wait_h/;
use Argon      qw/:commands/;
use Argon::Message;

unshift @INC, 't';

use_ok('Argon::Process')        or BAIL_OUT('unable to load Argon::Process');
require_ok('Test::DoublerTask') or BAIL_OUT('unable to load task class');

# Test basic usage
{
    my $proc = new_ok('Argon::Process')
        or BAIL_OUT('unable to continue without process object');

    ok(!$proc->is_running, 'is_running (1)');

    ok(my $pid = $proc->spawn, 'spawn (1)')
        or BAIL_OUT('unable to launch process');

    ok($pid =~ /\d+/, 'spawn (2)');

    ok($proc->is_running, 'is_running (2)');

    for my $i (0 .. 9) {
        my $msg = Argon::Message->new(command => CMD_QUEUE);
        $msg->set_payload(['Test::DoublerTask', [n => $i]]);

        my $expected = $i * 2;
        my $reply    = $proc->process($msg);
        my $payload  = $reply->get_payload;

        ok($reply->command eq CMD_COMPLETE, "process task ($i) - cmd");
        ok($payload eq $expected, "process task ($i) - payload");
    }

    ok($proc->kill(1), 'kill');
    ok(!$proc->is_running, 'is_running (3)');
}

# Test automatic shutdown of a process when it goes out of scope
{
    my $proc = new_ok('Argon::Process');
    my $pid  = $proc->spawn;
    undef $proc;
    ok(!kill(0, $pid), 'process self-terminates on DESTROY');
}

done_testing;
