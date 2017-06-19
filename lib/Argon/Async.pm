package Argon::Async;
#ABSTRACT: A tied condvar that calls recv on FETCH

=head1 DESCRIPTION

A tied condvar (see L<AnyEvent/CONDITION VARIABLES>) that calls C<recv> on
C<FETCH>.

=cut

use strict;
use warnings;
use Carp;

use parent 'Tie::Scalar';

sub TIESCALAR { bless \$_[1], $_[0] }
sub STORE { croak 'Argon::Async is read only' }
sub FETCH { ${$_[0]}->recv }

1;
