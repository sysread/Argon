#-------------------------------------------------------------------------------
# 
#-------------------------------------------------------------------------------
package Argon::Queue;

use strict;
use warnings;
use Carp;
use namespace::autoclean;

use Coro;
use Time::HiRes qw/time/;
use Argon       qw/:priorities LOG/;

sub new {
    my ($class, %param) = @_;
    my $limit = $param{limit};
    my $check = $param{check};
    my $self  = bless {
        queues     => [map {[]} (PRI_MAX .. PRI_MIN)], # store queue for each priority
        check      => $check,   # seconds (float) between reprioritization checks
        limit      => $limit,   # max items permitted in queue
        count      => 0,        # # of items currently in queue
        last_check => 0,        # time stamp of last reprioritization
        item       => {},       # hash of item to [item ref, priority, time added]
        sem        => Coro::Semaphore->new(0),
    }, $class;
}

sub is_empty { $_[0]->{count} == 0 }
sub is_full  { defined $_[0]->{limit} && $_[0]->{count} == $_[0]->{limit} }

sub _put {
    my ($self, $item, $priority) = @_;
    push @{$self->{queues}[$priority]}, $item;

    # Only record item if it can be given a higher priority
    $self->{item}{$item} = [$item, $priority, time]
        unless $priority == PRI_MAX;

    ++$self->{count};
    $self->{sem}->up;
}

sub put {
    my ($self, $item, $priority) = @_;
    $self->is_full && croak 'queue is full';
    !defined $priority && ($priority = PRI_NORMAL);
    $self->reprioritize;
    $self->_put($item, $priority);
    return $self->{count};
}

sub get {
    my $self = shift;
    $self->reprioritize;
    $self->{sem}->down;

    foreach my $pri (PRI_MAX .. PRI_MIN) {
        if (@{$self->{queues}[$pri]} > 0) {
            my $item = shift @{$self->{queues}[$pri]};
            delete $self->{item}{$item};
            --$self->{count};
            return $item;
        }
    }

    return;
}

sub reprioritize {
    my $self = shift;
    my $now  = time;

    return unless defined $self->{check}
               && $now >= $self->{last_check} + $self->{check};

    my @msgids = grep { $now - $self->{item}{$_}[2] >= $self->{check} }
                 keys %{$self->{item}};

    my %prune;
    @prune{@msgids} = (1) x @msgids;
    foreach my $pri (PRI_MIN .. PRI_MAX) {
        $self->{queues}[$pri] = [ grep { !$prune{$_} } @{$self->{queues}[$pri]} ];
    }

    $self->{count} -= scalar @msgids;

    foreach my $msgid (@msgids) {
        $self->_put(
            $self->{item}{$msgid}[0],
            $self->{item}{$msgid}[1] - 1,
        );

        delete $self->{item}{$msgid};
    }

    $self->{last_check} = $now;
}

1;