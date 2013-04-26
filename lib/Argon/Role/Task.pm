#-------------------------------------------------------------------------------
# Interface required of classes used as tasks in an Argon application.
#-------------------------------------------------------------------------------
package Argon::Role::Task;

use strict;
use warnings;
use Carp;

use Moose::Role;
use namespace::autoclean;

requires 'run';

;

1;