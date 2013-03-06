#!/bin/env perl

use strict;
use warnings;
use Carp;

use EV;
use Argon::Cluster;
use Argon qw/:commands/;

use Getopt::Long;

# Default values
my $port    = 8888;
my $workers = 4;

GetOptions(
    'port=i' => \$port,
);

my $node = Argon::Cluster->new(
    port => $port,
);

$node->start;

EV::run();

exit 0;