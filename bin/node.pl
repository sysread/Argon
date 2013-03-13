#!/usr/bin/env perl

use strict;
use warnings;
use Carp;

use Argon qw/:commands/;
use Argon::Node;
use Getopt::Long;
use Pod::Usage;

# Default values
my $port;
my $workers = 4;
my $limit;
my $check   = 2;
my $manager;
my $max_reqs;
my $help;

my $got_options = GetOptions(
    'port=i'     => \$port,
    'workers=i'  => \$workers,
    'manager=s'  => \$manager,
    'requests=i' => \$max_reqs,
    'limit=i'    => \$limit,
    'check=i'    => \$check,
    'help'       => \$help,
);

if (!$got_options || $help || !$port) {
    pod2usage(2);
    exit 1 if !$got_options || !$port;
    exit 0;
}

my %param = (
    concurrency => $workers,
    port        => $port,
    limit => $limit,
    check => $check,
);

$param{max_requests} = $max_reqs if $max_reqs;
$param{manager}      = $manager  if $manager;

my $node = Argon::Node->new(%param);

$node->start;

EV::run();

exit 0;
__END__

=head1 NAME

node.pl - runs an Argon worker node

=head1 SYNOPSIS

node.pl -p 8888 [-m somehost:8000] [-w 4] [-r 1000] [-q 50] [-c 2]

 Options:
   -[p]ort          port on which to listen
   -[w]orkers       number of worker processes to maintain (default 4)
   -[r]equests      max requests before restarting worker (optional; default -)
   -[m]anager       host:port of manager (optional; default none)
   -[l]limit        max items permitted to queue (optional; default 64)
   -[c]heck         seconds before queue reprioritization (optional; default 2)
   -[h]elp          prints this help message

=head1 DESCRIPTION

B<node.pl> runs an Argon node on the selected port.

=head1 OPTIONS

=over 8

=item B<-[h]elp>

Print a brief help message and exits.

=item B<-[p]ort>

The port on which the cluster listens.

=item B<-[w]orkers>

The number of worker processes to maintain.

=item B<-[r]equests>

The maximum number of requests a worker may handle before it is restarted by
the node.

=item B<-[m]manager>

The host:port of the manager process. By default, none is set, and the node
accepts requests independently of the manager.

=item B<-[l]imit>

Sets the maximum number of messages which may build up in the queue before new
tasks are rejected. Optional; default value 64.

=item B<-[c]heck>

Starvation in the queue is prevented by increasing messages' priority after they
have spent a certain amount of time in the queue. Setting -check configures how
long this time period is. Optional; default value 2 (seconds).

=back

=cut