#-------------------------------------------------------------------------------
# Argon::Cluster is a MessageManager that intelligently distributes messages
# among a list of clients. Clusters are also MessageServers that accept new
# messages and track their status, acting as a proxy for its client list.
#-------------------------------------------------------------------------------
package Argon::Cluster;

use Moose;
use Carp;
use namespace::autoclean;
use Argon qw/LOG :commands/;
require Argon::Client;

extends 'Argon::MessageManager';
with    'Argon::Role::MessageServer';

#-------------------------------------------------------------------------------
# Re-references Argon::Client nodes by host:port so that they may be removed by
# command later (also stored in Argon::MessageManager->servers.
#-------------------------------------------------------------------------------
has 'nodes' => (
    is       => 'ro',
    isa      => 'HashRef[Argon::Client]',
    init_arg => undef,
    default  => sub {{}},
);

sub BUILD {
    my $self = shift;
    $self->server->respond_to(CMD_ADD_NODE, sub { $self->add_node(@_) });
    $self->server->respond_to(CMD_DEL_NODE, sub { $self->del_node(@_) });
}

sub add_node {
    my ($self, $msg)  = @_;
    my ($host, $port) = @{$msg->get_payload};
    my $client = Argon::Client->new(
        host       => $host,
        port       => $port,
        endline    => $self->endline,
        chunk_size => $self->chunk_size,
    );

    $self->nodes->{"$host:$port"} = $client;
    $self->add_client($client);
    
    return $msg->reply(CMD_ACK);
}

sub del_node {
    my ($self, $msg)  = @_;
    my ($host, $port) = @{$msg->get_payload};
    if (exists $self->nodes->{"$host:$port"}) {
        my $client = $self->nodes->{"$host:$port"};
        undef $self->nodes->{"$host:$port"};
        $self->del_client($client);
    }

    return $msg->reply(CMD_ACK);
}

__PACKAGE__->meta->make_immutable;

1;