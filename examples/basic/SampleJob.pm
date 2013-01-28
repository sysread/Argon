package SampleJob;
use Moose;
use Carp;
use Argon       qw/LOG/;
use Time::HiRes qw/sleep/;

with 'Argon::Role::Task';

has 'value' => (
    is       => 'rw',
    required => 1,
);

has 'sleep_for' => (
    is       => 'ro',
    isa      => 'Num',
    default  => 0,
    required => 0,
);

sub run {
    my $self = shift;
    LOG("Doubling %04d", $self->value);
    sleep $self->sleep_for if $self->sleep_for;
    return $self->value * 2;
}

no Moose;

1;