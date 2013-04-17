package TestProcessClass;

use strict;
use warnings;
use Carp;

use IO::Handle;
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

    my $stream = Argon::Stream->new(in_fh  => $in, out_fh => $out);
    
    while (1) {
        my $msg = $stream->next_message;
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