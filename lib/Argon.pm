package Argon;
# ABSTRACT: Simple, fast, and flexible distributed computing

=head1 DESCRIPTION

Argon is a distributed processing platform built for Perl. It is designed to
offer a simple, flexible, system for quickly building scalable software.

=cut

use strict;
use warnings;
use Carp;

our $ALLOW_EVAL = 0;
sub ASSERT_EVAL_ALLOWED { $Argon::ALLOW_EVAL || croak 'not permitted: $Argon::ALLOW_EVAL is not set' };

1;
