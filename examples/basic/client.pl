use strict;
use warnings;
use Carp;
use Data::Dumper;
use EV;
use AnyEvent;
use Argon qw/LOG :commands/;

require Argon::Client;
require Argon::Message;
require SampleJob;

my $client = Argon::Client->new(
    host => 'localhost',
    port => 8888,
);

$client->connect(sub {
    warn "Connected!\n";
    
    $client->process('SampleJob', [10],
        class      => 'SampleJob',
        args       => [10],
        on_error   => sub { LOG('ERROR: [%s]',    shift), exit 0; },
        on_success => sub { LOG('COMPLETE: [%s]', shift), exit 0; },
    );
});

EV::run;