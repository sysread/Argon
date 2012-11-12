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
use Argon          qw/:commands LOG EOL/;
use Argon::Message qw//;

has 'endline' => (
    is       => 'ro',
    isa      => 'Str',
    default  => EOL,
);

has 'shutdown' => (
    is       => 'rw',
    isa      => 'Bool',
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
    LOG("Worker PID %d started", $$);

    until ($self->shutdown) {
        my $line     = <STDIN>;
        my $message  = Argon::Message::decode($line);
        my $response = eval { $self->dispatch($message) };

        if ($@) {
            my $error = $@;
            LOG($error);
            $response = $message->reply(CMD_ERROR);
            $response->set_payload($error);
        }

        print $response->encode . $self->endline;
    }
}

#-------------------------------------------------------------------------------
# Dispatches a message to another method based on its command.
#-------------------------------------------------------------------------------
sub dispatch {
    my ($self, $message) = @_;
    my $command = $message->command;
    my $handler = $self->handler->{$command};

    croak(sprintf 'Command not handled: %s', $message->command)
        unless $handler;

    return $self->$handler($message);
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
# TODO create WorkUnit class or similar to encapsulate work format of [class, [args, ...]]
#-------------------------------------------------------------------------------
sub handle_queue {
    my ($self, $message) = @_;
    my $payload = $message->get_payload;
    my ($class, $params) = @$payload;

    my $result = eval {
        require "$class.pm";
        $class->new(@$params)->run;
    };

    if ($@) {
        my $error = $@;
        my $reply = $message->reply(CMD_ERROR);
        $reply->set_payload($error);
        return $reply;
    } else {
        my $reply = $message->reply(CMD_COMPLETE);
        $reply->set_payload($result);
        return $reply;
    }
}

__PACKAGE__->meta->make_immutable;

1;