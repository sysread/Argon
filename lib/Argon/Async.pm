package Argon::Async;
#ABSTRACT: A tied condvar that calls recv on FETCH

use strict;
use warnings;
use Carp;

use parent 'Tie::Scalar';

sub TIESCALAR { bless \$_[1], $_[0] }
sub STORE { croak 'Argon::Async is read only' }
sub FETCH { ${$_[0]}->recv }

1;
