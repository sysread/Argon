#!/bin/env perl

use strict;
use warnings;
use Carp;

use EV;
use Coro;
use Getopt::Long;
use Time::HiRes qw/time/;
use Argon::Stream;
use Argon::Message;
use Argon qw/LOG :commands/;

# Default values
my $host  = 'localhost';
my $port  = 8888;
my $total = 1000;
my $conc  = 200;
my $delay = 0.05;

GetOptions(
    'host=s'        => \$host,
    'port=i'        => \$port,
    'number=i'      => \$total,
    'concurrency=i' => \$conc,
    'delay=f'       => \$delay,
);

LOG('Benchmark plan:');
LOG('Host: %s:%d', $host, $port);
LOG('Will perform %d tasks with a load of %d tasks pending.', $total, $conc);
LOG('Simulated task will take %f seconds to complete.', $delay);
LOG('--------------------------------------------------------------------------------');

my $stream   = Argon::Stream->connect(host => $host, port => $port);
my $pending  = Coro::Semaphore->new($conc);
my $received = 0;
my @pending;
my $start_time = time;

$stream->monitor(sub {
    my ($stream, $error) = @_;
    LOG('Connection error: %s', $error);
    exit 1;
});

foreach my $i (1 .. $total) {
    $pending->down;

    my $coro = async {
        my $msg = Argon::Message->new(command => CMD_QUEUE);
        $msg->set_payload(['SampleTask', [num => $i, delay => $delay]]);

        my $reply    = $stream->send($msg);
        my $end_time = time;

        if ($reply->command == CMD_ERROR) {
            LOG("Error: %s", $reply->get_payload);
            exit 1;
        } else {
            if ($i * 2 != $reply->get_payload) {
                LOG('Error: invalid result! (%d * 2 != %d)', $i, $reply->get_payload);
                exit 1;
            }
        }

        $pending->up;
        ++$received;

        if ($received % $conc == 0) {
            my $taken = $end_time - $start_time;
            my $avg   = $taken / $received;
            LOG(' - %4d of %4d complete in %fs (avg %fs/task)', $received, $total, $taken, $avg);
        }
    };

    push @pending, $coro;
    cede;
}

foreach my $pending (@pending) {
    $pending->join;
}

my $taken = time - $start_time;
my $avg   = $taken / $received;
LOG('--------------------------------------------------------------------------------');
LOG('%d tasks completed in %fs (avg %fs/task)', $received, $taken, $avg);
LOG('Savings / Overhead: %fs/task', ($avg - $delay));

exit 0;