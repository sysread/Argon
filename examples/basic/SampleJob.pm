package SampleJob;

use strict;
use warnings;
use Carp;
use Argon  qw/LOG/;

use fields qw/value/;

sub new {
    my ($class, $value) = @_;
    my $self = fields::new($class);
    $self->{value} = $value;
    return $self;
}

sub run {
    my $self = shift;
    LOG("Doubling %04d", $self->{value});
    return $self->{value} * 2;
}

1;