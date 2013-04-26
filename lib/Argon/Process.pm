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
    predicate => 'is_running',
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
#
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
#
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
#
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
    $stderr->timeout(3); # allow a bit of time for the process to launch
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
#
#-------------------------------------------------------------------------------
sub kill {
    my $self = shift;
    my $pid = $self->pid;

    if ($self->is_running) {
        if ($self->pid) {
            kill(0, $pid)
                && kill(9, $pid)
                || $!{ESRCH}
                || ERROR("Error killing pid %d: %s", $pid, $!);
        
            while ($pid > 0) {
                $pid = waitpid($pid, WNOHANG);
                if ($pid > 0) {
                    Coro::AnyEvent::sleep(0.1);
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
