package Argon::Channel;
# TODO Reconnection scheme

use strict;
use warnings;
use Carp;
use Moose;
use Scalar::Util qw/weaken/;
use AnyEvent::Socket;
use AnyEvent::Handle;
use Argon qw/:defaults :commands EOL LOG/;

has 'port' => (
    is       => 'rw',
    isa      => 'Int',
    clearer  => 'clear_port',
);

has 'host' => (
    is       => 'rw',
    isa      => 'Str',
    clearer  => 'clear_host',
);

has 'endline' => (
    is       => 'rw',
    isa      => 'Str',
    default  => EOL,
);

has 'handle' => (
    is       => 'rw',
    isa      => 'AnyEvent::Handle',
    init_arg => undef,
    clearer  => 'clear_handle',
);

has 'responders' => (
    is       => 'ro',
    isa      => 'HashRef[CodeRef]',
    init_arg => undef,
    traits   => ['Hash'],
    handles  => {
        respond_to  => 'set',
        respond     => 'get',
        responds_to => 'exists',
    }
);

has 'pending' => (
    is       => 'ro',
    isa      => 'HashRef[Argon::Message]',
    init_arg => undef,
    traits   => ['Hash'],
    handles  => {
        msg_set_pending => 'set',
        msg_get_pending => 'get',
        msg_is_pending  => 'exists',
        msg_clear       => 'delete',
    }
);

# Called when a queued message is completed
has 'on_complete' => (
    is       => 'rw',
    isa      => 'CodeRef',
    predicate => 'has_on_complete',
);

has 'backlog' => (
    is       => 'ro',
    isa      => 'HashRef[Argon::Message]',
    init_arg => undef,
    traits   => ['Hash'],
    handles  => {
       backlog_add   => 'set',
       backlog_get   => 'get',
       backlog_del   => 'delete',
       backlog_items => 'kv',
       no_backlog    => 'is_empty',
       backlogged    => 'exists',
    }
);

has 'retries' => (
    is       => 'ro',
    isa      => 'HashRef[Int]',
    init_arg => undef,
    default  => sub {{}},
);

has 'retry_timer' => (
    is       => 'rw',
    init_arg => undef,
    clearer  => 'stop_retry_timer',
);

has 'connect_callbacks' => (
    is       => 'ro',
    isa      => 'ArrayRef[CodeRef]',
    init_arg => undef,
    default  => sub {[]},
    traits   => ['Array'],
    handles  => {
        'add_connect_callbacks' => 'push',
        'all_connect_callbacks' => 'elements',
    }
);

has 'disconnect_callbacks' => (
    is       => 'ro',
    isa      => 'ArrayRef[CodeRef]',
    init_arg => undef,
    default  => sub {[]},
    traits   => ['Array'],
    handles  => {
        'add_disconnect_callbacks' => 'push',
        'all_disconnect_callbacks' => 'elements',
    }
);


sub BUILD {
    my $self = shift;
    $self->respond_to(CMD_COMPLETE, sub { $self->msg_complete(@_) });
    $self->respond_to(CMD_ERROR,    sub { $self->msg_complete(@_) });
    $self->respond_to(CMD_REJECTED, sub { $self->msg_rejected(@_) });
    weaken $self;
}

sub start_retry_timer {
    my $self = shift;
    $self->retry_timer(AnyEvent->timer(
        interval => POLL_INTERVAL,
        cb => sub { $self->drain },
    ));
}

sub connect {
    my ($self, %param) = @_;
    my $host = $param{host} || $self->host || croak 'expected "host"';
    my $port = $param{port} || $self->port || croak 'expected "port"';
    LOG('Connecting to %s:%d', $host, $port);
    tcp_connect($host, $port, sub { $self->_on_connect(@_) });
    $self->start_retry_timer;
}

sub close {
    my $self = shift;
    $self->handle->destroy if $self->handle;
}

sub _on_connect {
    my ($self, $fh, $host, $port, $retry) = @_;
    $self->host($host);
    $self->port($port);

    my $cb = sub { $self->_on_disconnect(@_) };
    my $handle = AnyEvent::Handle->new(
        fh       => $fh,
        on_eof   => $cb,
        on_error => $cb,
    );

    $self->handle($handle);
    $self->handle->on_read(sub { $self->_on_read(@_) });
    LOG('Connected to %s:%d', $host, $port);
    $_->($self) foreach $self->all_connect_callbacks;

    weaken $self;
}

sub _on_disconnect {
    my ($self) = @_;
    LOG('Disconnected from %s:%d', $self->host, $self->port);
    $_->($self) foreach $self->all_disconnect_callbacks;

    $self->stop_retry_timer;
    $self->clear_port;
    $self->clear_host;
    $self->clear_handle;
}

sub _on_read {
    my $self = shift;
    $self->handle->push_read(line => sub { $self->on_message(@_) });
}

sub on_message {
    my ($self, $handle, $line, $eol) = @_;
    my $msg = Argon::Message::decode($line);

    $self->respond($msg->command)->($msg)
        if $self->msg_is_pending($msg->id)
        && $self->responds_to($msg->command);

    $self->handle->push_read(line => sub { $self->on_message(@_) });
}

sub msg_complete {
    my ($self, $msg) = @_;
    $self->msg_clear($msg);
    delete $self->retries->{$msg->id};
    $self->on_complete->($msg, $self)
        if $self->has_on_complete;
}

sub msg_rejected {
    my ($self, $msg) = @_;
    $self->retry($msg);
    ++$self->retries->{$msg->id};
}

sub send {
    my ($self, $msg) = @_;
    $self->handle->push_write($msg->encode . $self->endline);
}

sub queue {
    my ($self, $msg) = @_;
    $self->msg_set_pending($msg->id, $msg);
    $self->send($msg);
}

sub process {
    my ($self, %param) = @_;
    my $job_class = $param{class} || croak 'Expected named parameter "class"';
    my $job_args  = $param{args}  || croak 'Expected named parameter "args"';

    my $task = [$job_class, $job_args];
    my $msg  = Argon::Message->new(command => CMD_QUEUE);

    $msg->set_payload($task);
    $self->queue($msg);
}

sub retry {
    my ($self, $msg) = @_;
    unless ($self->backlogged($msg->id)) {
        my $retry_after = time + log($self->retries->{$msg->id}) / 10;
        $self->backlog_add($msg->id, $retry_after);
    }
}

sub drain {
    my $self = shift;
    my $now  = time;
    foreach my $pair ($self->backlog_items) {
        my ($msg_id, $retry_after) = @$pair;
        if ($retry_after <= $now) {
            $self->send($self->msg_get_pending($msg_id));
            $self->backlog_del($msg_id);
        }
    }
}

no Moose;
__PACKAGE__->meta->make_immutable;