use strict;
use warnings;
use Carp;
use EV;
use Getopt::Std;

require Argon::Server;
require Argon::Node;

my %opt;
getopt('pc', \%opt);

my $port   = $opt{p} || 8888;
my $server = Argon::Server->new(port => $port, host => '127.0.0.1');
my $node   = Argon::Node->new(
    server      => $server,
    concurrency => 2,
    queue_limit => 100,
);

if ($opt{c}) {
    $node->add_manager(split ':', $opt{c});
}

$server->start;
$node->initialize;
EV::run;