package Argon::Client;

use Carp;
use Moose;
use namespace::autoclean;
use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket;
use Argon qw/:defaults/;
require Argon::Message;

has 'port'          => (is => 'ro', isa => 'Int', required => 1);
has 'host'          => (is => 'ro', isa => 'Str', required => 1);
has 'endline'       => (is => 'ro', isa => 'Str', default => EOL);
has 'chunk_size'    => (is => 'ro', isa => 'Int', default => CHUNK_SIZE);
has 'on_connect'    => (is => 'rw', isa => 'CodeRef');
has 'on_error'      => (is => 'rw', isa => 'CodeRef');
has 'condvar'       => (is => 'ro', init_arg => undef, default => sub { AnyEvent->condvar });
has 'handle'        => (is => 'rw', isa => 'AnyEvent::Handle', init_arg => undef);

sub start {
    my $self = shift;
    tcp_connect $self->host, $self->port, sub { $self->connect(@_) }, sub { $self->initialized(@_) };
    $self->condvar->recv;
}

sub stop {
    my $self = shift;
    $self->condvar->send;
}

sub initialized {
    my ($self, $fh, $host, $port) = @_;
}

sub connect {
    my ($self, $fh, $host, $port, $retry) = @_;
    $self->handle(AnyEvent::Handle->new(fh => $fh));
    $self->on_connect->($self);
}

sub send {
    my ($self, $message, $cb) = @_;

    # Send message
    $self->handle->push_write($message->encode . $self->endline);

    # Add callback for response
    $self->handle->on_read(sub {
        $self->handle->push_read(line => sub {
            my ($handle, $line, $eol) = @_;
            my $message = Argon::Message::decode($line);
            $cb->($message);
        });
    });
}

__PACKAGE__->meta->make_immutable;

1;
