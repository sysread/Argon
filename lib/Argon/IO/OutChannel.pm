#-------------------------------------------------------------------------------
# Outbound channel for IO.
#-------------------------------------------------------------------------------
package Argon::IO::OutChannel;

use strict;
use warnings;
use Carp;

use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

use Coro;
use Coro::Channel  qw//;
use Coro::AnyEvent qw//;
use AnyEvent::Util qw/fh_nonblocking/;
use Scalar::Util   qw/weaken/;
use FSA::Rules;
use Argon::IO::Channel;

extends 'Argon::IO::Channel';

#-------------------------------------------------------------------------------
# Stores the state object
#-------------------------------------------------------------------------------
has 'state' => (
    is        => 'ro',
    isa       => 'FSA::Rules',
    init_arg  => undef,
    default   => sub {
        FSA::Rules->new(
            READY => {
                do    => \&state_ready,
                rules => [ BUFFER => 1 ],
            },
            BUFFER => {
                do    => \&state_buffer,
                rules => [
                    WAIT  => sub { !shift->message },
                    ERROR => sub {  shift->message },
                ],
            },
            WAIT => {
                do    => \&state_wait,
                rules => [
                    WRITE => sub { !shift->message },
                    ERROR => sub {  shift->message },
                ],
            },
            WRITE => {
                do    => \&state_write,
                rules => [
                    WAIT         => sub { defined $_[0]->message && $_[0]->message eq Argon::IO::Channel::CONTINUE     },
                    BUFFER       => sub { defined $_[0]->message && $_[0]->message eq Argon::IO::Channel::COMPLETE     },
                    DISCONNECTED => sub { defined $_[0]->message && $_[0]->message eq Argon::IO::Channel::DISCONNECTED },
                    ERROR        => sub { defined $_[0]->message && $_[0]->message eq Argon::IO::Channel::ERROR        },
                ]
            },
            ERROR => {
                do    => \&state_error,
                rules => [ DONE => 1 ]
            },
            DISCONNECTED => {
                do    => \&state_disconnected,
                rules => [ DONE => 1 ]
            },
            DONE => {
                do    => \&state_done,
                rules => [ READY => 1 ],
            },
        );
    }
);

#-------------------------------------------------------------------------------
# Output buffer
#-------------------------------------------------------------------------------
has 'outbox' => (
    is        => 'rw',
    isa       => 'Coro::Channel',
    init_arg  => undef,
    default   => sub { Coro::Channel->new },
    handles   => {
        send         => 'put',
        next_message => 'get',
        wake_pending => 'shutdown',
    }
);

#-------------------------------------------------------------------------------
# Holds the current message
#-------------------------------------------------------------------------------
has 'current_message' => (
    is        => 'rw',
    isa       => 'Str',
    init_arg  => undef,
    clearer   => 'clear_current_message',
);

#-------------------------------------------------------------------------------
# Marks a location in current_message. Data after the mark has not yet been
# transmitted.
#-------------------------------------------------------------------------------
has 'current_offset' => (
    is        => 'rw',
    isa       => 'Int',
    init_arg  => undef,
    default   => 0,
    traits    => ['Counter'],
    handles   => {
        inc_offset   => 'inc',
        reset_offset => 'reset',
    }
);

#-------------------------------------------------------------------------------
# Initializes the state machine
#-------------------------------------------------------------------------------
sub BUILD {
    my $self = shift;
    $self->state->reset;
    $self->state->strict(1);
    $self->state->notes(object => $self);
    $self->state->start;
}

#-------------------------------------------------------------------------------
# Gets the instance from the current state
#-------------------------------------------------------------------------------
sub instance { shift->machine->notes('object') }

#-------------------------------------------------------------------------------
# Ready state (initial state)
#-------------------------------------------------------------------------------
sub state_ready {
    my $state = shift;
    my $self  = instance($state);
    croak 'expected "handle"' unless $self->has_handle;
    fh_nonblocking $self->handle, 1;
    $self->clear_last_error;
    $self->state->switch;
}

#-------------------------------------------------------------------------------
# Waits for data to show up in the output buffer
#-------------------------------------------------------------------------------
sub state_buffer {
    my $state = shift;
    my $self  = instance($state);
    async {
        my $msg = $self->next_message;
        $self->reset_offset;

        if (defined $msg) {
            $self->current_message($msg);
        } else {
            $state->message('outbox error');
        }

        $self->state->switch;
    };
}

#-------------------------------------------------------------------------------
# Waits for the handle to be writable
#-------------------------------------------------------------------------------
sub state_wait {
    my $state = shift;
    my $self = instance($state);
    $state->message(!defined Coro::AnyEvent::writable($self->handle));
    $self->state->switch;
}

#-------------------------------------------------------------------------------
# Writes any pending data to the handle. The next state message is determined
# by the result of syswrite:
#
#    0 bytes written (disconnect) => DISCONNECTED
#    undef (error = $!)           => ERROR
#    output partially written     => WAIT
#    output completely written    => BUFFER
#-------------------------------------------------------------------------------
sub state_write {
    my $state = shift;
    my $self  = instance($state);
    my $bytes = syswrite(
        $self->handle,
        $self->current_message,
        $self->chunk_size,
        $self->current_offset,
    );

    # Transmission error
    if (!defined $bytes) {
        $self->last_error($!);
        $state->message(Argon::IO::Channel::ERROR);
    }
    # Disconnection
    elsif ($bytes == 0) {
        $self->last_error('disconnected');
        $state->message(Argon::IO::Channel::DISCONNECTED);
    }
    # Bytes sent
    else {
        $self->inc_offset($bytes);
        if ($self->current_offset == length($self->current_message)) {
            $state->message(Argon::IO::Channel::COMPLETE);
        } else {
            $state->message(Argon::IO::Channel::CONTINUE);
        }
    }

    $self->state->switch;
}

#-------------------------------------------------------------------------------
# Error state
#-------------------------------------------------------------------------------
sub state_error {
    my $state = shift;
    my $self  = instance($state);
    $self->state->switch;
}

#-------------------------------------------------------------------------------
# Disconnected state
#-------------------------------------------------------------------------------
sub state_disconnected {
    my $state = shift;
    my $self  = instance($state);
    $self->state->switch;
}
#-------------------------------------------------------------------------------
# Terminal state
#-------------------------------------------------------------------------------
sub state_done {
    my $state = shift;
    my $self  = instance($state);
    $self->reset;
}

#-------------------------------------------------------------------------------
# Wakens any pending threads and resets internal state.
#-------------------------------------------------------------------------------
sub reset {
    my $self = shift;
    
    close $self->handle;
    $self->clear_handle;
    
    $self->wake_pending;
    
    $self->current_offset(0);
    $self->clear_current_message;
    $self->outbox(Coro::Channel->new);
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;