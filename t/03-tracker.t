use strict;
use warnings;
use Carp;
use Time::HiRes qw/sleep/;
use Test::More;

use_ok('Argon::Tracker') or BAIL_OUT;

{
    my $tracker = new_ok('Argon::Tracker', [
        tracking => 4,
        workers  => 4,
    ]) or BAIL_OUT('cannot continue without Tracker');

    for my $i (1 .. 4) {
        $tracker->start_request($i);
        ok($tracker->capacity == (4 - $i), "capacity ($i)");
    }

    sleep(0.5);
    $tracker->end_request($_) for (1 .. 4);

    my $avg = $tracker->avg_proc_time;
    ok($avg >= 0.5 && $avg <= 1, 'avg_proc_time within 0.5s');

    my $est = 0;
    for my $i (1 .. 4) {
        $tracker->start_request($i);
        ok($tracker->est_proc_time >= $est, "est_proc_time ($i)");
        $est = $tracker->est_proc_time;
    }
}

done_testing;
