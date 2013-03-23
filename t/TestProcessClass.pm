package TestProcessClass;

use strict;
use warnings;
use Carp;
use Argon;

sub new {
    my ($class, @args) = @_;
    return bless [@args], $class;
}

sub run {
    my $self = shift;
    local $| = 1;
    
    my $exit = 0;
    until ($exit) {
        my $line = <STDIN>;
        defined $line or last;
        chomp $line;

        if ($line eq 'EXIT') {
            $exit = 1;
        } else {
            warn  qq/Warning: you said "$line"\n/;
            print qq/You said "$line"\n/;
        }
    }

    exit 0;
}

1;