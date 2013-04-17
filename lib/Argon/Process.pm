package Argon::Process;

use strict;
use warnings;
use Carp;

use Moose;
use Coro;
use AnyEvent::Util qw/fh_nonblocking/;
use Cwd            qw/abs_path/;
use POSIX          qw/:sys_wait_h/;
use IPC::Open2     qw/open2/;
use IPC::Open3     qw/open3/;
use String::Escape qw/quote singlequote backslash/;
use File::Spec     qw//;
use Symbol         qw/gensym/;
use Argon          qw/:logging/;
use Argon::Stream;

has 'class' => (
    is        => 'ro',
    isa       => 'Str',
    required  => 1,
);

has 'args' => (
    is        => 'ro',
    isa       => 'ArrayRef',
    required  => 0,
);

has 'inc' => (
    is        => 'ro',
    isa       => 'ArrayRef',
    required  => 0,
);

has 'proc' => (
    is        => 'rw',
    init_arg  => undef,
    clearer   => 'unset_proc',
    predicate => 'is_running',
);

has 'stream' => (
    is        => 'rw',
    isa       => 'Argon::Stream',
    init_arg  => undef,
    clearer   => 'unset_stream',
    handles   => {
        send         => 'send',
        send_message => 'send_message',
    }
);

sub command {
    return abs_path($^X);
}

sub includes {
    my $self   = shift;
    my @inc    = map { sprintf("-I %s", backslash($_)) } @INC, @{$self->inc};
    my ($vol, $dir, $file) = File::Spec->splitpath($0);
    push @inc, "-I $dir";
    return @inc;
}

sub code {
    my $self   = shift;
    my $class  = $self->class;
    my $params = join ',', map { quote($_) } @{$self->args};
    return sprintf '$| = 1; require %s; my $o = %s->new(%s); $o->run();', $class, $class, $params;
}

sub spawn {
    my $self = shift;
    $self->is_running and croak 'process is already running';

    pipe(my $child_in, my $child_out);
    my $child_err = gensym;

    my $e    = sprintf '-e %s', singlequote($self->code);
    my $cmd  = join ' ', command, $self->includes, $e;
    my $proc = open2($child_in, $child_out, $cmd) or croak $?;

    $self->proc($proc);
    $self->stream(Argon::Stream->new(in_fh => $child_in, out_fh => $child_out));

=cut
    # Start thread to route stderr msgs locally
    async {
        while (1) {
            INFO 'Waiting on STDERR data';
            Coro::AnyEvent::readable $child_err;
            my $line = <$child_err>;
            warn $line;
        }
    };
=cut
    return 1;
}

sub kill_child {
    my ($self, $wait) = @_;
    $self->is_running or croak 'process is not running';

    kill 9, $self->proc;

    $self->unset_proc;
    $self->unset_stream;
}

sub wait_child {
    my $self = shift;
    waitpid $self->proc, 0;
}

sub DEMOLISH {
    my $self = shift;
    $self->kill_child(1);
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;