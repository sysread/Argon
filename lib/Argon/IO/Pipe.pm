#-------------------------------------------------------------------------------
# 
#-------------------------------------------------------------------------------
package Argon::IO::Pipe;

use strict;
use warnings;
use Carp;

use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

use Coro           qw//;
use Coro::AnyEvent qw//;
use AnyEvent::Util qw//;
use IO::Socket     qw/SOCK_STREAM/;

use Argon qw/:logging :commands/;
use Argon::Message;
use Argon::IO::InChannel;
use Argon::IO::OutChannel;

has 'in' => (
    is       => 'ro',
    isa      => 'Argon::IO::InChannel',
    required => 1,
);

has 'out' => (
    is       => 'ro',
    isa      => 'Argon::IO::OutChannel',
    required => 1,
);

#-------------------------------------------------------------------------------
# Class method: creates a new Pipe to a host:port.
#-------------------------------------------------------------------------------
sub connect {
    my ($class, %param) = @_;
    my $host = $param{host} || croak 'expected host';
    my $port = $param{port} || croak 'expected port';

    my $sock = IO::Socket::INET->new(
        PeerHost => $host,
        PeerPort => $port,
        Proto    => 'tcp',
        Type     => SOCK_STREAM,
    ) or croak $!;

    AnyEvent::Util::fh_nonblocking $sock, 1;

    Coro::AnyEvent::writable($sock);
    return $class->new(
        in  => Argon::IO::InChannel->new(handle => $sock),
        out => Argon::IO::OutChannel->new(handle => $sock),
    );
}

sub send_retry {
    my ($self, $msg) = @_;
    my $attempts = 0;

    while (1) {
        ++$attempts;
        $self->send($msg);
        my $reply = $self->receive;

        # If the task was rejected, sleep a short (but lengthening) amount of
        # time before attempting again.
        if ($reply->command == CMD_REJECTED) {
            my $sleep_time = log($attempts + 1) / log(10);
            Coro::AnyEvent::sleep($sleep_time);
        }
        else {
            return $reply;
        }
    }
}

sub send {
    my ($self, $message) = @_;
    my $line = $message->encode . $Argon::EOL;
    $self->out->send($line);
    croak 'disconnected'
        unless $self->out->is_connected;
}

sub receive {
    my $self = shift;
    my $line = $self->in->receive(TO => $Argon::EOL);
    croak 'disconnected'
        unless defined $line
            && $self->in->is_connected;
    return Argon::Message::decode($line);
}

__PACKAGE__->meta->make_immutable;

1;