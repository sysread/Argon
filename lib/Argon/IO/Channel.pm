#-------------------------------------------------------------------------------
# Base class for IO channels.
#-------------------------------------------------------------------------------
package Argon::IO::Channel;

use strict;
use warnings;
use Carp;

use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;
use Socket qw/getnameinfo NI_NUMERICSERV/;

use constant ERROR        => 'error';
use constant DISCONNECTED => 'disconnected';
use constant COMPLETE     => 'complete';
use constant CONTINUE     => 'continue';

#-------------------------------------------------------------------------------
# Stores the output handle
#-------------------------------------------------------------------------------
has 'handle'  => (
    is        => 'rw',
    isa       => 'FileHandle',
    required  => 1,
    clearer   => 'clear_handle',
    predicate => 'has_handle',
);

#-------------------------------------------------------------------------------
# The max number of bytes which will be sent in any one call to syswrite
#-------------------------------------------------------------------------------
has 'chunk_size' => (
    is        => 'rw',
    isa       => 'Int',
    default   => 4096,
);

#-------------------------------------------------------------------------------
# Stores the last error generated, if any
#-------------------------------------------------------------------------------
has 'last_error' => (
    is        => 'rw',
    isa       => 'Str',
    clearer   => 'clear_last_error',
    predicate => 'has_error',
);

#-------------------------------------------------------------------------------
# Returns a string version of this connection. The return value is guaranteed
# to be unique to any run of an application (it includes the stringified object
# reference, including its memory address).
#-------------------------------------------------------------------------------
sub address {
    my $self = shift;

    if ($self->is_connected
     && $self->handle->isa('IO::Socket::INET')
     && $self->handle->can('peername'))
    {
        my ($err, $host, $port) = getnameinfo($self->handle->peername, NI_NUMERICSERV);
        return sprintf('sock<%s:%s %s>', $host, $port, $self);
    } elsif (defined $self->handle) {
        return sprintf('file<fd:%s %s>', $self->handle->fileno, $self);
    } else {
        return sprintf('none<%s>', $self);
    }
}


no Moose;
__PACKAGE__->meta->make_immutable;

1;