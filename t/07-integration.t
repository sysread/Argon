use strict;
use warnings;
use Test::More;
use List::Util qw(shuffle);
use AnyEvent;
use Coro;
use Coro::AnyEvent;

use Argon::Client;
use Argon::Manager;
use Argon::Worker;

my $manager_cv     = AnyEvent->condvar;;
my $manager        = Argon::Manager->new();
my $manager_thread = async { $manager->start(sub { $manager_cv->send(shift) }) };
my $manager_addr   = $manager_cv->recv;

like($manager_addr, qr/^[\w\.]+:\d+$/, 'manager address is set');

my $worker_cv      = AnyEvent->condvar;
my $worker         = Argon::Worker->new(manager => $manager_addr);
my $worker_thread  = async { $worker->start(sub { $worker_cv->send }) };
$worker_cv->recv;

# Wait for worker to connect to manager.
# TODO There's got to be a better way to do this. But if the worker thread blocks
# while waiting for a manager connection, the manager cannot connect because the
# worker startup doesn't cede.
Coro::AnyEvent::sleep(3);

my $client = Argon::Client->new(host => $manager->host, port => $manager->port);
$client->connect;

my @range    = 1 .. 100;
my %deferred = map { $_ => $client->defer(sub { $_[0] * 2 }, [$_]) } @range;
my %results  = map { $_ => $deferred{$_}->() } keys %deferred;

foreach my $i (shuffle @range) {
    is($results{$i}, $i * 2, "expected results for $i");
}

$client->shutdown;
$worker->stop;
$manager->stop;

$manager_thread->join;
$worker_thread->join;

done_testing;
