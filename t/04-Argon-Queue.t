use strict;
use warnings;
use Carp;

use Test::More tests => 13;

use_ok('Argon::Queue');

# Positive path
{
    my $q = new_ok('Argon::Queue', [ max_size => 2 ])
        or BAIL_OUT('unable to continue without queue object');

    ok($q->count == 0, 'initial count 0');
    ok($q->is_empty, 'is_empty (1)');
    ok(!$q->is_full, 'is_full (1)');

    ok($q->put(1), 'put (1)');
    ok($q->put(2), 'put (2)');

    ok($q->is_full, 'is_full (2)');
    ok(!$q->is_empty, 'is_empty (2)');

    eval { $q->put(3) };
    ok($@ =~ 'queue is full', 'over-fill croaks');

    ok($q->get(1) == 1, 'get (1)');
    ok($q->get(2) == 2, 'get (2)');
    ok($q->is_empty, 'is_empty (3)');
}