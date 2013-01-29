use strict;
use warnings;
use Carp;
use Getopt::Std;
use EV;

require Argon::Cluster;

my %opt;
getopt('p', \%opt);

my $port    = $opt{p} || 8000;
my $cluster = Argon::Cluster->new(port => $port);

$cluster->start;
EV::run;
