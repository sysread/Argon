#-------------------------------------------------------------------------------
# 
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

sub spawn {
    my $self = shift;
    my $eol  = $self->eol;
    my $proc = AnyEvent::Subprocess->new(
        delegates => [qw/StandardHandles/],
        on_completion => sub {
            die 'bad exit status'
                unless $_[0]->is_success;
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
# NOTE: because the worker is synchronous, the stacking of push_write/push_read
# can simply pair sends with recvs configured for the particular send.
#-------------------------------------------------------------------------------
sub send {
    my ($self, $message, $callback) = @_;
    $self->delegate->('stdin')->push_write($message->encode . $self->eol);
    $self->delegate->('stdout')->push_read(line => sub {
        my ($handle, $line, $eol) = @_;
        my $response = Argon::Message::decode($line);
        $callback->($response);
    });
}



__PACKAGE__->meta->make_immutable;

1;