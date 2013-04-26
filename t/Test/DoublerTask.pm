#-------------------------------------------------------------------------------
# Trivial task class used by unit tests
#-------------------------------------------------------------------------------
package Test::DoublerTask;

use strict;
use warnings;
use Carp;

use Moose;
use namespace::autoclean;

with 'Argon::Role::Task';

has 'n' => (is => 'rw', isa => 'Num');

sub run {
    my $self = shift;
    return $self->n * 2;
}

__PACKAGE__->meta->make_immutable;

1;