use strict;
use warnings;
use Carp;
use EV;
use Getopt::Std;

require Argon::Server;
require Argon::Node;

my %opt;
getopt('pcm', \%opt);

my $port   = $opt{p} || 8888;
my $conc   = $opt{c} || 4;
my $queue  = 4 * $conc;
my $server = Argon::Server->new(port => $port, host => '127.0.0.1');
my $node   = Argon::Node->new(
    server      => $server,
    concurrency => $conc,
    queue_limit => $queue,
);

if ($opt{m}) {
    $node->add_manager(split ':', $opt{m});
}

$server->start;
$node->initialize;
EV::run;