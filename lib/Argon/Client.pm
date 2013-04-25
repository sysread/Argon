package Argon::Client;

use strict;
use warnings;
use Carp;

use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

use Argon::Stream;
use Argon::Message;
use Argon qw/:logging :commands/;

has 'port' => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

has 'host' => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has 'stream' => (
    is       => 'rw',
    isa      => 'Argon::Stream',
    init_arg => undef,
);

sub connect {
    my $self   = shift;
    my $stream = Argon::Stream->connect(
        host => $self->host,
        port => $self->port,
    );

    $self->stream($stream);
}

sub process {
    my ($self, %param) = @_;
    my $class  = $param{class}  || croak 'expected class';
    my $params = $param{params} || [];

    croak 'not connected' unless $self->stream;

    my $msg = Argon::Message->new(command => CMD_QUEUE);
    $msg->set_payload([$class, $params]);

    return $self->stream->send_retry($msg);
}

__PACKAGE__->meta->make_immutable;

1;