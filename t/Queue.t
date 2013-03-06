use strict;
use warnings;

use Argon::Message;
use Argon::Queue;
use List::Util   qw/shuffle/;
use Test::More   tests => 1507;

my $LIMIT = 500;

my $queue = Argon::Queue->new(limit => $LIMIT);
ok($queue->isa('Argon::Queue'), 'instantiation');
ok($queue->{limit} == $LIMIT, 'instantiation');
ok($queue->{size} == 0, 'instantiation');
ok($queue->is_empty, 'instantiation, queue is_empty');


my @items = shuffle(0 .. ($LIMIT - 1));
foreach my $i (@items) {
    my $msg = Argon::Message->new(command => 0, priority => $i);
    ok($queue->put($msg), "queue put ($i)");
}

ok($queue->is_full, 'queue limit');
eval { $queue->put(1) };
ok($@, 'queue limit');

my $prev;
my $msg;
until ($queue->is_empty) {
    $msg = $queue->get;
    ok($msg, sprintf('queue get (%d)', $msg->priority));

    if (defined $prev) {
        ok($msg <= $prev, sprintf('queue gets in correct order (%d before %d)', $prev->priority, $msg->priority));
    }

    $prev = $msg;
}

ok($queue->is_empty, 'queue is_empty');

eval { $queue->get };
ok($@, 'queue limit');