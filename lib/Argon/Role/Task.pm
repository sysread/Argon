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

1;
=pod

=head1 NAME

Argon::Role::Task

=head1 SYNOPSIS

    package MyTask;
    use Moose;

    with 'Argon::Role::Task';

    sub run {
        ...

    }

=head1 DESCRIPTION

Defines a role which must be implemented by task classes. Tasks are created via
C<Argon::Client->process>, which specifies the class name and parameters used to
instantiate the class. The I<run> method is provided by the implementing task
class. The I<run> method performs the work for which the task is designed and
returns the results.

=head1 AUTHOR

Jeff Ober L<mailto:jeffober@gmail.com>

=head1 LICENSE

BSD license

=cut