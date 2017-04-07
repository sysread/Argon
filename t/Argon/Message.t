use Test2::Bundle::Extended;
use Argon::Constants qw(:commands :priorities);
use Argon::Message;

subtest 'tokens' => sub {
  ok my $msg = Argon::Message->new(cmd => $PING, token => 'test-token');
  isnt $msg->error('foo')->token, $msg->token, 'error drops existing token';
  isnt $msg->reply->token, $msg->token, 'reply drops existing token';
  is $msg->reply(token => 'different-token')->token, 'different-token', 'reply allows setting token';
};

done_testing;
