#!/bin/env perl

use strict;
use warnings;
use Carp;

use EV;
use Coro;
use Getopt::Long;
use Time::HiRes qw/time/;
use Argon::Client;
use Argon qw/LOG :commands/;

# Default values
my $host  = 'localhost';
my $port  = 8888;
my $total = 1000;
my $conc  = 4;
my $delay = 0.05;

GetOptions(
    'host=s'       => \$host,
    'port=i'       => \$port,
    'number=i'     => \$total,
    'delay=f'      => \$delay,
    'concurrent=i' => \$conc,
);

LOG('Benchmark plan:');
LOG('Host: %s:%d', $host, $port);
LOG('Will send %d tasks over %d concurrent connections', $total, $conc);
LOG('Simulated task will take %0.4f seconds to complete.', $delay);
LOG('--------------------------------------------------------------------------------');

# Create connections
my $clients = Coro::Channel->new();
foreach (1 .. $conc) {
    my $client = Argon::Client->new(host => $host, port => $port);
    $client->connect;
    $clients->put($client);
}

# Configure reporting
my $report_every = $total / 10;
my $int_padding  = length "$total";
my $format       = "%0${int_padding}d/%0${int_padding}d complete in %.4fs (avg %.4fs/task)";

# Start
my @threads;
my $complete     = 0;
my $start_time   = time;

foreach my $task (1 .. $total) {
    my $client = $clients->get;

    push @threads, async {
        my $result = $client->process(
            class  => 'SampleTask',
            params => [num => $task, delay => $delay],
        );

        my $finish = time;

        $clients->put($client);
        ++$complete;

        if ($complete % $report_every == 0) {
            my $taken = $finish - $start_time;
            my $avg   = $taken / $complete;
            LOG($format, $complete, $total, $taken, $avg);
        }
    }
}

$_->join foreach @threads;

my $taken = time - $start_time;
my $avg   = $taken / $complete;
LOG('--------------------------------------------------------------------------------');
LOG($format, $complete, $total, $taken, $avg);
LOG('Savings / Overhead: %0.4fs/task', ($avg - $delay));

exit 0;