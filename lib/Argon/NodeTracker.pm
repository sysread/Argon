package Argon::NodeTracker;

use strict;
use warnings;
use Carp;

use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

use Time::HiRes qw/time/;

has 'tracking' => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

has 'requests' => (
    is       => 'ro',
    isa      => 'Int',
    init_arg => undef,
    default  => 0,
    traits   => ['Counter'],
    handles  => {
        'inc_requests' => 'inc',
    }
);

has 'history' => (
    is       => 'ro',
    isa      => 'ArrayRef[Num]',
    init_arg => undef,
    default  => sub {[]},
    traits   => ['Array'],
    handles  => {
        add_history    => 'push',
        del_history    => 'shift',
        len_history    => 'count',
        reduce_history => 'reduce',
    }
);

has 'pending' => (
    is       => 'ro',
    isa      => 'HashRef[Num]',
    init_arg => undef,
    default  => sub {{}},
    traits   => ['Hash'],
    handles  => {
        set_pending => 'set',
        get_pending => 'get',
        del_pending => 'delete',
        num_pending => 'count',
    }
);

has 'avg_proc_time' => (
    is       => 'rw',
    isa      => 'Num',
    init_arg => undef,
    default  => 0,
);

sub start_request {
    my ($self, $msg_id) = @_;
    $self->set_pending($msg_id, time);
}

sub end_request {
    my ($self, $msg_id) = @_;
    my $taken = time - $self->get_pending($msg_id);

    $self->del_pending($msg_id);
    $self->add_history($taken);

    if ($self->len_history > $self->tracking) {
        my $to_delete = $self->len_history - $self->tracking;
        $self->del_history foreach 1 .. $to_delete;
    }

    my $sum  = $self->reduce_history(sub { $_[0] + $_[1] });
    $self->avg_proc_time($sum / $self->len_history);
}

sub est_proc_time {
    my $self = shift;
    return $self->avg_proc_time * ($self->num_pending + 1);
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;