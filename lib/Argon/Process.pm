package Argon::Process;

use strict;
use warnings;
use Carp;

use Moose;
use Coro;
use Cwd            qw/abs_path/;
use POSIX          qw/:sys_wait_h/;
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

has 'to_proc' => (
    is        => 'rw',
    init_arg  => undef,
    clearer   => 'unset_to_proc',
);

has 'from_proc' => (
    is        => 'rw',
    init_arg  => undef,
    clearer   => 'unset_from_proc',
);

has 'err_proc' => (
    is        => 'rw',
    init_arg  => undef,
    clearer   => 'unset_err_proc',
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
    return sprintf '$| = 1; require %s; %s->new(%s)->run();', $class, $class, $params;
}

sub spawn {
    my $self = shift;
    $self->is_running and croak 'process is already running';

    pipe(my $in, my $out);
    my $err = gensym;

    my $e    = sprintf '-e %s', singlequote($self->code);
    my $cmd  = join ' ', command, $self->includes, $e;
    my $proc = open3($in, $out, $err, $cmd) or croak $?;

    $self->proc($proc);
    $self->to_proc($in);
    $self->from_proc($out);
    $self->err_proc($err);

    return 1;
}

sub kill_child {
    my ($self, $wait) = @_;
    $self->is_running or croak 'process is not running';
    
    kill 9, $self->proc;

    $self->unset_proc;
    $self->unset_to_proc;
    $self->unset_from_proc;
    $self->unset_err_proc;
}

sub wait_child {
    my $self = shift;
    waitpid $self->proc, 0;
}

sub send {
    my ($self, $line) = @_;
    $self->is_running or croak 'process is not running';
    my $fh = $self->to_proc;
    local $| = 1;
    chomp $line;
    printf $fh "%s\n", $line;
}

sub recv {
    my $self = shift;
    $self->is_running or croak 'process is not running';
    my $fh   = $self->from_proc;
    my $line = <$fh>;
    chomp $line;
    return $line;
}

sub recv_err {
    my $self = shift;
    $self->is_running or croak 'process is not running';
    my $fh   = $self->err_proc;
    my $line = <$fh>;
    chomp $line;
    return $line;   
}

sub DEMOLISH {
    my $self = shift;
    $self->kill_child(1);
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;