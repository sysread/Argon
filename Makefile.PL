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
    EXE_FILES           => [ 'bin/cluster.pl', 'bin/node.pl' ],

    PREREQ_PM => {
        'AnyEvent'                  => 0,
        'Coro'                      => 0,
        'Coro::PrioChannel'         => '0.005',
        'Data::UUID'                => 0,
        'Moose'                     => 0,
        'MooseX::StrictConstructor' => 0,
        'namespace::autoclean'      => 0,
        'String::Escape'            => 0,
        'UNIVERSAL::require'        => 0,
    },

    BUILD_REQUIRES => {
        'IO::Capture::Stderr'       => 0,
        'Test::More'                => 0,
        'Test::Refcount'            => 0,
    },
);
