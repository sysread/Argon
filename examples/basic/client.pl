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
    my $msg = Argon::Message->new(command => CMD_QUEUE);
    $msg->set_payload(['SampleJob', [10]]);
    $client->send($msg, sub {
        my ($client, $response) = @_;
        LOG(Dumper($response));
    });
});

EV::run;