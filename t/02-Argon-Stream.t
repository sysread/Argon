use strict;
use warnings;
use Test::More;
use AnyEvent::Util;
use Coro::Handle;
use Argon qw(:commands);
use Argon::Message;

BEGIN { use AnyEvent::Impl::Perl }

use_ok('Argon::Stream');

{
    my ($l, $r) = AnyEvent::Util::portable_socketpair;
    my $left  = new_ok('Argon::Stream', [handle => unblock($l), address => 'left']);
    my $right = new_ok('Argon::Stream', [handle => unblock($r), address => 'right']);

    foreach my $i (1 .. 10) {
        my $msg = Argon::Message->new(cmd => $CMD_PING, origin => 'test');
        $left->write($msg);
        my $recv = $right->read;
        is_deeply($msg, $recv, "write -> read ($i)");
    }
}

done_testing;
