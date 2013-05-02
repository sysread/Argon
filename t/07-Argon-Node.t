use strict;
use warnings;
use Carp;

use Test::More qw/no_plan/;

use Coro;
use Coro::AnyEvent;
use Argon::Stream;

unshift @INC, 't';

use_ok('Argon::Node')           or BAIL_OUT('unable to load Argon::Node');
require_ok('Test::DoublerTask') or BAIL_OUT('unable to load task class');