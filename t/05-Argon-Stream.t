use strict;
use warnings;
use Carp;

use Test::More;

use Coro;
use AnyEvent::Util;
use Coro::Handle;
use Argon::Message;
use Argon qw/:logging :commands/;

use_ok('Argon::Stream');

# Positive path
{
    my ($fh1, $fh2) = AnyEvent::Util::portable_socketpair
        or BAIL_OUT($!);

    $fh1 = unblock $fh1;
    $fh2 = unblock $fh2;

    # Object creation
    my $left = new_ok('Argon::Stream', [
        in_chan  => $fh1,
        out_chan => $fh1,
    ]) or BAIL_OUT('unable to continue without stream object');

    my $right = Argon::Stream->create($fh2);
    ok(defined $right && $right->isa('Argon::Stream'), 'create')
        or BAIL_OUT('unable to continue without stream object');

    # send_message -> receive
    my $msg = Argon::Message->new(command => CMD_QUEUE);
    $msg->set_payload(42);

    $left->send_message($msg);
    my $reply = $right->receive;
    ok(defined $reply && $reply->get_payload eq 42, 'send_messge -> receive');

    # send
    my @threads;

    push @threads, async {
        $msg = Argon::Message->new(command => CMD_QUEUE);
        $msg->set_payload('What is the meaning of life, the universe and everything?');

        my $reply = $left->send($msg);
        ok($reply->command == CMD_COMPLETE, 'send (1) - cmd');
        ok($reply->get_payload eq 42, 'send (2) - payload');
    };

    push @threads, async {
        my $msg = $right->receive;
        my $reply = $msg->reply(CMD_COMPLETE);
        $reply->set_payload(42);
        $right->send_message($reply);
    };

    $_->join foreach @threads;

    # monitor
    my $flag = 0;
    my $monitor = $right->monitor(sub { $flag = 1 });
    $left->close;
    $monitor->join;

    ok($flag, 'monitor');

    # clean up
    $right->close;
}

done_testing;
