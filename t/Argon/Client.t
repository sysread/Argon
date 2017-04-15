use Test2::Bundle::Extended;
use Argon::Test;
use Argon::Constants qw(:commands);
use Argon::Message;
use Argon::Client;

sub client {
  my ($left, $right) = channel_pair();
  ok my $client = Argon::Client->new(
    host    => 'localhost',
    port    => 4242,
    channel => $left,
    @_,
  ), 'client';

  return ($client, $right);
}

subtest 'callbacks' => sub {
  ar_test 'positive path' => sub {
    my $cv = shift;
    my ($opened, $ready, $closed, $failed, $notify) = @_;

    my ($client, $channel); ($client, $channel) = client(
      opened => sub { $opened = 1 },
      ready  => sub { $ready  = 1 },
      failed => sub { $failed = 1 },
      closed => sub { $closed = 1; $cv->send; },
      notify => sub { $notify = 1; $channel->disconnect; },
    );

    $channel->send(Argon::Message->new(cmd => $PING));
    $cv->recv;

    ok  $opened, 'opened';
    ok  $ready,  'ready';
    ok  $notify, 'notify';
    ok  $closed, 'closed';
    ok !$failed, '!failed';
  };

  ar_test 'failed' => sub {
    my $cv = shift;
    my $client = Argon::Client->new(host => 'notarealhost', port => 0, failed => sub { $cv->send('failed') });
    is $cv->recv, 'failed', 'failed callback triggered';
  };
};

ar_test 'send/recv' => sub {
  my $cv = shift;

  my ($client, $channel) = client(notify => $cv);

  my $request;

  $channel->on_msg(sub {
    $request = shift;
    $channel->send($request->reply(info => 'response content'));
  });

  my $msg = Argon::Message->new(cmd => $PING, info => 'request content');

  $client->send($msg);

  ok my $reply = $cv->recv, 'reply received';
  is $request, $msg, 'msg sent was msg received';
  is $reply->info, 'response content', 'expected msg contents';
};

done_testing;
