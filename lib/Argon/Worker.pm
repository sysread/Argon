#-------------------------------------------------------------------------------
# Argon::Worker implements a worker process that processes the payload of a
# Message and returns the results. Workers receive their input in the same
# line-oriented format as MessageProcessors do, except that they read their
# input synchronously from STDIN. Similarly, the result of their work is sent
# to STDOUT in the same fashion.
#
# This means that Workers may only handle a single task at a time. Workers do
# not queue tasks themselves. It is the responsibility of the process spawning
# the worker to track and manage the worker's input and output.
#-------------------------------------------------------------------------------
package Argon::Worker;

use Moose;
use Carp;
use namespace::autoclean;
use Argon          qw/:commands EOL/;
use Argon::Message qw//;

has 'endline' => (
    is       => 'ro',
    isa      => 'Str',
    default  => EOL,
);

has 'shutdown' => (
    is       => 'rw',
    isa      => 'Boolean',
    default  => 0,
    init_arg => undef,
);

has 'handler' => (
    is       => 'ro',
    isa      => 'HashRef',
    builder  => '_build_dispatch_table',
    init_arg => undef,
);

#-------------------------------------------------------------------------------
# Builds the dispatch table used by dispatch() to route messages to handler
# methods.
#-------------------------------------------------------------------------------
sub _build_dispatch_table {
    my $self = shift;
    return { 
        CMD_SHUTDOWN, 'handle_shutdown',
    };
}

#-------------------------------------------------------------------------------
# Begins the core loop of the worker process.
#-------------------------------------------------------------------------------
sub loop {
    my $self = shift;
    local $| = 1; # enable auto-flush
    until ($self->shutdown) {
        my $message = Argon::Message::decode(<STDIN>);
        my $result  = $self->dispatch($message);
        print $result->encode . $self->endline;
    }
}

#-------------------------------------------------------------------------------
# Dispatches a message to another method based on its command.
#-------------------------------------------------------------------------------
sub dispatch {
    my ($self, $message) = @_;
    my $command = $message->command;
    my $handler = $self->handler->{$command};
    my $method  = $self->can($handler);

    if ($method) {
        return $self->$method->($message);
    } else {
        my $error = sprintf 'Command not handled: %s', $message->command;
        my $response = $method->reply(CMD_ERROR);
        $response->set_payload($error);
        return $response;
    }
}

#-------------------------------------------------------------------------------
# Configures worker to exit the work loop.
#-------------------------------------------------------------------------------
sub handle_shutdown {
    my $self = shift;
    $self->shutdown(1);
}

__PACKAGE__->meta->make_immutable;

1;