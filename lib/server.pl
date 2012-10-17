use strict;
use warnings;
use Argon::Server;

my $server = Argon::Server->new(
    port     => 8889,
    host     => '127.0.0.1',
    endline  => "\015\012",
    on_error => sub {
        my ($error, $message) = @_;
        warn $error;
    }
);

$server->respond_to(1, sub {
    my $message = shift;
    my $input = $message->payload;
    $message->payload(uc $input);
    return $message;
});

$server->start;