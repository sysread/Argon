#-------------------------------------------------------------------------------
# Inbound channel for IO.
#-------------------------------------------------------------------------------
package Argon::IO::InChannel;

use strict;
use warnings;
use Carp;

use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

use Coro;
use Coro::Channel   qw//;
use Coro::AnyEvent  qw//;
use AnyEvent::Util  qw/fh_nonblocking/;
use Scalar::Util    qw/weaken/;
use FSA::Rules      qw//;
use Errno           qw/EAGAIN/;
use Argon           qw/:logging/;
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
                rules => [ WAIT => 1 ],
            },
            WAIT => {
                do    => \&state_wait,
                rules => [
                    ERROR => sub { !defined shift->message },
                    READ  => sub {  shift->message         },
                    WAIT  => sub { !shift->message         },
                ],
            },
            READ => {
                do    => \&state_read,
                rules => [
                    WAIT         => sub { shift->message eq Argon::IO::Channel::COMPLETE     },
                    READ         => sub { shift->message eq Argon::IO::Channel::CONTINUE     },
                    ERROR        => sub { shift->message eq Argon::IO::Channel::ERROR        },
                    DISCONNECTED => sub { shift->message eq Argon::IO::Channel::DISCONNECTED },
                ],
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

has 'inbox' => (
    is        => 'rw',
    isa       => 'Coro::Channel',
    init_arg  => undef,
    default   => sub { Coro::Channel->new },
    clearer   => 'clear_inbox',
    handles   => {
        receive => 'get',
    }
);

has 'buffer' => (
    is        => 'rw',
    isa       => 'ScalarRef',
    init_arg  => undef,
    default   => sub { my $buf = ''; \$buf },
    clearer   => 'clear_buffer',
);

has 'offset' => (
    is        => 'rw',
    isa       => 'Int',
    init_arg  => undef,
    default   => 0,
    traits    => ['Counter'],
    handles   => {
        inc_offset   => 'inc',
        dec_offset   => 'dec',
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
# Wait state
#-------------------------------------------------------------------------------
sub state_wait {
    my $state = shift;
    my $self  = instance($state);
    $self->read_messages;
    async {
        my $result = Coro::AnyEvent::readable($self->handle, $Argon::TIMEOUT);
        $state->message($result);
        $self->state->switch;
    };
}

#-------------------------------------------------------------------------------
# Read state
#-------------------------------------------------------------------------------
sub state_read {
    my $state = shift;
    my $self  = instance($state);
    my $bytes = sysread(
        $self->handle,
        ${$self->buffer},
        $self->chunk_size,
        $self->offset,
    );

    # I/O Error
    if (!defined $bytes) {
        if ($! == EAGAIN) {
            $state->message(Argon::IO::Channel::CONTINUE);
        } else {
            $self->last_error($!);
            $state->message(Argon::IO::Channel::ERROR);
        }
    }
    # Disconnect
    elsif ($bytes == 0) {
        $self->last_error('disconnected');
        $state->message(Argon::IO::Channel::DISCONNECTED);
    }
    # Bytes read
    else {
        $self->inc_offset($bytes);
        if ($self->read_messages == 0) {
            $state->message(Argon::IO::Channel::CONTINUE);
        } else {
            $state->message(Argon::IO::Channel::COMPLETE);
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
# Awakens any threads waiting on a read and resets internal structures.
#-------------------------------------------------------------------------------
sub reset {
    my $self = shift;

    close $self->handle;
    $self->inbox->shutdown;

    $self->clear_handle;
    $self->clear_inbox;
    $self->clear_buffer;

    $self->offset(0);
    $self->inbox(Coro::Channel->new(1));

    my $buf = '';
    $self->buffer(\$buf);
}

#-------------------------------------------------------------------------------
# Reads messages out of the buffer and places them into the inbox.
#-------------------------------------------------------------------------------
sub read_messages {
    my $self = shift;
    my $msgs = 0;

    while ((my $index = index ${$self->buffer}, $Argon::EOL) != -1) {
        my $msg = substr ${$self->buffer}, 0, $index;
        my $len = $index + length($Argon::EOL);
        substr(${$self->buffer}, 0, $len) = '';
        $self->inbox->put($msg);
        $self->dec_offset($len);
        ++$msgs;
    }
    
    return $msgs;
}

#-------------------------------------------------------------------------------
# Returns true if the channel is in a valid connection state.
#-------------------------------------------------------------------------------
sub is_connected {
    my $self  = shift;
    my $state = $self->state->curr_state->name;
    return $state ne 'DISCONNECTED'
        && $state ne 'ERROR'
        && $state ne 'DONE';
}

__PACKAGE__->meta->make_immutable;

1;