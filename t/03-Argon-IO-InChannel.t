use strict;
use warnings;
use Carp;

use Coro::AnyEvent;
use Test::More qw/no_plan/;

require_ok('Argon::IO::InChannel');
use_ok('Argon::IO::InChannel');

# Positive path
{
    pipe(my $r, my $w) or BAIL_OUT($!);
    my $msg  = "Hello world\n";
    my $len  = length $msg;
    my $in   = new_ok('Argon::IO::InChannel' => [ handle => $r ]);
    
    # Send data to pipe
    syswrite($w, $msg);
    
    # Read data from pipe
    my $result = $in->receive(TO => "\n");
    ok($result eq $msg, 'I/O test');
}

# Disconnect
{
    pipe(my $r, my $w) or BAIL_OUT($!);
    my $msg  = "Hello world\n";
    my $len  = length $msg;
    my $in   = Argon::IO::InChannel->new(handle => $r);
    
    # Send data to pipe
    syswrite($w, $msg);
    close $w;
    
    # Second read should trigger an error
    my $result  = $in->receive(TO => "\n");
    my $failure = $in->receive(TO => "\n");
    ok(!defined $failure, 'I/O disconnect - read result');
    ok($in->state->curr_state->name eq 'DONE', 'I/O disconnect - state');
}