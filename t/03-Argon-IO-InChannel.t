use strict;
use warnings;
use Carp;

use Coro::AnyEvent;
use AnyEvent::Util qw/portable_socketpair fh_nonblocking/;
use Test::More     qw/no_plan/;
use Argon          qw//;

require_ok('Argon::IO::InChannel');
use_ok('Argon::IO::InChannel');

{
    my ($r, $w) = portable_socketpair or BAIL_OUT($!);
    fh_nonblocking $r, 1;
    fh_nonblocking $w, 1;

    my @msgs = ("Hello world", "Thanks for all the fish", "How now brown bureaucrat");
    my $in   = new_ok('Argon::IO::InChannel' => [ handle => $r ]);

    # Send data to pipe
    syswrite($w, $_ . $Argon::EOL) foreach @msgs;

    # Read data from pipe
    foreach my $msg (@msgs) {
        my $result = $in->receive;
        ok($result eq $msg, "I/O test: $msg");
    }

    # Close other side of the connection
    $w->close;

    my $failure = $in->receive;
    ok(!defined $failure, 'I/O disconnect - read result');
    ok($in->state->curr_state->name eq 'DONE', 'I/O disconnect - state');   
}