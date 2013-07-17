package Argon::Process;

use strict;
use warnings;
use Carp;

use Moose;
use MooseX::StrictConstructor;
use namespace::autoclean;

use Config;
use Coro;
use Coro::Handle   qw/unblock/;
use IPC::Open3     qw/open3/;
use POSIX          qw/:sys_wait_h/;
use String::Escape qw/backslash qqbackslash/;
use Symbol         qw/gensym/;
use Time::HiRes    qw//;

use Argon::Stream  qw//;
use Argon          qw/:logging/;

# Extra args to be passed to the perl interpreter
has 'args' => (
    is        => 'rw',
    isa       => 'ArrayRef',
    predicate => 'has_extra_args',
);

has 'pid' => (
    is        => 'rw',
    isa       => 'Int',
    init_arg  => undef,
    predicate => 'has_pid',
    clearer   => 'clear_pid',
);

has 'stream' => (
    is        => 'rw',
    isa       => 'Argon::Stream',
    init_arg  => undef,
    clearer   => 'clear_stream',
    handles   => {
        process => 'send',
    }
);

has 'stderr' => (
    is        => 'rw',
    isa       => 'Coro::Handle',
    init_arg  => undef,
    clearer   => 'clear_stderr',
);

#-------------------------------------------------------------------------------
# Ensures that the child process is killed when the parent process is destroyed.
#-------------------------------------------------------------------------------
sub DEMOLISH {
    my $self = shift;
    $self->kill(1);
}

#-------------------------------------------------------------------------------
# Returns true if process is currently running.
#-------------------------------------------------------------------------------
sub is_running {
    my $self = shift;
    return $self->has_pid
        && kill(0, $self->pid)
        && !$!{ESRCH};
}

#-------------------------------------------------------------------------------
# Return the full path to the perl binary used to launch the parent in order to
# ensure that children are run on the same perl version.
#-------------------------------------------------------------------------------
sub get_command_path {
    my $self = shift;
    my $perl = $Config{perlpath};
    my $ext  = $Config{_exe};
    $perl .= $ext
        if $^O ne 'VMS'
        && $perl !~ /$ext$/i;
    return $perl;
}

#-------------------------------------------------------------------------------
# Returns a string of parameters that will be passed to the perl executable.
# These include any user-specified arguments passed to the constructor as well
# as the include paths for the currently executing perl interpreter.
#-------------------------------------------------------------------------------
sub get_args {
    my $self  = shift;
    my @inc   = map { sprintf('-I%s', backslash($_)) } @INC;
    my $cmd   = '-MArgon::Worker -e "my \$w = Argon::Worker->new; \$w->loop;"';
    my @extra = $self->has_extra_args
        ? map { backslash($_) } @{$self->args}
        : ();

    return join ' ', @extra, @inc, $cmd;
}

#-------------------------------------------------------------------------------
# Executes the child process and configures streams and handles for IPC. Also
# starts loop that forwards STDERR data from the child to the current process
# (for logging).
#
# Croaks (as well as emitting log entries) on failure.
#-------------------------------------------------------------------------------
sub spawn {
    my ($self) = @_;
    my ($r, $w, $e) = (gensym, gensym, gensym);
    my $cmd  = $self->get_command_path;
    my $args = $self->get_args;
    my $exec = "$cmd $args";
    my $pid  = open3($w, $r, $e, $exec)
        or croak "Error spawning process: $!";

    my $reader = unblock $r;
    my $writer = unblock $w;
    my $stderr = unblock $e;
    my $stream = Argon::Stream->new(
        in_chan  => $reader,
        out_chan => $writer,
    );

    # Test that process spawned correctly
    $stderr->timeout(10); # allow a bit of time for the process to launch
    my $line = $stderr->readline($Argon::EOL);
    if (!defined $line || $line !~ /Worker process starting/) {
        ERROR 'Worker error: %s', $line;

        # Report any additional lines of stderr
        $stderr->timeout(1); # no need for a longer timeout here
        my @stderr = ($line);
        while ($line = $stderr->readline) {
            last unless defined $line;
            ERROR 'Worker error: %s', $line;
            push @stderr, $line;
        }

        # Kill failed process
        kill(9, $pid);
        croak join("\n", @stderr);
    }

    # Reset timeout
    $stderr->timeout(undef);

    # Configure internals
    $self->stream($stream);
    $self->stderr($stderr);
    $self->pid($pid);

    # Forward spawned process' STDERR messages to this process' logs
    async { warn $self->stderr->readline("\n") while 1 }

    return $pid;
}

#-------------------------------------------------------------------------------
# Kills the child process. Returns after the process has been reaped. If the
# process is not running, returns immediately. If the optional second parameter
# is provided and is true, this method will block the program until it has
# finished (the default behavior is to yield while waiting for the child
# process to die).
#-------------------------------------------------------------------------------
sub kill {
    my ($self, $block) = @_;

    if ($self->is_running) {
        my $pid = $self->pid;
        if ($pid) {
            if (kill(0, $pid)) {
                ERROR("Error killing pid %d: %s", $pid, $!)
                    unless kill(9, $pid) || $!{ESRCH};
            }

            if ($block) {
                waitpid($pid, 0);

            } else {
                while ($pid > 0) {
                    $pid = waitpid($pid, WNOHANG);
                    Coro::AnyEvent::sleep(0.1)
                        if $pid > 0;
                }
            }
        }

        $self->stream->close;
        $self->stderr->close;

        $self->clear_pid;
        $self->clear_stream;
        $self->clear_stderr;
    }

    return 1;
}

__PACKAGE__->meta->make_immutable;

1;

=pod

=head1 NAME

Argon::Process

=head1 SYNOPSIS

    use Argon::Process;

    my $proc = Argon::Process->new();
    $proc->spawn;

    my $result = $proc->process($msg);

    $proc->kill;

=head1 DESCRIPTION

Argon::Process implements external Perl processes (Argon::Workers) in a
platform-independent way.

=head1 METHODS

=head2 new(args => [...])

Creates a new Argon::Process. The process object is then ready to be launched
using C<spawn()>.

Optional parameter C<args> may be passed to specify command-line arguments to
the Perl interpreter.

=head2 is_running()

Returns true if the process has been launched as is currently running.

=head2 spawn()

Launches the external Perl process and waits for it to connect back. Throws an
error if unable to launch the process or if the process itself does not launch
correctly. Returns the PID of the newly created process.

=head2 process($msg)

Sends an Argon::Message to the process. The message will be processed and the
results returned to the caller. This method yields to the loop then returns the
resulting Argon::Message received from the child process.

=head2 kill([1])

Kills the process and returns once complete. If the optional second parameter is
specified, this method will block execution until the process has been reaped.
The default behavior is to yield and sleep until the process has been reaped.

=head1 AUTHOR

Jeff Ober L<mailto:jeffober@gmail.com>

=head1 LICENSE

BSD license

=cut
