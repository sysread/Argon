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
use Data::Dumper   qw//;
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
        CMD_QUEUE,    'handle_queue',
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
        my $result = eval { $self->$method->($message) };
        if ($@) {
            my $error = $@;
            my $reply = $message->reply(CMD_ERROR);
            $reply->set_payload($error);
            return $reply;
        } else {
            return $result;
        }
    } else {
        my $error = sprintf 'Command not handled: %s', $message->command;
        my $reply = $method->reply(CMD_ERROR);
        $reply->set_payload($error);
        return $reply;
    }
}

#-------------------------------------------------------------------------------
# Configures worker to exit the work loop.
#-------------------------------------------------------------------------------
sub handle_shutdown {
    my ($self, $message) = @_;
    $self->shutdown(1);
    return $message->reply(CMD_ACK);
}

#-------------------------------------------------------------------------------
# Processes a message as a work unit. A work unit is defined as an instance of
# a class supporting a "run" method.
#-------------------------------------------------------------------------------
sub handle_queue {
    my ($self, $message) = @_;
    my $payload = $message->get_payload;
    my $result  = eval { $payload->run };
    
    if ($@) {
        my $error = $@;
        my $reply = $message->reply(CMD_ERROR);
        $reply->set_payload($error);
        return $reply;
    } else {
        return $result;
    }
}

__PACKAGE__->meta->make_immutable;

1;