use strict;
use warnings;
use Carp;
use Argon::Client;
use Argon qw/:priorities/;

my $client = Argon::Client->new(host => 'localhost', port => 8889);

$client->on_error(sub {
    my ($error, $cmd, $id, $msg) = @_;
    warn $error;
});

$client->on_connect(sub {
    my $client = shift;
    
    my $message = Argon::Message->new(command => 1);
    $message->payload('hello world');
    
    $client->send($message, sub {
        my $response = shift;        
        my $data = $response->payload;
        warn "RESPONSE: $data\n";
        $client->stop;
    });
});

$client->start;

exit 0;