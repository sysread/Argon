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
use Argon                qw/:commands LOG EOL/;
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

has 'stdin' => (
    is       => 'rw',
    init_arg => undef,
);

has 'stdout' => (
    is       => 'rw',
    init_arg => undef,
);

has 'stderr' => (
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
    my $self = shift;
    my $eol  = $self->endline;

    my $proc = AnyEvent::Subprocess->new(
        delegates => [qw/StandardHandles/],
        code      => sub {
            my $worker = Argon::Worker->new(eol => $eol);
            $worker->loop;
            exit 0;
        },
    );

    my $run = $proc->run;
    $self->process($proc);
    $self->stdin($run->delegate('stdin')->handle);
    $self->stdout($run->delegate('stdout')->handle);
    $self->stderr($run->delegate('stderr')->handle); # TODO add listener and LOG messages

    $self->stderr->on_read(sub {
        my @start_request;

        @start_request = (
            line => sub {
                my ($handle, $line, $eol) = @_;
                warn "$line\n"; # re-emit stderr lines
                $self->stderr->push_read(@start_request);
            }
        );

        $self->stderr->push_read(@start_request);
    });
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
    Carp::confess unless $message;

    $self->pending($message->id);

    $self->stdout->push_read(line => sub {
        my ($handle, $line, $eol) = @_;
        my $response = Argon::Message::decode($line);
        $self->clear_pending; # TODO check that response message id matches pending
        $callback->($response);
    });

    $self->stdin->push_write($message->encode . $self->endline);
}



__PACKAGE__->meta->make_immutable;

1;