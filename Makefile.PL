use 5.006;
use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Argon',
    AUTHOR              => q{"Jeff Ober" <"jeffober@gmail.com">},
    VERSION_FROM        => 'lib/Argon.pm',
    ABSTRACT            => 'A robust, distributed services platform.',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More'                => 0,
        'Moose'                     => 0,
        'MooseX::StrictConstructor' => 0,
        'namespace::autoclean'      => 0,
        'Data::UUID'                => 0,
        'AnyEvent'                  => 0,
        'Coro'                      => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Argon-*' },
);
