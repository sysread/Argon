package Argon::Worker;

use strict;
use warnings;
use Carp;

use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

use Coro           qw//;
use POSIX          qw/:sys_wait_h/;
use AnyEvent       qw//;
use AnyEvent::Util qw//;
use Time::HiRes    qw/sleep/;
use Argon          qw/:logging :commands/;
use Argon::Stream;
use Argon::IO::InChannel;
use Argon::IO::OutChannel;

# Nabbed from AnyEvent::Worker
our $FD_MAX = eval { POSIX::sysconf(&POSIX::_SC_OPEN_MAX) - 1 } || 1023;

has 'request_count' => (
    is       => 'ro',
    isa      => 'Int',
    init_arg => undef,
    default  => 0,
    traits   => ['Counter'],
    handles  => { inc => 'inc' },
);

has 'stream' => (
    is       => 'rw',
    isa      => 'Argon::Stream',
    init_arg => undef,
    clearer  => 'clear_stream',
);

has 'child_pid' => (
    is       => 'rw',
    isa      => 'Int',
    init_arg => undef,
    clearer  => 'clear_child_pid',
);

#-------------------------------------------------------------------------------
# Forwards message to child process for processing and returns the result. Also
# increments the request_count attribute.
#-------------------------------------------------------------------------------
sub process {
    my ($self, $msg) = @_;
    $self->inc;
    return $self->stream->send($msg);
}

#-------------------------------------------------------------------------------
# Starts the child process.
#-------------------------------------------------------------------------------
sub start {
    my $self = shift;
    my ($child, $parent) = AnyEvent::Util::portable_socketpair
        or croak "error creating pipe: $!";

    binmode $parent, ':raw';
    binmode $child,  ':raw';
    my $pid = fork;

    # Parent process
    if ($pid) {
        close $parent;
        AnyEvent::Util::fh_nonblocking $child, 1;
        $self->stream(Argon::Stream->create($child));
        $self->child_pid($pid);
    }
    # Child process
    elsif (defined $pid) {
        $SIG{INT} = 'IGNORE';

        # Close open handles (nabbed from AnyEvent::Worker)
        foreach my $fileno ($^F + 1 .. $FD_MAX) {
            unless ($fileno == $parent->fileno) {
                POSIX::close $fileno;
            }
        }

        # Kill all Coros apart from the child thread itself.
        Coro::killall;

        local $| = 1;
        AnyEvent::Util::fh_nonblocking $parent, 0;
        $parent->autoflush(1);

        my $exit_code = 0;

        while (my $line = do { local $/ = $Argon::EOL; <$parent> }) {
            unless (defined $line) {
                WARN 'Parent terminated connection';

                $exit_code = 1;
                last;
            }

            my $msg   = Argon::Message::decode($line);
            my $reply = $self->process_task($msg);

            $parent->print($reply->encode . $Argon::EOL);
            $parent->flush();
        }

        INFO 'Worker exiting';
        kill 9, $$ if AnyEvent::WIN32;
        POSIX::_exit $exit_code;
    }
    else {
        ERROR 'Error starting worker process: %s', $!;
        croak $!;
    }
}

#-------------------------------------------------------------------------------
# Processes an individual task (in the worker process).
#-------------------------------------------------------------------------------
sub process_task {
    my ($self, $msg) = @_;

    my $result = eval {
        my ($class, $params) = @{$msg->get_payload};
        require "$class.pm";

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

#-------------------------------------------------------------------------------
# Kills the worker process.
#-------------------------------------------------------------------------------
sub kill_child {
    my ($self, $wait) = @_;

    if ($self->child_pid) {
        my $pid = $self->child_pid;

        kill(0, $pid)
            && kill(9, $pid)
            || $!{ESRCH}
            || ERROR("Error killing pid %d: %s", $pid, $!);

        if ($wait) {
            while ($pid > 0) {
                $pid = waitpid($pid, WNOHANG);
                sleep 0.1 if $pid > 0;
            }
        }

        $self->clear_stream;
        $self->clear_child_pid;
    }
}

#-------------------------------------------------------------------------------
# Ensures that the child process is killed when the parent process is destroyed.
#-------------------------------------------------------------------------------
sub DEMOLISH {
    my $self = shift;
    $self->kill_child(1);
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
