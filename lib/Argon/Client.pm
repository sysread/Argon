#-------------------------------------------------------------------------------
# TODO Reconnection scheme
# TODO Error handler for handle/socket errors
#-------------------------------------------------------------------------------
package Argon::Client;

use Carp;
use Moose;
use namespace::autoclean;
use AnyEvent;
use AnyEvent::Handle;
use AnyEvent::Socket;
use Argon qw/:defaults :commands LOG/;
require Argon::Message;
require Argon::Respond;

has 'port' => (
    is        => 'ro',
    isa       => 'Int',
    required  => 1,
);

has 'host' => (
    is        => 'ro',
    isa       => 'Str',
    required  => 1,
);

has 'endline' => (
    is        => 'ro',
    isa       => 'Str',
    default   => EOL,
);

has 'chunk_size' => (
    is        => 'ro',
    isa       => 'Int',
    default   => CHUNK_SIZE,
);

has 'handle' => (
    is        => 'rw',
    isa       => 'AnyEvent::Handle',
    init_arg  => undef,
    clearer   => 'disconnect',
    predicate => 'is_connected',
);

has 'respond' => (
    traits    => ['Hash'],
    is        => 'ro',
    isa       => 'HashRef[Argon::Respond]',
    init_arg  => undef,
    default   => sub {{}},
    handles   => {
        respond_get    => 'get',
        respond_set    => 'set',
        respond_keys   => 'keys',
        respond_delete => 'delete',
    },
);

# Flags whether or not to backlog rejected tasks for resubmission.
has 'has_backlog' => (
    is        => 'ro',
    isa       => 'Bool',
    default   => 1,
);

# Stores rejected tasks for resubmission.
has 'backlog' => (
    is        => 'rw',
    isa       => 'ArrayRef',
    init_arg  => undef,
    default   => sub {[]},
);

# Checks for backlogged tasks and resubmits them.
has 'backlog_timer' => (
    is        => 'rw',
    init_arg  => undef,
);

has 'connection_attempts' => (
    traits    => ['Counter'],
    is        => 'ro',
    isa       => 'Int',
    default   => 0,
    init_arg  => undef,
    handles   => {
        inc_connection_attempts   => 'inc',
        reset_connection_attempts => 'reset',
    },
);

# Attempts to reconnect after the connection to the server is unexpectedly broken.
has 'connection_timer' => (
    is        => 'rw',
    init_arg  => undef,
    clearer   => 'clear_connection_timer',
    predicate => 'is_reconnecting',
);


sub BUILD {
    my $self = shift;
    $self->backlog_timer(AnyEvent->timer(
        interval => POLL_INTERVAL,
        after    => 0,
        cb       => sub {
            while (my $item = pop @{$self->backlog}) {
                $self->queue(@$item);
            }
        }
    ));
}

sub connect {
    my ($self, $cb) = @_;
    tcp_connect $self->host, $self->port, sub { $self->on_connect($cb, @_) };
}

sub close {
    my $self = shift;
    $self->handle->destroy;
    $self->disconnect;
}

sub next_reconnect_attempt {
    my $self = shift;
    my $n = $self->connection_attempts ** 2;
    return $n < 1 ? 1 : log($n);
}

sub reconnect {
    my $self = shift;
    unless ($self->is_reconnecting) {
        LOG("Reconnect in %fs", $self->next_reconnect_attempt);

        $self->connection_timer(AnyEvent->timer(
            after    => $self->next_reconnect_attempt,
            cb       => sub {
                $self->clear_connection_timer;
                $self->inc_connection_attempts;
                $self->connect;
            },
        ));
    }
}

sub stop_reconnecting {
    my $self = shift;
    $self->clear_connection_timer;
}

sub on_connect {
    my ($self, $cb, $fh, $host, $port, $retry) = @_;

    if (!defined $fh) {
        LOG('Failure connecting to remote host %s:%d.', $self->host, $self->port);
        $self->reconnect;
    } else {
        LOG('Connected to remote host %s:%d.', $self->host, $self->port);
        $self->stop_reconnecting;
        $self->reset_connection_attempts;

        my $handle = AnyEvent::Handle->new(
            fh       => $fh,
            on_eof   => sub { $self->reconnect },
            on_error => sub { $self->reconnect },
        );

        $self->handle($handle);

        # Configure continuous reader callback
        $self->handle->on_read(sub { $self->on_message(@_) });

        if (ref $cb eq 'CODE') {
            $cb->($self);
        }
    }
}

#-------------------------------------------------------------------------------
# Dispatches received messages to configured callbacks or Respond object.
#-------------------------------------------------------------------------------
sub on_message {
    my $self = shift;
    my @start_request;

    @start_request = (
        line => sub {
            my ($handle, $line, $eol) = @_;
            my $message = Argon::Message::decode($line);

            my $respond = $self->respond_get($message->id);
            if ($respond) {
                $respond->dispatch($message);
                $self->respond_delete($message);
            }

            $self->handle->push_read(@start_request)
                if $self->is_connected;
        }
    );

    $self->handle->push_read(@start_request);
}

#-------------------------------------------------------------------------------
# Sends a single message to the remote host and dispatches Argon::Respond
# $respond with the server's reply.
#-------------------------------------------------------------------------------
sub send {
    my ($self, $message, $respond) = @_;
    $self->respond_set($message->id, $respond);
    $self->handle->push_write($message->encode . $self->endline);
}

#-------------------------------------------------------------------------------
# Sends a task to the remote host and begins polling for the response.
# TODO Make the poll an interval that is turned on or off based on the presense
#      of outstanding tasks, rather than scheduling a unique one for each
#      pending task.
#-------------------------------------------------------------------------------
sub process {
    my ($self, %param) = @_;
    my $job_class  = $param{class} || croak 'Expected named parameter "class"';
    my $job_args   = $param{args}  || croak 'Expected named parameter "args"';
    my $on_success = $param{on_success};
    my $on_error   = $param{on_error};

    my $msg = Argon::Message->new(command => CMD_QUEUE);
    $msg->set_payload([$job_class, $job_args]);
    $self->queue($msg, sub { $on_success->(shift->payload) }, sub { $on_error->(shift->payload) });
}

#-------------------------------------------------------------------------------
# Queues a message on the remote host and polls for the result.
#-------------------------------------------------------------------------------
sub queue {
    my ($self, $msg, $on_success, $on_error) = @_;
    Carp::confess 'Inappropriate message status (expected QUEUE)'
        unless $msg->command() == CMD_QUEUE;

    my $respond = Argon::Respond->new;
    $respond->to(CMD_ERROR,    sub { $on_error->(shift)   }) if $on_error;
    $respond->to(CMD_COMPLETE, sub { $on_success->(shift) }) if $on_success;
    $respond->to(CMD_PENDING,  sub { $self->respond_set($msg->id => $respond) });

    if ($self->has_backlog) {
        $respond->to(CMD_REJECTED, sub { push @{$self->backlog}, [$msg, $on_success, $on_error] });
    } else {
        $respond->to(CMD_REJECTED, sub { $on_success->(shift) }) if $on_success;
    }

    $self->send($msg, $respond);
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
