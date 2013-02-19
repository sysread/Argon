#-------------------------------------------------------------------------------
# Convenience class for preparing a series of callbacks for a Message response.
#-------------------------------------------------------------------------------
package Argon::Respond;

use Moose;
use Carp;
use namespace::autoclean;
use Argon qw/LOG/;

has 'callback' => (
    is       => 'rw',
    isa      => 'HashRef[CodeRef]',
    init_arg => undef,
    default  => sub {{}},
);

#-------------------------------------------------------------------------------
# Registers a callback, overriding any existing callback for a command.
#-------------------------------------------------------------------------------
sub to {
    my ($self, $cmd, $cb) = @_;
    $self->callback->{$cmd} = $cb;
}

#-------------------------------------------------------------------------------
# Dispatches a response callback for a message. If no response is configured,
# no call is made and no error is signaled.
#-------------------------------------------------------------------------------
sub dispatch {
    my ($self, $msg, @args) = @_;
    $self->callback->{$msg->command}->($msg, @args)
        if exists $self->callback->{$msg->command};
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
