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
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Argon-*' },

    PREREQ_PM => {
        'Moose'                     => 0,
        'MooseX::StrictConstructor' => 0,
        'namespace::autoclean'      => 0,
        'Data::UUID'                => 0,
        'AnyEvent'                  => 0,
        'Coro'                      => 0,
        'String::Escape'            => 0,
    },

    BUILD_REQUIRES => {
        'Test::More'                => 0,
        'IO::Capture::Stderr'       => 0,
    },
);
