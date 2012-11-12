use strict;
use warnings;
use Carp;
use Getopt::Std;
use EV;

require Argon::Server;
require Argon::Cluster;

my %opt;
getopt('p', \%opt);

my $port    = $opt{p} || 8000;
my $server  = Argon::Server->new(port => $port);
my $cluster = Argon::Cluster->new(server => $server);

$server->start;
EV::run;