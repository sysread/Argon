use strict;
use warnings;
use Carp;
use Data::Dumper;
use EV;
use AnyEvent;
use Getopt::Std;
use Argon qw/LOG :commands/;

require Argon::Client;
require Argon::Message;
require SampleJob;

my %opt;
getopt('hpc', \%opt);

my $client = Argon::Client->new(
    host => $opt{h},
    port => $opt{p},
);

my $count = 0;
my $total = $opt{c} || 10;
sub on_complete {
    my $num = shift;
    return sub {
        my $result = shift;
        LOG('COMPLETE (%d): %s', $num, $result);
        
        if (++$count == $total) {
            LOG('All results are in. Bye!');
            exit 0;
        }
    }
}

$client->connect(sub {
    warn "Connected!\n";
    foreach my $i (1 .. $total) {
        $client->process(
            class      => 'SampleJob',
            args       => [$i],
            on_success => on_complete($i),
            on_error   => on_complete($i),
        );
    }
});

EV::run;