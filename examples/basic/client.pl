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
getopt('hpns', \%opt);

my $total = $opt{n} || 10;
my $host  = $opt{h} || 'localhost';
my $port  = $opt{p} || 8888;
my $sleep = $opt{s} || 0.1;

my $client = Argon::Client->new(
    host => $host,
    port => $port,
);

my $count = 0;

sub inc {
    if (++$count == $total) {
        LOG('All results are in. Bye!');
        exit 0;
    }   
}

sub on_complete {
    my $num = shift;
    return sub {
        LOG('COMPLETE (%4d): %4d', $num, shift);
        inc;
    }
}

sub on_error {
    my $num = shift;
    return sub {
        LOG('ERROR (%4d): %s', $num, shift);
        inc;
    }
}

$client->connect(sub {
    warn "Connected!\n";
    foreach my $i (1 .. $total) {
        $client->process(
            class      => 'SampleJob',
            args       => [$i, $sleep],
            on_success => on_complete($i),
            on_error   => on_error($i),
        );
    }
});

EV::run;
