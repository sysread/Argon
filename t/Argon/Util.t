package TestClass;

sub foo {
  my $self = shift;
  return ['foo was called', @_];
};

1;

package main;
use Test2::Bundle::Extended;
use Test::Refcount;
use Scalar::Util qw(isweak);
use Argon::Util qw(K param interval);

subtest K => sub {
  my $obj = bless {}, 'TestClass';
  my $mtd = $obj->can('foo');
  my $one = 1;
  my $ref = \$one;

  is_oneref $obj, 'initial instance refcount is 1';
  is_refcount $mtd, 2, 'initial method refcount is 2';
  is_refcount $ref, 2, 'initial arg refcount is 2';

  ok my $cb = K('foo', $obj), 'call';
  is ref $cb, 'CODE', 'returns code ref';

  is_oneref $obj, 'no new instance refs';
  is_refcount $mtd, 2, 'no new method refs';
  is_refcount $ref, 2, 'no new arg refs';

  ok my $ret = $cb->($ref), 'callback';
  is $ret, ['foo was called', $ref], 'expected return values';
  undef $ret;

  is_oneref $obj, 'no new instance refs';
  is_refcount $mtd, 2, 'no new method refs';
  is_refcount $ref, 2, 'no new arg refs';
};

subtest param => sub {
  my %args = (foo => 'bar');
  is param('foo', %args), 'bar', 'key exists';
  is param('bar', %args, 'baz'), 'baz', 'key does not exist, default provided';
  is param('bar', %args, undef), U(), 'key does not exist, undef provided as default';
  dies { param('bar', %args) }, 'dies if key not specified and no default provided';
};

subtest interval => sub {
  my $n = 2;

  ok my $i = interval($n), 'initialize';
  is $i->(), ($n + log($n)), 'call 1';
  is $i->(), ($n + log($n * 2)), 'call 2';
  is $i->(), ($n + log($n * 3)), 'call 3';
  is $i->(), ($n + log($n * 4)), 'call 4';

  is $i->(1), U(), 'reset';
  is $i->(), ($n + log($n)), 'call 1';
  is $i->(), ($n + log($n * 2)), 'call 2';
};

done_testing;
