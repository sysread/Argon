use strict;
use warnings;
use Test::More;

use Coro;
use Argon::Node;

unshift @INC, 't';

BEGIN { use AnyEvent::Impl::Perl }

use_ok('Argon::Client');

my $node = Argon::Node->new(
    concurrency => 4,
    queue_limit => 10,
) or BAIL_OUT('unable to create node');

$node->listener; # force socket creation to get host/port

my $thread = async { $node->start };

my $client = new_ok('Argon::Client', [
    port => $node->port,
    host => $node->host,
]);

ok($client->connect, 'connect');

# run
{
    my @range = 0 .. 10;
    my %result;
    my @threads = map {
        my $i = $_;
        async { $result{$i} = $client->run(sub { 2 * shift }, $i) }
    } @range;

    $_->join foreach @threads;

    for my $i (@range) {
        is($result{$i}, $i * 2, 'run');
    }
}

# process
{
    for my $i (0 .. 10) {
        my $result = $client->process(
            class  => 'Test::DoublerTask',
            params => [n => $i],
        );

        is($result, $i * 2, 'process');
    }
}

done_testing;
