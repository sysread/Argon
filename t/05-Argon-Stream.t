use strict;
use warnings;
use Carp;

use Test::More tests => 7;

use Coro;
use AnyEvent::Util;
use Coro::Handle;
use Argon::Message;
use Argon qw/:commands/;

use_ok('Argon::Stream');

# Positive path
{
    my ($fh1, $fh2) = AnyEvent::Util::portable_socketpair;
    $fh1 = unblock $fh1;
    $fh2 = unblock $fh2;

    # Object creation
    my $left = new_ok('Argon::Stream', [
        in_chan  => $fh1,
        out_chan => $fh1,
    ]);

    my $right = Argon::Stream->create($fh2);
    ok(defined $right && $right->isa('Argon::Stream'), 'create');

    # send_message -> receive
    my $msg = Argon::Message->new(command => CMD_QUEUE);
    $msg->set_payload(42);

    $left->send_message($msg);
    my $reply = $right->receive;
    ok(defined $reply, 'receive message');
    ok($reply->get_payload eq 42, 'send_messge -> receive');

    # send
    async {
        $msg = Argon::Message->new(command => CMD_QUEUE);
        $msg->set_payload('What is the meaning of life, the universe and everything?');

        my $reply = $left->send($msg);
        ok($reply->get_payload eq 42);
    };

    async {
        my $msg = $right->receive;
        $msg->set_payload(42);
        $right->send_message($msg);
    };

    cede;

    # Monitoring
    my $flag = 0;

    $left->monitor(sub { $flag = 1 });
    Coro::AnyEvent::sleep($Argon::POLL_INTERVAL);

    $fh2->close;
    Coro::AnyEvent::sleep($Argon::POLL_INTERVAL);
    ok($flag, 'monitor');
}