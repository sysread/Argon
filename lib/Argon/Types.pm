package Argon::Types;
# ABSTRACT: TypeConstraints used by Argon classes

=head1 DESCRIPTION

Type constraints used by Ar classes.

=cut

use strict;
use warnings;
use Moose::Util::TypeConstraints;
use Path::Tiny qw(path);
use Argon::Constants qw(:commands :priorities);

=head1 TYPE CONSTRAINTS

=head2 AnyEvent::Condvar

See L<AnyEvent/CONDITION VARIABLES>.

=cut

class_type 'AnyEvent::CondVar';

=head2 Ar::Callback

A code reference or condition variable.

=cut

union 'Ar::Callback', ['CodeRef', 'AnyEvent::CondVar'];

=head2 Ar::FilePath

A path to an existing, accessible file.

=cut

subtype 'Ar::FilePath', as 'Str', where { $_ && path($_)->is_file };

=head2 Ar::Command

An Ar command verb. See L<Argon::Constants/:commands>.

=cut

enum 'Ar::Command', [$ID, $PING, $ACK, $ERROR, $QUEUE, $DENY, $DONE, $HIRE];

=head2 Ar::Priority

An L<Argon::Message> priority. See L<Argon::Constants/:priorities>.

=cut

enum 'Ar::Priority', [$HIGH, $NORMAL, $LOW];

no Moose::Util::TypeConstraints;
1;
