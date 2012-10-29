#-------------------------------------------------------------------------------
# Argon::WorkerProcess is the manager class for the code executed in an external
# perl process by Argon::Worker. Whereas Argon::Worker runs within the external
# process, this class provides the means by which the Argon::Worker process is
# spawned and assigned tasks.
#-------------------------------------------------------------------------------
package Argon::WorkerProcess;

use Moose;
use Carp;
use namespace::autoclean;
use AnyEvent::Handle     qw//;
use AnyEvent::Subprocess qw//;
use IPC::Open3           qw/open3/;
use Symbol               qw/gensym/;
use Argon                qw/:commands EOL/;
use Argon::Worker        qw//;

has 'endline' => (
    is       => 'ro',
    isa      => 'Str',
    default  => EOL,
);

has 'process' => (
    is       => 'rw',
    isa      => 'AnyEvent::Subprocess',
    init_arg => undef,
);

has 'delegate' => (
    is       => 'rw',
    init_arg => undef,
);

has 'pending' => (
    is        => 'rw',
    isa       => 'Str',
    init_arg  => undef,
    clearer   => 'clear_pending',
    predicate => 'has_pending',
);

sub spawn {
    my ($self, %param) = @_;
    my $on_success     = $param{on_success};
    my $on_error       = $param{on_error};
    my $eol            = $self->eol;

    my $proc = AnyEvent::Subprocess->new(
        delegates => [qw/StandardHandles/],
        on_completion => sub {
            my $cb = $_[0]->is_success ? $on_success : $on_error;
            $cb->($self) if ref $cb eq 'CODE';
        },
        code => sub {
            my $worker = Argon::Worker->new(eol => $eol);
            $worker->loop;
            exit 0;
        },
    );

    $self->process($proc);
    $self->delegate($proc->run);
}

#-------------------------------------------------------------------------------
# Sends a message to the worker process and applies $callback to the result.
# Note that only one message may be pending for a worker at any time. Attempting
# to send a message to a worker that is already processing a message will
# trigger an error.
#-------------------------------------------------------------------------------
sub send {
    my ($self, $message, $callback) = @_;
    croak 'Worker is busy' if $self->pending;
    $self->pending->($message->{id});
    $self->delegate->('stdin')->push_write($message->encode . $self->eol);
    $self->delegate->('stdout')->push_read(line => sub {
        my ($handle, $line, $eol) = @_;
        my $response = Argon::Message::decode($line);
        $self->clear_pending; # TODO check that response message id matches pending
        $callback->($response);
    });
}



__PACKAGE__->meta->make_immutable;

1;