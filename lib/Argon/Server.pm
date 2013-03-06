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
# Marks a msg id as having a request pending with a stream.
#-------------------------------------------------------------------------------
has 'pending' => (
    is       => 'ro',
    isa      => 'HashRef[Argon::Stream]',
    init_arg => undef,
    default  => sub {{}},
    traits   => ['Hash'],
    handles  => {
        set_pending => 'set',
        get_pending => 'get',
        del_pending => 'delete',
        has_pending => 'exists',
        all_pending => 'keys',
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
    init_arg => sub {{}},
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
        LOG($!);
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
    LOG('Client connected: %s', $stream->address);

    $self->set_service($stream->address, 1);

    async {
        while ($stream->is_connected && $self->has_service($stream->address)) {
            my $msg = $stream->next_message or last;
            $self->set_pending($msg->id, $stream);
            
            my $reply = $self->dispatch($msg, $stream);
            if (defined $reply) {
                if ($reply->isa('Argon::Message')) {
                    $self->send_response($reply);
                } else {
                    $self->del_pending($msg->id);
                }
            }
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

#-------------------------------------------------------------------------------
# For previously dispatched messages which did not generate an immediate
# response, send_response allows a reply to be sent when it becomes available.
# It is the handler's responsibility to manage this by calling send_response.
#-------------------------------------------------------------------------------
sub send_response {
    my ($self, $msg) = @_;
    if ($self->has_pending($msg->id)) {
        my $stream = $self->get_pending($msg->id);
        $self->del_pending($msg->id);

        eval { $stream->send_message($msg) };

        # If sending the reply failed due to a connection error, clear any other
        # messages pending for this stream.
        if ($@ && $@ =~ /closed/) {
            $self->cleanup_stream($stream);
        }
    }
}

#-------------------------------------------------------------------------------
# 
#-------------------------------------------------------------------------------
sub cleanup_stream {
    my ($self, $stream) = @_;
    foreach my $msg_id ($self->all_pending) {
        if ($self->get_pending($msg_id) eq $stream) {
            $self->del_pending($msg_id);
        }
    }
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;