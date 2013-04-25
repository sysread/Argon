package TestProcessClass;

use strict;
use warnings;
use Carp;

use IO::Handle;
use Coro::Handle qw/unblock/;
use Argon qw/:commands :logging/;
use Argon::Stream;

sub new {
    my ($class, @args) = @_;
    return bless [@args], $class;
}

sub run {
    my $self = shift;
    local $| = 1;

    my $in  = IO::Handle->new;
    my $out = IO::Handle->new;

    $in->fdopen(fileno(STDIN),   'r');
    $out->fdopen(fileno(STDOUT), 'w');

    my $stream = Argon::Stream->create(
        in_fh  => unblock($in),
        out_fh => unblock($out),
    );

    while (1) {
        my $msg = $stream->receive;
        my $pay = $msg->get_payload;
        INFO 'Input: %s', $pay;

        if ($pay eq 'EXIT') {
            INFO 'Shutting down';
            my $reply = $msg->reply(CMD_ACK);
            $stream->send($reply);
            last;
        } else {
            my $reply = $msg->reply(CMD_ACK);
            $reply->set_payload(sprintf('You said "%s"', $pay));
            $stream->send($reply);
        }
    }

    exit 0;
}

1;