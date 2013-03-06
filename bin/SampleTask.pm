package SampleTask;

use strict;
use warnings;
use Carp;

use Moose;
use Argon::Role::Task;
use Time::HiRes qw/sleep/;

with 'Argon::Role::Task';

has 'num'   => (is => 'ro', isa => 'Int');
has 'delay' => (is => 'ro', isa => 'Num', required => 0, default => 0);

sub run {
    my $self = shift;
    sleep $self->delay if $self->delay != 0;
    return $self->num * 2;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;