package Argon::Dispatcher;

use Moo;
use MooX::HandlesVia;
use Types::Standard qw(-types);
use Carp;

extends 'Argon::Service';

has _dispatch => (
    is          => 'ro',
    isa         => Map[Int,CodeRef],
    init_arg    => undef,
    default     => sub {{}},
    handles_via => 'Hash',
    handles     => {
        respond_to   => 'set',
        get_callback => 'get',
        responds_to  => 'exists',
    }
);

sub dispatch {
    my $self = shift;
    my $msg  = shift;
    my $cmd  = $msg->cmd;
    croak "command not handled: $cmd" unless $self->responds_to($cmd);
    return $self->get_callback($cmd)->($msg, @_);
}

1;
