use Test2::Bundle::Extended;
use Argon::Queue;
use Argon::Message;
use Argon::Constants qw(:priorities :commands);

sub msg { Argon::Message->new(cmd => $ACK, pri => $_[0]) };
my $msg1 = Argon::Message->new(cmd => $ACK, pri => $NORMAL);
my $msg2 = Argon::Message->new(cmd => $ACK, pri => $HIGH);
my $msg3 = Argon::Message->new(cmd => $ACK, pri => $LOW);
my $msg4 = Argon::Message->new(cmd => $ACK, pri => $NORMAL);

ok my $queue = Argon::Queue->new(4), 'new';
$queue->{balanced} = time + 100; # force to future value prevent rebalancing during testing

is $queue->count, 0, 'count';
ok $queue->is_empty, 'is_empty';
ok !$queue->is_full, '!is_full';

is $queue->put($msg1), 1, 'put';
is $queue->put($msg2), 2, 'put';
is $queue->put($msg3), 3, 'put';
is $queue->put($msg4), 4, 'put';
is $queue->count, 4, 'count';
ok !$queue->is_empty, '!is_empty';
ok $queue->is_full, 'is_full';
ok dies { $queue->put(msg($NORMAL)) }, 'put dies when is_full';
ok dies { $queue->put('foo') }, 'put dies on invalid parameter';

is $queue->get, $msg2, 'get';
is $queue->count, 3, 'count';
is $queue->get, $msg1, 'get';
is $queue->count, 2, 'count';
is $queue->get, $msg4, 'get';
is $queue->count, 1, 'count';
is $queue->get, $msg3, 'get';
is $queue->count, 0, 'count';
is $queue->get, U(), 'get returns undef when is_empty';
is $queue->count, 0, 'count';
ok $queue->is_empty, 'is_empty';
ok !$queue->is_full, '!is_full';

done_testing;
