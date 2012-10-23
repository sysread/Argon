#-------------------------------------------------------------------------------
# 
#-------------------------------------------------------------------------------
package Argon::Cluster;

use Moose;
use Carp;
use namespace::autoclean;
use Argon qw/:commands/;
require Argon::Client;

extends 'Argon::MessageManager';
with    'Argon::MessageServer';

has 'nodes' => (
    is       => 'ro',
    isa      => 'HashRef',
    init_arg => undef,
    default  => sub {{}},
);

after 'build_protocol' => sub {
    my $self = shift;
    $self->server->respond_to(CMD_ADD_NODE, $self->add_node);
    $self->server->respond_to(CMD_DEL_NODE, $self->del_node);
};

sub add_node {
    my ($self, $msg)  = @_;
    my ($host, $port) = @{$msg->get_payload};
    my $client = Argon::Client->new(
        host       => $host,
        port       => $port,
        endline    => $self->endline,
        chunk_size => $self->chunk_size,
        on_error   => sub {
            # TODO: mark as unavailable
        },
    );

    $self->nodes->{"$host:$port"} = $client;
    $self->add_client($client);
}

sub del_node {
    my ($self, $msg)  = @_;
    my ($host, $port) = @{$msg->get_payload};
    if (exists $self->nodes->{"$host:$port"}) {
        my $client = $self->nodes->{"$host:$port"};
        $self->del_client($client);
    }
}

__PACKAGE__->meta->make_immutable;

1;