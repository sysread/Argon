package Argon::Stream;

use Moose;
use MooseX::AttributeShortcuts;
use AnyEvent;
use AnyEvent::Socket;
use Carp;
use Coro;
use Coro::Handle;
use Socket qw(unpack_sockaddr_in inet_ntoa);
use Argon::Message;
use Argon qw(:logging);

has handle => (
    is        => 'rwp',
    isa       => 'Coro::Handle',
    required  => 1,
    clearer   => '_clear_handle',
    predicate => 'is_connected',
    handles   => {
        fh => 'fh',
    }
);

has addr => (
    is  => 'lazy',
    isa => 'Str',
);

sub _build_addr {
    my $self = shift;
    my ($port, $ip) = unpack_sockaddr_in($self->handle->sockname);
    my $host = inet_ntoa($ip);
    sprintf('%s:%d', $host, $port);
}

sub connect {
    my ($class, $host, $port) = @_;
    my $rouse = rouse_cb;
    my $stream;
    my $error;

    tcp_connect($host, $port,
        sub {
            my $fh = shift;
            if ($fh) {
                $stream = $class->new(handle => unblock $fh);
            } else {
                $error = "error connecting to $host:$port: $!";
            }

            $rouse->();
        },
        sub { $Argon::CONNECT_TIMEOUT },
    );

    rouse_wait($rouse);
    croak $error if $error;
    return $stream;
}

sub close {
    my $self = shift;
    $self->handle->close;
    $self->_clear_handle;
}

sub write {
    my ($self, $msg) = @_;
    croak 'not connected' unless $self->is_connected;
    $self->handle->print($msg->encode . $Argon::EOL);
}

sub read {
    my $self = shift;
    croak 'not connected' unless $self->is_connected;
    my $line = $self->handle->readline($Argon::EOL) or return;
    do { local $\ = $Argon::EOL ; chomp $line };
    return Argon::Message->decode($line);
}

no Moose;
__PACKAGE__->meta->make_immutable;
1;
