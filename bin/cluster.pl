#!/bin/env perl

use strict;
use warnings;
use Carp;

use Getopt::Long;
use Pod::Usage;
use Argon::Cluster;

# Default values
my $help  = 0;
my $limit = 64;
my $check = 2;
my $port;

my $got_options = GetOptions(
    'help'    => \$help,
    'limit=i' => \$limit,
    'check=i' => \$check,
    'port=i'  => \$port,
);

if (!$got_options || $help || !$port) {
    pod2usage(2);
    exit 0;
}

my $node = Argon::Cluster->new(
    port        => $port,
    queue_limit => $limit,
    queue_check => $check,
);

$node->start;

EV::run();

exit 0;
__END__

=head1 NAME

cluster.pl - runs an Argon cluster

=head1 SYNOPSIS

cluster.pl -p 8888 [-q 50] [-c 2]
sample [options] [file ...]

 Options:
   -[p]ort          port on which to listen
   -[l]limit        max number of items permitted to queue up (default 64)
   -[c]heck         number of seconds between queue reprioritization checks
                    (default 2)
   -[h]elp          prints this help message

=head1 DESCRIPTION

B<cluster.pl> runs an Argon cluster on the selected port.

=cut