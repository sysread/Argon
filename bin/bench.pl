#!/bin/env perl

use strict;
use warnings;
use Carp;

use Coro;
use Getopt::Long;
use Time::HiRes qw/time/;
use Argon       qw/LOG :commands/;
use Argon::Client;

# Default values
my $host     = 'localhost';
my $port     = 8888;
my $total    = 1000;
my $conc     = 4;
my $delay    = 0.05;
my $variance = 0;

GetOptions(
    'host=s'       => \$host,
    'port=i'       => \$port,
    'number=i'     => \$total,
    'concurrent=i' => \$conc,
    'delay=f'      => \$delay,
    'variance=f'   => \$variance,
);

# If the delay is 0, use the variance to calculate an average such that the
# delay ought not fall below zero.
if ($delay == 0 && $variance != 0) {
    LOG('Warning: recalculated delay and variance to prevent negative delays.');
    $delay    = $variance / 2;
    $variance = $variance / 2;
}
# If the variance could cause the delay to be less than zero, use the variance
# to calculate the effective avg delay.
elsif ($delay < $variance) {
    LOG('Warning: recalculated delay and variance to prevent negative delays.');
    my $difference = $variance - $delay;
    $delay    += $difference;
    $variance -= $difference;
}

LOG('Benchmark plan:');
LOG('Host: %s:%d', $host, $port);
LOG('Will send %d tasks over %d concurrent connections', $total, $conc);
LOG('Simulated task will average %0.4fs (+/-%0.4fs) to complete.', $delay, $variance);
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

# Pre-generate task data to keep its overhead out of the statistics
my @tasks;
foreach my $task (1 .. $total) {
    if ($variance != 0) {
        my $rand  = rand($variance);
        my $delay = ($delay > $rand && $task % 2 == 0)
            ? ($delay - $rand)
            : ($delay + $rand);
        push @tasks, [num => $task, delay => $delay];
    } else {
        push @tasks, [num => $task, delay => $delay];
    }
}

# Start
my @threads;
my $complete     = 0;
my $start_time   = time;

foreach my $task (@tasks) {
    my $client = $clients->get;

    push @threads, async {
        my $result = $client->process(
            class  => 'SampleTask',
            params => $task,
        );

        my $finish = time;

        $clients->put($client);
        ++$complete;

        if ($result->command == CMD_ERROR) {
            LOG('Error: %s', $result->get_payload);
        }

        if ($complete % $report_every == 0) {
            my $taken = $finish - $start_time;
            my $avg   = $taken / $complete;
            LOG($format, $complete, $total, $taken, $avg);
        }
    }
}

# Wait for all threads to complete
$_->join foreach @threads;

# Output summary
my $taken = time - $start_time;
my $avg   = $taken / $complete;
LOG('--------------------------------------------------------------------------------');
LOG($format, $complete, $total, $taken, $avg);
LOG('Savings / Overhead: %0.4fs/task', ($avg - $delay));

exit 0;