use strict;
use warnings;
use Carp;

use Test::More;

use AnyEvent;
use Coro;
use Coro::AnyEvent;
use Argon qw/:commands/;
use Argon::Message;

BEGIN { use AnyEvent::Impl::Perl }


unshift @INC, 't';

use_ok('Argon::Server') or BAIL_OUT('unable to load Argon::Server');
require_ok('Test::DoublerTask') or BAIL_OUT('unable to load task class');

my $s = new_ok('Argon::Server', [ queue_limit  => 10 ]);
$s->listener; # force builder to run

ok(defined $s->port, 'sets port on build');
ok(defined $s->host, 'sets host on build');

my $dispatcher_hit;
$s->respond_to(CMD_PING, sub {
    $dispatcher_hit = 1;
    my $req = shift;
    return $req->reply(CMD_ACK);
});

my $msg = Argon::Message->new(command => CMD_PING);

done_testing;
