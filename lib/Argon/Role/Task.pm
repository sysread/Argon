#-------------------------------------------------------------------------------
# Interface required of classes used as tasks in an Argon application.
#-------------------------------------------------------------------------------
package Argon::Role::Task;

use Moose::Role;
use Carp;
use namespace::autoclean;

requires 'run';

no Moose;

1;