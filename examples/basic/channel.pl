use strict;
use warnings;
use Carp;
use Data::Dumper;
use EV;
use AnyEvent;
use Getopt::Std;
use Test::LeakTrace;
use Argon qw/LOG :commands/;

require Argon::Channel;
require Argon::Message;
require SampleJob;

my %opt;
getopt('hpns', \%opt);

my $total = $opt{n} || 10;
my $host  = $opt{h} || 'localhost';
my $port  = $opt{p} || 8888;
my $sleep = defined $opt{s} ? $opt{s} : 0.1;

my $count = 0;
my $report_every = $total >= 10 ? ($total / 10) : 10;

sub on_complete {
    my $msg = shift;

    ++$count;

    if ($count % $report_every == 0) {
        LOG('%d of %d tasks complete', $count, $total);
    }

    if ($count == $total) {
        LOG('All results are in. Bye!');
        EV::break;
    }
}

sub send_tasks {
    my $chan = shift;
    foreach my $i (1 .. $total) {
        $chan->process(
            class => 'SampleJob',
            args  => [value => $i, sleep_for => $sleep],
        );
    }}

my $chan = Argon::Channel->new();
$chan->connect(host => $host, port => $port);
$chan->on_complete(\&on_complete);
$chan->add_connect_callbacks(\&send_tasks);

EV::run;
exit 0;