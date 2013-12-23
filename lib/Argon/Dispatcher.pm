package Argon::Dispatcher;

use Moose;
use MooseX::AttributeShortcuts;
use Carp;

extends 'Argon::Service';

has _dispatch => (
    is       => 'ro',
    isa      => 'HashRef[CodeRef]',
    init_arg => undef,
    default  => sub {{}},
    traits   => ['Hash'],
    handles  => {
        respond_to   => 'set',
        responds_to  => 'exists',
        get_callback => 'get',
    }
);

sub dispatch {
    my $self = shift;
    my $msg  = shift;
    my $cmd  = $msg->cmd;
    croak "command not handled: $cmd" unless $self->responds_to($cmd);
    return $self->get_callback($cmd)->($msg, @_);
}

no Moose;
__PACKAGE__->meta->make_immutable;
1;
