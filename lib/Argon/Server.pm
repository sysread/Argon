package Argon::Server;

use strict;
use warnings;
use Carp;

use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

use AnyEvent;
use Coro;
use Coro::AnyEvent;
use IO::Socket::INET;
use Socket qw/getnameinfo/;

use Argon::Stream;
use Argon::Message;
use Argon qw/:commands :defaults LOG K/;

has 'port' => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

has 'host' => (
    is       => 'ro',
    isa      => 'Str',
    default  => 'localhost',
);

#-------------------------------------------------------------------------------
# Stores callbacks for a given command.
#-------------------------------------------------------------------------------
has 'handler' => (
    is       => 'ro',
    isa      => 'HashRef[CodeRef]',
    init_arg => undef,
    default  => sub {{}},
    traits   => ['Hash'],
    handles  => {
        respond_to  => 'set',
        get_handler => 'get',
        has_handler => 'exists',
        handles     => 'keys',
    }
);

#-------------------------------------------------------------------------------
# Flags the stream->address as currently being serviced. If the flag is deleted,
# the service loop for the stream will self-terminate. If unset from within a
# response-handler, any message returned by the handler will be sent before the
# loop terminates.
#-------------------------------------------------------------------------------
has 'service_loop' => (
    is       => 'ro',
    isa      => 'HashRef[Int]',
    init_arg => undef,
    default  => sub {{}},
    traits   => ['Hash'],
    handles  => {
        set_service  => 'set',
        get_service  => 'get',
        stop_service => 'delete',
        has_service  => 'exists',
    }
);

#-------------------------------------------------------------------------------
# Starts the server listening for new requests.
#-------------------------------------------------------------------------------
sub start {
    my $self = shift;
    my $sock = IO::Socket::INET->new(
        LocalAddr => $self->host,
        LocalPort => $self->port,
        Proto     => 'tcp',
        Type      => SOCK_STREAM,
        Listen    => LISTEN_QUEUE_SIZE,
        ReuseAddr => 1,
        Blocking  => 0,
    );

    unless ($sock) {
        LOG('Error creating server socket: %s', $!);
        exit 1;
    }

    $sock->listen or croak $!;
    LOG('Service started on %s:%d', $self->host, $self->port);

    while (1) {
        Coro::AnyEvent::readable($sock);
        my $client = $sock->accept;
        my $stream = Argon::Stream->new(fh => $client);
        $self->service($stream);
    }
}

#-------------------------------------------------------------------------------
# Launches a new coro to handle incoming requests from a stream.
#-------------------------------------------------------------------------------
sub service {
    my ($self, $stream) = @_;
    my $addr = $stream->address;
    LOG('Client connected: %s', $addr);

    $self->set_service($addr, 1);

    async {
        while ($stream->is_connected && $self->has_service($stream->address)) {
            my $msg = $stream->next_message or last;
            async {
                my $reply = $self->dispatch($msg, $stream);
                if (defined $reply) {
                    if ($reply->isa('Argon::Message')) {
                        eval { $stream->send_message($reply) };
                        if ($@ && Argon::Stream::is_connection_error($@)) {
                            # pass
                        }
                    }
                }
            };
        }

        $self->stop_service($stream->address);
    };
}

#-------------------------------------------------------------------------------
# Dispatches a message to registered callbacks based on the message's command.
#-------------------------------------------------------------------------------
sub dispatch {
    my ($self, $msg, $stream) = @_;
    if ($self->has_handler($msg->command)) {
        return $self->get_handler($msg->command)->($msg, $stream);
    } else {
        LOG('Warning: command not handled - %d', $msg->command);
        my $reply = $msg->reply(CMD_ERROR);
        $reply->set_payload('Command not handled');
        return $reply;
    }
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;