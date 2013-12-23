use strict;
use warnings;
use Test::More;
use Test::TinyMocker;
use Guard;
use Argon::Message;
use Argon qw(:commands);
use Argon::Client;
use Argon::Stream;

BEGIN { require AnyEvent::Impl::Perl }

$Argon::LOG_LEVEL = 0;

use_ok('Argon::Manager') or BAIL_OUT;

# Create a new manager
my $m = new_ok('Argon::Manager', [port => '4321', host => 'test']) or BAIL_OUT;
$m->init;

ok($m->responds_to($CMD_QUEUE), 'manager responds to CMD_QUEUE');
ok($m->responds_to($CMD_REGISTER), 'manager responds to CMD_REGISTER');

{
    # Queue fails with no capacity
    my $reply = $m->dispatch(Argon::Message->new(cmd => $CMD_QUEUE));
    is($reply->cmd, $CMD_ERROR, 'queue fails with no capacity');
}

# Registration succeeds
{
    my $monitor_called;

    mock 'Argon::Manager', 'start_monitor', sub { $monitor_called = 1 };
    mock 'Argon::Stream', 'connect', sub { bless {}, 'Argon::Stream' };
    mock 'Argon::Stream', 'addr', sub { 'blah:4321' };

    scope_guard {
        unmock 'Argon::Manager', 'start_monitor';
        unmock 'Argon::Stream', 'connect';
        unmock 'Argon::Stream', 'addr';
    };

    my $msg = Argon::Message->new(
        cmd => $CMD_REGISTER,
        key => 'test',
        payload => {
            host => 'foo',
            port => '1234',
            capacity => 4,
        }
    );

    my $reply = $m->dispatch($msg);

    is($reply->cmd, $CMD_ACK, 'register acks');
    is($reply->payload->{client_addr}, 'blah:4321', 'register replies with correct payload');
    is($m->capacity, 4, 'register incs capacity');
    is($m->current_capacity, 4, 'register ups sem');
    ok($m->has_worker('test'), 'has_worker true after register');
    ok($monitor_called, 'register starts monitoring worker connection');
}

{
    mock 'Argon::Client', 'send', sub { return $_[1]->reply(cmd => $CMD_COMPLETE, payload => 42) };
    scope_guard { unmock 'Argon::Client', 'send' };

    # Queue succeeds with registered worker
    my $reply = $m->dispatch(Argon::Message->new(cmd => $CMD_QUEUE));
    is($reply->cmd, $CMD_COMPLETE, 'queue succeeds with registered worker');
    is($reply->payload, 42, 'queue returns expected result from worker client');
}

# Deregistration results in capacity reduction
$m->deregister('test');
is($m->capacity, 0, 'worker disconnect removes capacity');
is($m->current_capacity, 0, 'worker disconnect adjusts sem');
ok(!$m->has_worker('test'), 'worker deregistered');

{
    # Queue fails with degraded capacity
    my $reply = $m->dispatch(Argon::Message->new(cmd => $CMD_QUEUE));
    is($reply->cmd, $CMD_ERROR, 'queue fails with no capacity after dereg');
}

done_testing;
