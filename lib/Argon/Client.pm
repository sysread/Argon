#-------------------------------------------------------------------------------
# TODO Reconnection scheme
# TODO Prevent duplicate poll queries (e.g. poll x, start another poll before
#      x's poll gets a result
# TODO Provide on-error callback for initial connection
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

has 'on_error' => (
    is        => 'rw',
    isa       => 'CodeRef',
);

has 'handle' => (
    is        => 'rw',
    isa       => 'AnyEvent::Handle',
    init_arg  => undef,
    clearer   => 'disconnect',
    predicate => 'is_connected',
);

# Stores the next callback to be called for a given message id
has 'pending' => (
    is        => 'rw',
    isa       => 'HashRef[CodeRef]',
    init_arg  => undef,
    default   => sub {{}},
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

has 'poll_timer' => (
    is        => 'rw',
    init_arg  => undef,
    clearer   => 'stop_polling',
    predicate => 'is_polling',
);

has 'backlog' => (
    is        => 'rw',
    isa       => 'ArrayRef',
    init_arg  => undef,
    default   => sub {[]},
);

has 'backlog_timer' => (
    is        => 'rw',
    init_arg  => undef,
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
    $self->stop_polling;
}

sub on_connect {
    my ($self, $cb, $fh, $host, $port, $retry) = @_;
    croak 'Failure connecting to remote host' unless defined $fh;
    
    my $handle;
    $handle = AnyEvent::Handle->new(
        fh => $fh,
        on_eof => sub {
            LOG('Disconnected to remote host %s:%d.', $self->host, $self->port);
            $self->connect(sub {
                LOG('Reconnected to remote host %s:%d.', $self->host, $self->port);
            });
        },
        on_error => sub {
            my $msg = $_[2];
            LOG("Error: $msg");
        },
    );
    
    $self->handle($handle);

    # Configure continuous reader callback
    $self->handle->on_read(sub { $self->on_message(@_) });

    # Run poll timer
    #$self->poll_timer(AnyEvent->timer(after => 0, interval => POLL_INTERVAL, cb => sub { $self->_poll }));

    $cb->($self);
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

            if ($self->pending->{$message->id}) {
                my $cb = $self->pending->{$message->id};
                undef $self->pending->{$message->id};

                if (ref $cb eq 'Argon::Respond') {
                    $cb->dispatch($message);
                } else {
                    $cb->($message);

                }
            }

            $self->handle->push_read(@start_request)
                if $self->is_connected;
        }
    );

    $self->handle->push_read(@start_request);
}

#-------------------------------------------------------------------------------
# Registers callback (an instance of Argon::Respond) for tasks that have been
# accepted and are awaiting a result.
#-------------------------------------------------------------------------------
sub await {
    my ($self, $msg, $on_success, $on_error) = @_;

    my $respond = Argon::Respond->new;
    $respond->to(CMD_ERROR,    sub { $on_error->(shift)   }) if $on_error;
    $respond->to(CMD_COMPLETE, sub { $on_success->(shift) }) if $on_success;
    $respond->to(CMD_PENDING,  sub { $self->respond_set($msg->id => $respond) });

    $self->respond_set($msg->id, $respond);
}

#-------------------------------------------------------------------------------
# Sends a single message to the remote host and executes callback $cb if the
# server responds.
#-------------------------------------------------------------------------------
sub send {
    my ($self, $message, $cb) = @_;
    $self->handle->push_write($message->encode . $self->endline);
    $self->pending->{$message->id} = $cb;
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

    $self->await($msg, $on_success, $on_error);

    $self->send($msg, sub {
        my $reply = shift;
        if ($reply->command == CMD_REJECTED) {
            push @{$self->backlog}, [$msg, $on_success, $on_error];
        } else {
            my $callback = $self->respond_get($reply->id);
            $self->respond_delete($reply->id);
            # Callback may be undefined if the successful response was in-bound
            # from the last poll while this send was being performed.
            $callback->dispatch($reply)
                if defined $callback;
        }
    });
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
