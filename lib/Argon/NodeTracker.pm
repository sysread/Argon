#-------------------------------------------------------------------------------
# Tracks the length of time it takes to process requests for a node. Used by
# Argon::Cluster to monitor Node responsiveness.
#-------------------------------------------------------------------------------
package Argon::NodeTracker;

use strict;
use warnings;
use Carp;

use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

use Time::HiRes qw/time/;

#-------------------------------------------------------------------------------
# The length of tracking history to keep.
#-------------------------------------------------------------------------------
has 'tracking' => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

#-------------------------------------------------------------------------------
# The number of workers a node has.
#-------------------------------------------------------------------------------
has 'workers' => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

#-------------------------------------------------------------------------------
# The total number of requests this node has served.
#-------------------------------------------------------------------------------
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

#-------------------------------------------------------------------------------
# Stores the last <tracking> request timings.
#-------------------------------------------------------------------------------
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

#-------------------------------------------------------------------------------
# Hash of pending requests (msgid => tracking start time).
#-------------------------------------------------------------------------------
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

#-------------------------------------------------------------------------------
# Avg processing time, calculated after each request completes.
#-------------------------------------------------------------------------------
has 'avg_proc_time' => (
    is       => 'rw',
    isa      => 'Num',
    init_arg => undef,
    default  => 0,
);

#-------------------------------------------------------------------------------
# Begins tracking a request.
#-------------------------------------------------------------------------------
sub start_request {
    my ($self, $msg_id) = @_;
    $self->set_pending($msg_id, time);
    $self->inc_requests;
}

#-------------------------------------------------------------------------------
# Completes tracking for a request and updates tracking stats.
#-------------------------------------------------------------------------------
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

#-------------------------------------------------------------------------------
# Returns the current capacity (workers - pending requests).
#-------------------------------------------------------------------------------
sub capacity {
    my $self = shift;
    return $self->workers - $self->num_pending;
}

#-------------------------------------------------------------------------------
# Returns the estimated time it would take to process a task, based on the
# number of pending tasks for this node and the average processing time.
#-------------------------------------------------------------------------------
sub est_proc_time {
    my $self = shift;
    return $self->avg_proc_time * ($self->num_pending + 1);
}

;
__PACKAGE__->meta->make_immutable;

1;