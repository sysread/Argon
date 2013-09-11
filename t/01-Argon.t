use strict;
use warnings;
use Carp;

use Test::More;
use Test::Refcount;
use IO::Capture::Stderr;

# Import
{
    require_ok('Argon');
    use_ok('Argon');
    use_ok('Argon', qw/:priorities/);
    use_ok('Argon', qw/:commands/);
    use_ok('Argon', qw/:logging/);
}

# K()
{
    package Foo;
    sub new { bless {}, $_[0] }
    sub bar { }

    package main;
    use Argon;

    my $obj = Foo->new();
    my $cb  = K('bar', $obj);

    ok(ref $cb eq 'CODE', 'K() creates CODE ref');
    is_oneref($cb, 'K() weakens object reference');

    eval { K('invalid', $obj) };
    ok($@, 'K() croaks on invalid method');

    eval { K('invalid', 'not an object') };
    ok($@, 'K() croaks on invalid object');
}

# error()
{
    use Argon;
    eval { croak 'foo' };
    my $error = Argon::error($@);
    ok($error eq 'foo', 'error() strips line numbers');
}

# LOG() | INFO() | WARN() | ERROR()
{
    use Argon qw/:logging/;

    my $prefix = qr/\[\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\] \[\d+\]/;

    my $capture = IO::Capture::Stderr->new();
    $capture->start;

    INFO('info');
    WARN('warn');
    ERROR('error');
    Argon::LOG('info 2');

    $capture->stop;

    ok($capture->read =~ /^$prefix info$/,  'INFO()');
    ok($capture->read =~ /^$prefix warn$/,  'WARN()');
    ok($capture->read =~ /^$prefix error$/, 'ERROR()');
    ok($capture->read =~ /^$prefix info 2$/, 'ERROR()');
}

done_testing;
