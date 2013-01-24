package SampleJob;

use strict;
use warnings;
use Carp;
use Argon       qw/LOG/;
use Time::HiRes qw/sleep/;

use fields qw/value sleep/;

sub new {
    my ($class, $value, $sleep) = @_;
    my $self = fields::new($class);
    $self->{value} = $value || croak 'Expected value for first argument';
    $self->{sleep} = $sleep || 0;
    return $self;
}

sub run {
    my $self = shift;
    LOG("Doubling %04d", $self->{value});
    sleep $self->{sleep} if $self->{sleep};
    return $self->{value} * 2;
}

1;