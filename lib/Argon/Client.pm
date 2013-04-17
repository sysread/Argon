package Argon::Client;

use strict;
use warnings;
use Carp;

use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

use Argon::IO::Pipe;
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

has 'pipe' => (
    is       => 'rw',
    isa      => 'Argon::IO::Pipe',
    init_arg => undef,
);

sub connect {
    my $self = shift;
    my $pipe = Argon::IO::Pipe->connect(
        host => $self->host,
        port => $self->port,
    );

    $self->pipe($pipe);
}

sub process {
    my ($self, %param) = @_;
    my $class  = $param{class}  || croak 'expected class';
    my $params = $param{params} || [];

    croak 'not connected' unless $self->pipe;

    my $msg = Argon::Message->new(command  => CMD_QUEUE);
    $msg->set_payload([$class, $params]);

    return $self->pipe->send_retry($msg);
}

__PACKAGE__->meta->make_immutable;

1;