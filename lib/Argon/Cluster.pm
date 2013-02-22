#-------------------------------------------------------------------------------
# Argon::Cluster is a MessageManager that intelligently distributes messages
# among a list of clients. Clusters are also MessageServers that accept new
# messages and track their status, acting as a proxy for its client list.
#
# TODO
#   * Handle unexpected node disconnects
#-------------------------------------------------------------------------------
package Argon::Cluster;

use Moose;
use Carp;
use namespace::autoclean;
use Scalar::Util qw/weaken/;
use Argon qw/LOG :commands/;

require Argon::Channel;

extends 'Argon::MessageManager';
with    'Argon::Role::Server';
with    'Argon::Role::MessageServer';
with    'Argon::Role::ManagedServer';

#-------------------------------------------------------------------------------
# Re-references Argon::Channel nodes by host:port so that they may be removed by
# command later (also stored in Argon::MessageManager->servers.
#-------------------------------------------------------------------------------
has 'nodes' => (
    is       => 'ro',
    isa      => 'HashRef[Argon::Channel]',
    init_arg => undef,
    default  => sub {{}},
);


sub DESTROY
{
    use Devel::Cycle;
    my $this = shift;

    # callback will be called for every cycle found
    find_cycle($this, sub {
            my $path = shift;
            foreach (@$path)
            {
                my ($type,$index,$ref,$value) = @$_;
                print STDERR "Circular reference found while destroying object of type " .
                    ref($this) . "! reftype: $type\n";
                # print other diagnostics if needed; see docs for find_cycle()
            }
        });

    # perhaps add code to weaken any circular references found,
    # so that destructor can Do The Right Thing
}

sub BUILD {
    my $self = shift;
    $self->respond_to(CMD_ADD_NODE, 'add_node');
    $self->respond_to(CMD_DEL_NODE, 'del_node');
}

sub add_node {
    my ($self, $msg)  = @_;
    my ($host, $port) = @{$msg->get_payload};

    unless (exists $self->nodes->{"$host:$port"}) {
        my $client = Argon::Channel->new(
            host    => $host,
            port    => $port,
            endline => $self->endline,
        );

        $self->nodes->{"$host:$port"} = $client;
        $self->add_client($client);

        weaken $client;
    }

    return $msg->reply(CMD_ACK);
}

sub del_node {
    my ($self, $msg)  = @_;
    my ($host, $port) = @{$msg->get_payload};
    if (exists $self->nodes->{"$host:$port"}) {
        my $client = $self->nodes->{"$host:$port"};
        $self->del_client($client);
        delete $self->nodes->{"$host:$port"};
    }
    return $msg->reply(CMD_ACK);
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
