use strict;
use warnings;
use Carp;

use Test::More tests => 7;
use Argon      qw/:logging/;

require_ok('Argon::Process');
use_ok('Argon::Process');

my $proc = Argon::Process->new(
    class => 'TestProcessClass',
    args  => [1,2,3],
    inc   => [],
);

ok($proc->spawn, 'process spawns');
ok(!$!, 'process spawns without error') or die $!;
ok(!$?, 'process does not immediately quit');

$proc->send('Hello');
ok($proc->recv eq 'You said "Hello"', 'ipc in/out functions');
ok($proc->recv_err eq 'Warning: you said "Hello"', 'ipc err functions');