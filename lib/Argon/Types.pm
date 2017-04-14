package Argon::Types;
# ABSTRACT: TypeConstraints used by Argon classes

use strict;
use warnings;
use Moose::Util::TypeConstraints;
use Path::Tiny qw(path);
use Argon::Constants qw(:commands :priorities);

class_type 'AnyEvent::CondVar';

union 'Ar::Callback', ['CodeRef', 'AnyEvent::CondVar'];

subtype 'Ar::FilePath', as 'Str', where { $_ && path($_)->exists };

enum 'Ar::Command', [$ID, $PING, $ACK, $ERROR, $QUEUE, $DENY, $DONE, $HIRE];

enum 'Ar::Priority', [$HIGH, $NORMAL, $LOW];

no Moose::Util::TypeConstraints;
1;
