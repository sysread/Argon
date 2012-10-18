package Argon::MessageQueue;

use strict;
use warnings;
use Carp;
use POSIX      qw/floor/;
use List::Util qw/max/;

use fields qw/limit size data/;

sub new {
    my ($class, %param) = @_;
    my $limit = $param{limit} || croak 'Expected "limit"';
    my $self  = fields::new($class);
    $self->{limit} = $limit;
    $self->{size}  = 0;
    $self->{data}  = [];
    return $self;
}

sub parent { floor(($_[0] - 1) / 2) }
sub left   { (2 * $_[0]) + 1 }
sub right  { (2 * $_[0]) + 2 }

sub size     { $_[0]->{size} }
sub fill     { ($_[0]->{size} / $_[0]->{limit}) * 100 }
sub is_full  { $_[0]->{size} >= $_[0]->{limit} }
sub is_empty { $_[0]->{size} == 0 }

sub put {
    my ($self, $msg) = @_;
    croak 'Queue is full' if $self->is_full;

    my $data = $self->{data};

    push @$data, $msg;
    ++$self->{size};

    my $idx    = $self->{size} - 1;
    my $parent = parent($idx);

    while ($idx > 0 && $data->[$idx] > $data->[$parent]) {
        my $tmp = $data->[$parent];
        $data->[$parent] = $data->[$idx];
        $data->[$idx]    = $tmp;

        $idx = $parent;
        $parent = parent($idx);
    }

    return $self->{size};
}

sub get {
    my $self = shift;
    croak 'Queue is empty' if $self->is_empty;

    my $data = $self->{data};
    my $msg  = shift @$data;

    # Replace root of heap with last element on the heap
    unshift @$data, pop @$data;
    --$self->{size};
    
    # Sift down
    my $last_idx = $self->{size} - 1;
    my $idx      = 0;
    my $left     = left($idx);
    my $right    = right($idx);
    
    while ($idx < $last_idx) {
        my $min;
        if ($left > $last_idx && $right > $last_idx) {
           last;
        } elsif ($left > $last_idx) {
            $min = $right;
        } elsif ($right > $last_idx) {
            $min = $left;
        } else {
            $min = ($data->[$left] >= $data->[$right])
                ? $left
                : $right;
        }
        
        if ($data->[$idx] < $data->[$min]) {
            my $tmp = $data->[$min];
            $data->[$min] = $data->[$idx];
            $data->[$idx] = $tmp;

            $idx   = $min;
            $left  = left($idx);
            $right = right($idx);
        } else {
            last;
        }
    }

    return $msg;
}

1;