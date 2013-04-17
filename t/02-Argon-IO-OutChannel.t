use strict;
use warnings;
use Carp;

use Coro::AnyEvent;
use Test::More qw/no_plan/;

require_ok('Argon::IO::OutChannel');
use_ok('Argon::IO::OutChannel');

{
    pipe(my $r, my $w) or BAIL_OUT($!);
    local $| = 1;
    my $msg  = "Hello world\n";
    my $len  = length $msg;

    # Test with chunk_size set to message length to allow sync io on the read
    # handle below.
    my $out = new_ok('Argon::IO::OutChannel' => [ handle => $w, chunk_size => $len ]);
    ok($out, 'instantiation');

    $out->send($msg);

    Coro::AnyEvent::readable $r;
    my $result = <$r>;
    ok($result eq $msg, "I/O test");
}