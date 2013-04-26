#-------------------------------------------------------------------------------
# 
#-------------------------------------------------------------------------------
package Argon::Queue;

use strict;
use warnings;
use Carp;

use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

use Coro::PrioChannel;

has 'max_size' => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

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

has 'queue' => (
    is       => 'ro',
    isa      => 'Coro::PrioChannel',
    init_arg => undef,
    default  => sub { Coro::PrioChannel->new },
);

sub is_full  { $_[0]->count == $_[0]->max_size }
sub is_empty { $_[0]->count == 0 }

sub put {
    my ($self, @params) = @_;
    croak 'queue is full' if $self->is_full;
    $self->queue->put(@params);
    $self->inc_count;
}

sub get {
    my $self = shift;
    my $item = $self->queue->get;
    $self->dec_count;
    return $item;    
}

__PACKAGE__->meta->make_immutable;

1;