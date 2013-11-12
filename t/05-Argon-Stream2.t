use strict;
use warnings;
use Carp;
use Test::More;
use List::Util qw(shuffle);
use AnyEvent::Util;
use Argon::Message;
use Argon qw(:logging :commands);

$Argon::DEBUG = $Argon::DEBUG | Argon::DEBUG_DEBUG;


BEGIN { use AnyEvent::Impl::Perl }


my $class = 'Argon::Stream2';
use_ok($class);

{
    my $count = 100;

    my ($fh1, $fh2) = AnyEvent::Util::portable_socketpair
        or BAIL_OUT($!);

    # Create callback to collect messages
    my %cv;
    my $on_message = sub {
        my $msg = shift;
        my $id  = $msg->id;
        $cv{$id} // BAIL_OUT "test bug - msg id has no cv ($id)";
        $cv{$id}->send($msg);
    };

    my $closed_cv = AnyEvent->condvar;
    my $is_closed = 0;
    my $closed_cb = sub { $is_closed = 1; $closed_cv->send };

    my $left = $class->create($fh1, on_message => $on_message, on_close => $closed_cb);
    isa_ok($left, $class, "isa $class") or BAIL_OUT;

    my $right = $class->create($fh2, on_message => $on_message, on_close => $closed_cb);
    isa_ok($right, $class, "isa $class") or BAIL_OUT;

    my %id;
    foreach my $i (shuffle(1 .. $count)) {
        my $msg = Argon::Message->new(command => CMD_QUEUE);
        $msg->set_payload("MSG $i");
        my $id = $msg->id;
        $cv{$id} = AnyEvent->condvar;
        $left->write($msg);
        $id{$i} = $msg->id;
    }

    foreach my $i (shuffle keys %id) {
        my $id  = $id{$i};
        my $msg = $cv{$id}->recv;
        ok(defined $msg, "received msg ($i)");
        is($msg->id, $id, "received id correct ($i)");
        is($msg->get_payload, "MSG $i", "receive msg payload is correct ($i)");
    }

    $right->close;
    $closed_cv->recv;
    ok($is_closed, 'closing right triggers close on left');
}

done_testing;
