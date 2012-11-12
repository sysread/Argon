package Argon::Server;

use Moose;
use Carp;
use namespace::autoclean;
use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket;
use Argon::Message;
use Argon qw/LOG :defaults/;

has 'port' => (
    is  => 'rw',
    isa => 'Int',
);

has 'host' => (
    is  => 'rw',
    isa => 'Str',
);

has 'endline' => (
    is      => 'ro',
    isa     => 'Str',
    default => EOL,
);

has 'chunk_size' => (
    is      => 'ro',
    isa     => 'Int',
    default => CHUNK_SIZE,
);

has 'on_error' => (
    is       => 'rw',
    isa      => 'CodeRef',
);

has 'callback' => (
    is       => 'rw',
    isa      => 'HashRef[CodeRef]',
    init_arg => undef,
    default  => sub { {} },
);

has 'server' => (
    is       => 'rw',
    isa      => 'AnyEvent::Util::guard',
    init_arg => undef,
);

sub respond_to {
    my ($self, $command, $cb) = @_;
    $self->callback->{$command} = $cb;
}

sub start {
    my $self = shift;
    my $server = tcp_server(
        $self->host,
        $self->port,
        # Accept callback
        sub {
            my ($fh, $host, $port) = @_;
            $self->host($host);
            $self->port($port);
            $self->accept(@_);
        },
        # Prepare callback (returns listen queue size)
        sub {
            LOG("Listening on port %d", $self->port);
            return LISTEN_QUEUE_SIZE;
        },
    );
    $self->server($server);
}

sub stop {
    my $self = shift;
}

sub accept {
    my ($self, $fh, $host, $port) = @_;
    LOG("client connected from %s:%d", $host, $port);

    my $handle = AnyEvent::Handle->new(
        fh       => $fh,
        on_eof   => sub {
            LOG("client disconnected");
        },
        on_error => sub {
            my $msg = $_[2];
            LOG("error: $msg") unless $msg eq 'Broken pipe';
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

                if ($error) {
                    if ($self->on_error) {
                        $response = $self->on_error->($error, $message);
                    } else {
                        LOG("an error occurred: %s", $error);
                    }
                }

                $handle->push_write($response->encode . $self->endline);
                $handle->push_read(@start_request);
            }
        );

        $handle->push_read(@start_request);
    });
}

__PACKAGE__->meta->make_immutable;

1;