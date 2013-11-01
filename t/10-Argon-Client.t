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
    for my $i (0 .. 10) {
        my $result = $client->run(sub { $_[0] * 2 }, $i);
        is($result, $i * 2, 'process (code)');
    }
}

# process
{
    for my $i (0 .. 10) {
        my $result = $client->process(
            class  => 'Test::DoublerTask',
            params => [n => $i],
        );

        is($result, $i * 2, 'process (class)');
    }
}

done_testing;
