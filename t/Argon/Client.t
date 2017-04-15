use Test2::Bundle::Extended;
use Argon::Test;
use Argon::Constants qw(:commands);
use Argon::Message;
use Argon::Client;

sub client {
  my ($left, $right) = channel_pair();
  my $client = Argon::Client->new(
    host    => 'localhost',
    port    => 4242,
    channel => $left,
  );

  return ($client, $right);
}

ar_test 'send/recv' => sub {
  my $cv = shift;

  my ($client, $channel) = client();

  my $request;

  $channel->on_msg(sub {
    $request = shift;
    $channel->send($request->reply(info => 'response content'));
  });

  $client->notify($cv);

  my $msg = Argon::Message->new(cmd => $PING, info => 'request content');

  $client->send($msg);

  ok my $reply = $cv->recv, 'reply received';
  is $request, $msg, 'msg sent was msg received';
  is $reply->info, 'response content', 'expected msg contents';
};

done_testing;
