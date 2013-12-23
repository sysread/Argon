package Argon::Client;

use Moose;
use MooseX::AttributeShortcuts;
use Carp;
use AnyEvent;
use AnyEvent::Socket;
use Coro;
use Coro::AnyEvent;
use Coro::Handle;
use Guard qw(scope_guard);
use Argon qw(:commands :priorities);
use Argon::Message;
use Argon::Stream;

has host => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has port => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

has stream => (
    is       => 'lazy',
    isa      => 'Argon::Stream',
    init_arg => undef,
    handles  => [qw(addr)],
);

sub _build_stream {
    my $self = shift;
    return Argon::Stream->connect($self->host, $self->port);
}

after _build_stream => sub {
    my $self = shift;
    $self->read_loop;
};

has pending => (
    is       => 'ro',
    isa      => 'HashRef',
    init_arg => undef,
    default  => sub {{}},
    traits   => ['Hash'],
    handles  => {
        set_pending => 'set',
        get_pending => 'get',
        has_pending => 'exists',
        del_pending => 'delete',
        all_pending => 'keys',
    }
);

has inbox => (
    is       => 'ro',
    isa      => 'Coro::Channel',
    init_arg => undef,
    default  => sub { Coro::Channel->new() },
);

has read_loop => (
    is       => 'lazy',
    isa      => 'Coro',
    init_arg => undef,
);

sub _build_read_loop {
    my $self = shift;
    return async {
        scope_guard { $self->shutdown };

        while (1) {
            my $msg = $self->stream->read or last;

            if ($self->has_pending($msg->id)) {
                $self->get_pending($msg->id)->put($msg);
            } else {
                $self->inbox->put($msg);
            }
        }
    };
}

sub shutdown {
    my $self = shift;

    $self->stream->close;
    $self->inbox->shutdown;

    my $error = 'Lost connection to worker while processing request';
    foreach my $msgid ($self->all_pending) {
        my $msg = Argon::Message->new(cmd => $CMD_ERROR, id => $msgid, payload => $error);
        $self->get_pending($msgid)->put($msg);
    }
}

sub connect {
    my $self = shift;
    $self->stream;
}

sub _wait_msgid {
    my ($self, $msgid) = @_;
    my $reply = $self->get_pending($msgid)->get();
    $self->del_pending($msgid);
    return $reply;
}

sub send {
    my ($self, $msg) = @_;
    $self->set_pending($msg->id, Coro::Channel->new());
    $self->stream->write($msg);
    return $self->_wait_msgid($msg->id);
}

sub queue {
    my ($self, $f, $args, $pri) = @_;
    $f && ref $f eq 'CODE' || croak 'expected CODE ref';
    $args ||= [];
    ref $args eq 'ARRAY' || croak 'expected ARRAY ref of args';
    $pri ||= $PRI_NORMAL;

    my $reply = $self->send(Argon::Message->new(
        cmd     => $CMD_QUEUE,
        pri     => $pri,
        payload => [$f, $args],
    ));

    if ($reply->cmd == $CMD_COMPLETE) {
        return $reply->payload;
    } elsif ($reply->cmd == $CMD_ERROR) {
        croak $reply->payload;
    }
}

sub defer {
    my $arr = wantarray;
    my $cv  = AnyEvent->condvar;

    my $thread = async_pool {
        if ($arr) {
            my @result = eval { queue(@_) };
            $cv->croak($@) if $@;
            $cv->send(@result);
        } else {
            my $result = eval { queue(@_) };
            $cv->croak($@) if $@;
            $cv->send($result);
        }
    } @_;

    return sub { $cv->recv };
}

no Moose;
__PACKAGE__->meta->make_immutable;
1;
