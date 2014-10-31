package Argon::Service;

use Moo;
use MooX::HandlesVia;
use Types::Standard qw(-types);
use Carp;
use Coro;
use Coro::Handle;
use AnyEvent;
use AnyEvent::Socket;
use Guard;
use Argon::Message;
use Argon::Stream;
use Argon qw(:commands :logging);

has port => (
    is  => 'rwp',
    isa => Int,
);

has host => (
    is  => 'rwp',
    isa => Str,
);

has address => (
    is  => 'rwp',
    isa => Str,
);

has stop_cb => (
    is          => 'rwp',
    isa         => CodeRef,
    init_arg    => undef,
    handles_via => 'Code',
    handles     => { stop => 'execute' }
);

sub start {
    my ($self, $cb) = @_;

    $self->_set_stop_cb(rouse_cb);
    my $sigint  = AnyEvent->signal(signal => 'INT',  cb => $self->stop_cb);
    my $sigterm = AnyEvent->signal(signal => 'TERM', cb => $self->stop_cb);

    my $guard = tcp_server(
        $self->host,
        $self->port,
        # accept callback
        sub {
            my ($fh, $host, $port) = @_;
            async_pool { $self->process_requests(unblock($fh), "$host:$port") };
        },
        # prepare callback
        sub {
            my ($fh, $host, $port) = @_;
            INFO 'Service started on %s:%d', $host, $port;
            $self->_set_port($port);
            $self->_set_host($host);
            $self->_set_address("$host:$port");
            $self->init;
            $cb->($self->address) if $cb && ref $cb eq 'CODE';
        },
    );

    rouse_wait($self->stop_cb);
    $self->shutdown;
    INFO 'Service stopped';
}

sub process_requests {
    my ($self, $handle, $addr) = @_;
    my $stream = Argon::Stream->new(handle => $handle);

    INFO 'Accepted connection from client (%s)', $addr;
    $self->client_connected($addr);

    scope_guard {
        if ($@) {
            WARN 'Error occurred processing request from %s: %s', $addr, $@;
        }

        INFO 'Lost connection to client (%s)', $addr;
        $self->client_disconnected($addr);
    };

    while (my $msg = $stream->read) {
        async_pool {
            my $reply = eval { $self->dispatch($msg, $addr) };

            if ($@) {
                $reply = $msg->reply(cmd => $CMD_ERROR, payload => $@);
            } elsif (!$reply || !$reply->isa('Argon::Message')) {
                $reply = $msg->reply(cmd => $CMD_ERROR, payload => 'The server generated an invalid response.');
            }

            $stream->write($reply);
        };
    }
}

# Methods triggered by the Argon::Service
sub init                { }
sub client_connected    { }
sub client_disconnected { }
sub shutdown            { }

1;
