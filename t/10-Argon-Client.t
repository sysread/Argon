use strict;
use warnings;
use Test::More;
use List::Util qw(shuffle);
use Coro;
use Coro::Debug;
use AnyEvent;
use Argon qw(:logging);
use Argon::Node;

#$Argon::DEBUG = $Argon::DEBUG | Argon::DEBUG_DEBUG;

unshift @INC, 't';

BEGIN { use AnyEvent::Impl::Perl }


use_ok('Argon::Client');

my $node = Argon::Node->new(
    concurrency => 4,
    queue_limit => 10,
) or BAIL_OUT('unable to create node');

$node->listener; # force socket creation to get host/port

my $started = AnyEvent->condvar;
my $thread = async {
    local $Coro::current->{desc} = 'Unit test node';
    $node->start($started);
};

$started->recv;

my $client = new_ok('Argon::Client', [
    port => $node->port,
    host => $node->host,
]);

ok($client->connect, 'connect');

# run
{
    for my $i (1 .. 10) {
        my $result = $client->run(sub { $_[0] * 2 }, $i);
        is($result, $i * 2, 'process (code)');
    }
}

# process
{
    for my $i (1 .. 10) {
        my $result = $client->process(
            class  => 'Test::DoublerTask',
            params => [n => $i],
        );

        is($result, $i * 2, 'process (class)');
    }
}

# out of order process
{
    my $count = 100;
    my %result;
    my @threads;

    for my $i (shuffle(1 .. $count)) {
        push @threads, async {
            local $Coro::current->{desc} = "PROCESS $i";
            $result{$i} = $client->process(
                class  => 'Test::DoublerTask',
                params => [n => $i],
            );
        }
    }

    $_->join foreach @threads;
    warn "HERE";

    for my $i (1 .. $count) {
        is($result{$i}, $i * 2, 'process out-of-order');
    }
}

done_testing;
