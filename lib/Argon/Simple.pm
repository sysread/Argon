package Argon::Simple;

use strict;
use warnings;
use Carp;
use Argon::Client;

use parent qw(Exporter);
our @EXPORT = qw(connect process);

my $CLIENT;

sub connect {
    my ($host, $port) = @_;

    unless ($port) {
        ($host, $port) = split /:/, $host;
    }

    croak 'usage: connect($host, $port)'
        unless $host && $port;

    if (!$CLIENT || $host ne $CLIENT->host || $port != $CLIENT->port) {
        $CLIENT = Argon::Client->new(host => $host, port => $port);
    }

    return $CLIENT;
}

sub process (&@) {
    my ($f, $args) = @_;
    croak 'not connected' unless $CLIENT;

    my $msgid    = $CLIENT->queue($f, $args);
    my $deferred = sub { $CLIENT->collect($msgid) };

    return $deferred unless wantarray;

    my $is_finished = sub {
        my $status = $CLIENT->server_status;

        foreach my $pending (values %{$status->{pending}}) {
            return 0 if exists $pending->{$msgid};
        }

        return 1;
    };

    return ($deferred, $is_finished);
}

1;
__DATA__

=head1 NAME

Argon::Simple

=head1 SYNOPSIS

    use Argon::Simple;

    connect 'somehost:9999';

    my $deferred = process { shift * 2 } 21;
    if ($deferred->() == 42) {
        print "So long, and thanks for all the fish!\n";
    }

    my ($deferred, $is_finished) = process { shift * 2 } 21;
    do { print "." } until $is_finished->();
    print "So long, and thanks for all the fish!\n";

=head1 DESCRIPTION

In most cases, a script or application is going to connect to a single Argon
system. For these cases, this module provides simplified access to the Argon
system.

=head1 SUBROUTINES

=head2 connect("host:port")

Connects to a single Argon manager. If called with a single argument, a string
in the form of "host:port" is expected. Alternately, the host and port may be
passed as two separate arguments (e.g. C<connect($host, $port)>).

=head2 process { code } @args

When called in scalar context, returns a CODE reference. When called, the
C<Coro> thread will block (cede) until the result is retrieved from the Argon
system and is available.

When called in list context, additionally returns a CODE reference which
evaluates to true when the task has been completed by the Argon system.

=head1 AUTHOR

Jeff Ober <jeffober@gmail.com>
