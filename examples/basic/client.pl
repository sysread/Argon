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
getopt('hp', \%opt);

my $client = Argon::Client->new(
    host => $opt{h},
    port => $opt{p},
);

$client->connect(sub {
    warn "Connected!\n";
    
    foreach my $i (1 .. 10) {
        $client->process('SampleJob', [$i],
            class      => 'SampleJob',
            args       => [10],
            on_error   => sub { my $reply = shift; LOG('ERROR (%d): [%s]', $i, $reply); },
            on_success => sub { LOG('COMPLETE (%d): [%s]', $i, shift); },
        );
    }
});

EV::run;