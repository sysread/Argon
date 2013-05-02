#-------------------------------------------------------------------------------
# Argon::Queue wraps Coro::PrioChannel, changing the behavior slightly. The
# queue specifies a maximum size, after which attempts to `put` items into the
# queue will cause `put` to croak.
#-------------------------------------------------------------------------------
package Argon::Queue;

use strict;
use warnings;
use Carp;

use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

use Coro::PrioChannel;
use Argon qw/:priorities/;

#-------------------------------------------------------------------------------
# Max number of items permitted in the queue.
#-------------------------------------------------------------------------------
has 'max_size' => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

#-------------------------------------------------------------------------------
# Current count of items in the queue
#-------------------------------------------------------------------------------
has 'count' => (
    is       => 'rw',
    isa      => 'Int',
    init_arg => undef,
    default  => 0,
    traits   => ['Counter'],
    handles  => {
        inc_count => 'inc',
        dec_count => 'dec',
    }
);

#-------------------------------------------------------------------------------
# Coro::PrioChannel instance
#-------------------------------------------------------------------------------
has 'queue' => (
    is       => 'ro',
    isa      => 'Coro::PrioChannel',
    init_arg => undef,
    default  => sub { Coro::PrioChannel->new },
);

#-------------------------------------------------------------------------------
# Predicates
#-------------------------------------------------------------------------------
sub is_full  { $_[0]->count == $_[0]->max_size }
sub is_empty { $_[0]->count == 0 }

#-------------------------------------------------------------------------------
# Places a new item into the queue. Croaks if the queue is already at its
# max_size number of elements.
#-------------------------------------------------------------------------------
sub put {
    my ($self, $item, $pri) = @_;
    $pri ||= PRI_NORMAL;
    croak 'queue is full' if $self->is_full;
    $self->queue->put($item, $pri);
    $self->inc_count;
}

#-------------------------------------------------------------------------------
# Retrieves the next item from the queue. If necessary, blocks until one is
# available.
#-------------------------------------------------------------------------------
sub get {
    my $self = shift;
    my $item = $self->queue->get;
    $self->dec_count;
    return $item;
}

__PACKAGE__->meta->make_immutable;

1;