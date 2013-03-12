#!/bin/env perl

use strict;
use warnings;
use Carp;

use EV;
use Argon::Node;
use Argon qw/:commands/;

use Getopt::Long;

# Default values
my $port        = 8888;
my $workers     = 4;
my $queue_limit = $workers * 2;
my $queue_check = 2;
my $manager;
my $max_reqs;

GetOptions(
    'port=i'        => \$port,
    'workers=i'     => \$workers,
    'manager=s'     => \$manager,
    'requests=i'    => \$max_reqs,
    'queue_limit=i' => \$queue_limit,
    'queue_check=i' => \$queue_check,
);

my %param = (
    concurrency => $workers,
    port        => $port,
    queue_limit => $queue_limit,
    queue_check => $queue_check,
);

$param{max_requests} = $max_reqs if $max_reqs;
$param{manager}      = $manager  if $manager;

my $node = Argon::Node->new(%param);

$node->start;

EV::run();

exit 0;