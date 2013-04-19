#!/usr/bin/env perl

use strict;
use warnings;
use Carp;

use EV;
use Coro;
use Getopt::Long;
use Pod::Usage;
use Time::HiRes qw/time/;
use Argon       qw/:commands :logging/;
use Argon::Client;

# Default values
my $address;
my $total    = 1000;
my $conc     = 4;
my $delay    = 0.05;
my $variance = 0;
my $help;

my $got_options = GetOptions(
    'address=s'     => \$address,
    'number=i'      => \$total,
    'concurrency=i' => \$conc,
    'delay=f'       => \$delay,
    'variance=f'    => \$variance,
    'help'          => \$help,
);

if (!$got_options || $help || !$address) {
    pod2usage(2);
    exit 1 if !$got_options || !$address;
    exit 0;
}

# Process address name
my ($host, $port) = split ':', $address;
unless (defined $host && defined $port) {
    warn "Invalid address. Please specify host:port.\n";
    pod2usage(2);
    exit 1;
}

# If the delay is 0, use the variance to calculate an average such that the
# delay ought not fall below zero.
if ($delay == 0 && $variance != 0) {
    INFO 'Warning: recalculated delay and variance to prevent negative delays.';
    $delay    = $variance / 2;
    $variance = $variance / 2;
}
# If the variance could cause the delay to be less than zero, use the variance
# to calculate the effective avg delay.
elsif ($delay < $variance) {
    INFO 'Warning: recalculated delay and variance to prevent negative delays.';
    my $difference = $variance - $delay;
    $delay    += $difference;
    $variance -= $difference;
}

INFO 'Benchmark plan:';
INFO 'Host: %s:%d', $host, $port;
INFO 'Will send %d tasks over %d concurrent connections', $total, $conc;
INFO 'Simulated task will average %0.4fs (+/-%0.4fs) to complete.', $delay, $variance;
INFO '--------------------------------------------------------------------------------';

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

while (my $task = shift @tasks) {
    my $client = $clients->get;

    push @threads, async {
        my $result = $client->process(
            class  => 'SampleTask',
            params => $task,
        );

        my $finish = time;
        $clients->put($client);

        if ($result->command == CMD_ERROR) {
            ERROR 'Error: %s', $result->get_payload;
            push @tasks, $task;
        } else {
            ++$complete;

            if ($complete % $report_every == 0) {
                my $taken = $finish - $start_time;
                my $avg   = $taken / $complete;
                INFO $format, $complete, $total, $taken, $avg;
            }
        }
    }
}

# Wait for all threads to complete
$_->join foreach @threads;

# Output summary
my $taken = time - $start_time;
my $avg   = $taken / $complete;
INFO '--------------------------------------------------------------------------------';
INFO $format, $complete, $total, $taken, $avg;
INFO 'Savings / Overhead: %0.4fs/task', ($avg - $delay);

exit 0;
__END__

=head1 NAME

bench.pl - runs a benchmark against a node or cluster

=head1 SYNOPSIS

bench.pl -p 8888 [-i somehost] [-n 2000] [-c 8] [-d 0.5] [-v 0.25]

 Options:
   -[p]ort          port to which the client should connect
   -[a]ddress       host to which the client should connect
   -[n]umber        total number of messages to send
   -[c]oncurrency   number of concurrent connections to use
   -[d]elay         the amount of time to simulate each task taking
   -[v]ariance      introduces variation in simulated task time (delay)
   -[h]elp          prints this help message

=head1 DESCRIPTION

B<bench.pl> runs a stress test against an Argon node or cluster.

=head1 OPTIONS

=over 8

=item B<-[h]elp>

Print a brief help message and exits.

=item B<-[p]ort>

The port to which the client connects.

=item B<-[a]ddress>

The hostname to which the client connects.

=item B<-[n]umber>

The total number of requests to send.

=item B<-[c]oncurrency>

The number of independent connections to the service to establish. Tasks will
be split up among the connections for best throughput.

=item B<-[d]elay>

Sets the number of seconds the dummy task will sleep in order to simulate a
task of fixed processing time.

=item B<-[v]ariance>

Setting this to a fractional value of seconds causes variation of up to that
value in the delay used by the dummy task.

=back

=cut
