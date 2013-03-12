#!/bin/env perl

use strict;
use warnings;
use Carp;

use EV;
use Argon::Cluster;
use Argon qw/:commands/;

use Getopt::Long;

# Default values
my $port        = 8888;
my $queue_limit = 50;
my $queue_check = 2;

GetOptions(
    'port=i'        => \$port,
    'queue_limit=i' => \$queue_limit,
    'check=i'       => \$queue_check,
);

my $node = Argon::Cluster->new(
    port        => $port,
    queue_limit => $queue_limit,
    queue_check => $queue_check,
);

$node->start;

EV::run();

exit 0;