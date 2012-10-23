#-------------------------------------------------------------------------------
# ProcessPools manage a pool of Argon::Worker processes.
#-------------------------------------------------------------------------------
package Argon::ProcessPool;

use Moose;
use Carp;
use namespace::autoclean;
use Argon      qw/:commands EOL/;
use Symbol     qw/gensym/;
use IPC::Open3 qw/open3/;

has 'concurrency' => (
    is       => 'ro',
    isa      => 'Int',
    required => 1,
);

has 'endline' => (
    is       => 'ro',
    isa      => 'Str',
    default  => EOL,
);

has 'process' => (
    is       => 'ro',
    isa      => 'HashRef',
    init_arg => undef,
    default  => sub {[]},
);

#-------------------------------------------------------------------------------
# Starts the worker processes.
#-------------------------------------------------------------------------------
sub start {
    my $self = shift;
    my $eol  = $self->endline;
    my @procs;
    foreach my $i (0 .. ($self->concurrency - 1)) {
        my ($pid, $out, $in, $err);
        $err = gensym;
        $pid = open3($out, $in, $err, $^X, '-M', 'Argon::Worker', '-e', "Argon::Worker->new(endine => '$eol')->loop()");
        $self->process->{$pid} = [$out, $in, $err];
    }
}

#-------------------------------------------------------------------------------
# Stops worker processes.
#-------------------------------------------------------------------------------
sub stop {
    my $self = shift;
    my @pids = keys %{$self->process};
    foreach my $pid (@pids) {
        my ($out, $in, $err) = $self->process->{$pid};
        my $message = Argon::Message->new(command => CMD_SHUTDOWN);
        print $out $message->encode . $self->endline;
        undef $self->process->{$pid};
    }
}

__PACKAGE__->meta->make_immutable;

1;