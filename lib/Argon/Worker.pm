#-------------------------------------------------------------------------------
# Argon::Worker sits in a loop, waiting for new jobs to show up and then
# processing them and sending the response back. It reads messages in from
# STDIN and writes responses back to STDOUT.
#
# Workers are not normally created directly. They are launched in a separate
# process by Argon::Process.
#-------------------------------------------------------------------------------
package Argon::Worker;

use strict;
use warnings;
use Carp;

use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

use Coro::Handle   qw/unblock/;
use Argon          qw/:commands :logging/;
use Argon::Stream  qw//;

#-------------------------------------------------------------------------------
# Runs the work processing loop for the worker process, reading new tasks off of
# the wire, executing them, and emiting the results back to the parent process.
#-------------------------------------------------------------------------------
sub loop {
    my $self = shift;
    my $exit_code = 0;

    INFO 'Worker process starting';

    my $reader = unblock \*STDIN;
    my $writer = unblock \*STDOUT;
    my $stream = Argon::Stream->new(in_chan => $reader, out_chan => $writer);

    # Listen for tasks
    while (1) {
        my $msg = $stream->receive;

        unless (defined $msg) {
            WARN 'Parent terminated connection';
            $exit_code = 1;
            last;
        }

        my $reply = $self->process_task($msg);
        $stream->send_message($reply);
    }

    INFO 'Exiting';
}

#-------------------------------------------------------------------------------
# Processes an individual task (in the worker process).
#-------------------------------------------------------------------------------
sub process_task {
    my ($self, $msg) = @_;

    my $result = eval {
        my ($class, $params) = @{$msg->get_payload};

        require UNIVERSAL::require;
        $class->require or die $@;

        unless ($class->does('Argon::Role::Task')) {
            croak 'Tasks must implement Argon::Role::Task';
        }

        my $instance = $class->new(@$params);
        $instance->run;
    };

    my $reply;
    if ($@) {
        my $error = $@;
        WARN 'Task error: %s', $@;
        $reply = $msg->reply(CMD_ERROR);
        $reply->set_payload($error);
    } else {
        $reply = $msg->reply(CMD_COMPLETE);
        $reply->set_payload($result);
    }

    return $reply;
}

__PACKAGE__->meta->make_immutable;

1;