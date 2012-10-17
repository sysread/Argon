#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Argon' ) || print "Bail out!\n";
}

diag( "Testing Argon $Argon::VERSION, Perl $], $^X" );
