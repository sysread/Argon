use strict;
use warnings;
use Carp;
use EV;
use Getopt::Std;
use Argon qw/:commands LOG/;

require Argon::Pool;
require Argon::Message;

my %opt;
getopt('cnwr', \%opt);

my $conc  = $opt{c} || 4;
my $count = $opt{n} || 512;
my $wait  = $opt{w} || 0;
my $reqs  = $opt{r} || 8;
my $pool  = Argon::Pool->new('concurrency' => $conc, max_requests => $reqs);

foreach my $i (1 .. $count) {
    my $msg = Argon::Message->new(command => CMD_QUEUE);
    $msg->set_payload(['SampleJob', [value => $i, sleep_for => $wait]]);

    $pool->assign($msg, sub {
        my $response = shift;
        my $result   = $response->get_payload;
        LOG('%d * 2 = %d', $i, $result);

        if (--$count == 0) {
            LOG('Done!'), EV::break;
        }
    })
}

EV::run;
