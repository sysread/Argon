use strict;
use warnings;
use Carp;
use EV;
use Getopt::Std;

# For strict parameter checking on all calls to AnyEvent
$ENV{PERL_ANYEVENT_STRICT} = 1;

require Argon::Node;

my %opt;
getopt('pcmr', \%opt);

my $port   = $opt{p} || 8888;
my $conc   = $opt{c} || 4;
my $reqs   = $opt{r} || 0;
my $queue  = 8 * $conc;
my $node   = Argon::Node->new(
    port         => $port,
    host         => '127.0.0.1',
    concurrency  => $conc,
    queue_limit  => $queue,
    max_requests => $reqs,
);

if ($opt{m}) {
    $node->add_manager(split ':', $opt{m});
}

$node->start;
EV::run;
