#-------------------------------------------------------------------------------
# Client connection to an Argon::Node or Argon::Cluster.
#-------------------------------------------------------------------------------
package Argon::Client;

use strict;
use warnings;
use Carp;

use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

use Argon::Stream;
use Argon::Message;
use Argon qw/:logging :commands :priorities/;

#-------------------------------------------------------------------------------
# Remote host port
#-------------------------------------------------------------------------------
has 'port' => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

#-------------------------------------------------------------------------------
# Remote host name
#-------------------------------------------------------------------------------
has 'host' => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

#-------------------------------------------------------------------------------
# Argon::Stream managing the socket connection to the remote host
#-------------------------------------------------------------------------------
has 'stream' => (
    is       => 'rw',
    isa      => 'Argon::Stream',
    init_arg => undef,
);

#-------------------------------------------------------------------------------
# Connects the client to the remote host.
#-------------------------------------------------------------------------------
sub connect {
    my $self   = shift;
    my $stream = Argon::Stream->connect(
        host => $self->host,
        port => $self->port,
    );

    $self->stream($stream);
}

#-------------------------------------------------------------------------------
# Sends a message and waits for the response. If the message is rejected,
# continues to resend the message after longer and longer delays until it is
# accepted.
#-------------------------------------------------------------------------------
sub _retry {
    my ($self, $msg, $retries) = @_;
    my $attempts = 0;

    while (1) {
        ++$attempts;

        croak "failed after $retries retries"
            if defined $retries && $attempts > $retries;

        my $reply = $self->stream->send($msg);

        # If the task was rejected, sleep a short (but lengthening) amount of
        # time before attempting again.
        if ($reply->command == CMD_REJECTED) {
            my $sleep_time = log($attempts + 1) / log(10);
            Coro::AnyEvent::sleep($sleep_time);
        }
        else {
            return $reply;
        }
    }
}

#-------------------------------------------------------------------------------
# Creates a new task and queues it on the connected network. Throws an error if
# the remote host is not connected. By default, there is no limit to the number
# of retries when the system is under load and a task is rejected. This may be
# controlled using the retries parameter.
#
# TODO support parameter "retries"
#-------------------------------------------------------------------------------
sub process {
    my ($self, %param) = @_;
    my $class    = $param{class}    || croak 'expected class';
    my $params   = $param{params}   || [];
    my $priority = $param{priority} || PRI_NORMAL;
    my $retries  = $param{retries};

    croak 'not connected' unless $self->stream;

    my $msg = Argon::Message->new(command => CMD_QUEUE);
    $msg->set_payload([$class, $params]);

    my $reply = $self->_retry($msg, $retries);
    if ($reply->command == CMD_COMPLETE) {
        return $reply->get_payload;
    } else {
        croak $reply->get_payload;
    }
}

__PACKAGE__->meta->make_immutable;

1;

=pod

=head1 NAME

Argon::Client

=head1 SYNOPSIS

    use Argon::Client;

    my $client = Argon::Client->new(port => 8000, host => 'some.host.name');
    $client->connect;
    my $result = $client->process(
        class  => 'Some::Class', # with Argon::Role::Task
        params => [ foo => 'bar', baz => 'bat' ],
    );

=head1 DESCRIPTION

Argon::Client provides a client connection to an Argon::Node or Argon::Cluster
instance and a simple API for sending tasks and retrieving the results.

=head1 METHODS

=head2 new(port => ..., host => ...)

Creates a new Argon::Client that will connect to I<host:port>. Port must be a
valid port number and host a valid hostname to which the current system can
connect.

=head2 connect()

Creates a connection to the remote host. An error is thrown if the connection
fails.

=head2 process(class => '...', params => [...], priority => PRI_HIGH)

Queues a task on the remote host and returns the results. If the task resulted
in an error, it is rethrown here. Otherwise, the result of calling the I<run>
method of the class passed as an argument. Params expects an array ref of
arguments to be passed to I<class>'s constructor (although they may be in the
form of hash arguments, e.g. C<[foo => 'bar']>).

By default, tasks are sent with a priority of C<PRI_NORMAL>. This may be
controlled via the I<priority> parameter.

Due to Argon's architecture, an overloaded system will reject tasks rather than
create a large backlog. When this happens, Argon::Client silently retries the
task indefinitely until it is accepted and completed. To control this behavior,
the optional parameter I<retries> may be specified to limit the number of
retries.

=head1 AUTHOR

Jeff Ober L<mailto:jeffober@gmail.com>

=head1 LICENSE

BSD license

=cut
