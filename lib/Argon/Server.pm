package Argon::Server;

use Carp;
use Moose;
use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket;
use Argon::Message;
use Argon qw/:defaults/;

has 'port'          => (is => 'ro', isa => 'Int');
has 'host'          => (is => 'ro', isa => 'Str');
has 'endline'       => (is => 'ro', isa => 'Str', default => EOL);
has 'chunk_size'    => (is => 'ro', isa => 'Int', default => CHUNK_SIZE);
has 'on_error'      => (is => 'rw', isa => 'CodeRef', required => 1);
has 'callback'      => (is => 'rw', isa => 'HashRef', init_arg => undef, default => sub { {} });
has 'condvar'       => (is => 'ro', init_arg => undef, default => sub { AnyEvent->condvar });
has 'server'        => (is => 'rw', init_arg => undef);

sub respond_to {
    my ($self, $command, $cb) = @_;
    $self->callback->{$command} = $cb;
}

sub start {
    my $self = shift;
    $self->server(tcp_server $self->host, $self->port, sub { $self->accept(@_) }, sub { $self->initialized(@_) });
    $self->condvar->recv;
}

sub stop {
    my $self = shift;
    $self->condvar->send;
}

sub initialized {
    my ($self, $fh, $host, $port) = @_;
}

sub accept {
    my ($self, $fh, $host, $port) = @_;
    warn "-client connected from $host:$port\n";

    my $handle = AnyEvent::Handle->new(
        fh       => $fh,
        on_eof   => sub {
            warn "-client disconnected\n";
        },
        on_error => sub {
            my $msg = $_[2];
            warn "-error: $msg\n";
        },
    );

    $handle->on_read(sub {
        my @start_request;

        @start_request = (
            line => sub {
                my ($handle, $line, $eol) = @_;
                my $message = Argon::Message::decode($line);
                my ($response, $error);

                if (exists $self->callback->{$message->command}) {
                    $response = eval { $self->callback->{$message->command}->($message) };
                    $error = sprintf('Application Error: %s', $@)
                        if $@;
                } else {
                    $error = sprintf('Protocol Error: command not recognized [%s]', $message->command);
                }

                $response = $self->on_error->($error, $message)
                    if $error;

                $handle->push_write($response->encode . $self->endline);
                $handle->push_read(@start_request);
            }
        );

        $handle->push_read(@start_request);
    });
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;