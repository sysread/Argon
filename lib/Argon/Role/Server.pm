package Argon::Role::Server;

use Moose::Role;
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

# Hash of msg->id => handle, for replying to msg
has 'msg2handle' => (
    is       => 'ro',
    isa      => 'HashRef[AnyEvent::Handle]',
    init_arg => undef,
    default  => sub {{}},
    traits   => ['Hash'],
    handles  => {
        origin_set  => 'set',
        origin_get  => 'get',
        origin_del  => 'delete',
    },
);

# Hash of handle->fh => msg->id for fast lookups when
# client is disconnected.
has 'fd2msg' => (
    is       => 'ro',
    isa      => 'HashRef',
    init_arg => undef,
    default  => sub {{}},
);

#-------------------------------------------------------------------------------
# Initializes and starts the server.
#-------------------------------------------------------------------------------
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

#-------------------------------------------------------------------------------
# Stops the server.
#-------------------------------------------------------------------------------
sub stop {
    my $self = shift;
}

#-------------------------------------------------------------------------------
# Callback when a new client connects to the listening socket.
#-------------------------------------------------------------------------------
sub accept {
    my ($self, $fh, $host, $port) = @_;
    LOG("client connected from %s:%d", $host, $port);

    my $handle = AnyEvent::Handle->new(
        fh       => $fh,
        on_eof   => sub {
            LOG("client disconnected");
            $self->purge_fh($fh);
        },
        on_error => sub {
            my $msg = $_[2];
            LOG("error: $msg") unless $msg eq 'Broken pipe';
            $self->purge_fh($fh);
        },
    );

    $handle->on_read(sub {
        my @start_request;

        @start_request = (
            line => sub {
                my ($handle, $line, $eol) = @_;
                my $message = Argon::Message::decode($line);

                $self->register_message($handle, $message);
                my $response = $self->dispatch_message($message);

                if ($response && ref $response eq 'Argon::Message') {
                    $self->send_reply($response);
                }

                $handle->push_read(@start_request);
            }
        );

        $handle->push_read(@start_request);
    });
}

#-------------------------------------------------------------------------------
# Registers callback for incoming requests of a particular command type.
#-------------------------------------------------------------------------------
sub respond_to {
    my ($self, $command, $cb) = @_;
    $self->callback->{$command} = $cb;
}

#-------------------------------------------------------------------------------
# Dispatches a message based on registered callbacks.
#-------------------------------------------------------------------------------
sub dispatch_message {
    my ($self, $message) = @_;
    my ($response, $error);

    if (exists $self->callback->{$message->command}) {
        $response = eval { $self->callback->{$message->command}->($message) };
        $@ && ($error = sprintf('Application Error: %s', $@));
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

    return $response;
}

#-------------------------------------------------------------------------------
# Stores a message internally so that it may be replied to at a later time.
#-------------------------------------------------------------------------------
sub register_message {
    my ($self, $handle, $message) = @_;
    $self->origin_set($message->id, $handle);
    $self->fd2msg->{$handle->fh} ||= {};
    $self->fd2msg->{$handle->fh}{$message->id} = 1;
}

#-------------------------------------------------------------------------------
# Unregisters a registered message.
#-------------------------------------------------------------------------------
sub unregister_message {
    my ($self, $handle, $message) = @_;
    $self->origin_del($message->id);
    undef $self->fd2msg->{$handle->fh}{$message->id};
}

#-------------------------------------------------------------------------------
# Purges all messages awaiting reply for a given file handle.
#-------------------------------------------------------------------------------
sub purge_fh {
    my ($self, $fh) = @_;
    $self->origin_del($_) foreach keys %{$self->fd2msg->{$fh}};
    undef $self->fd2msg->{$fh};
}

#-------------------------------------------------------------------------------
# Sends a reply to a previously registered message.
#-------------------------------------------------------------------------------
sub send_reply {
    my ($self, $message) = @_;
    my $handle = $self->origin_get($message->id);
    if ($handle) {
        $handle->push_write($message->encode . $self->endline);
        $self->unregister_message($handle, $message);
    }
}

no Moose;

1;
