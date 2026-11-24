use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME             => 'Class::Veyra',
    VERSION_FROM     => 'lib/Class/Veyra.pm',
    ABSTRACT         => 'Class syntax and explicit interfaces for Perl',
    MIN_PERL_VERSION => '5.038',

    EXE_FILES => [
        'script/veyra',
        'script/veyra-compile',
    ],

    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 0,
    },

    TEST_REQUIRES => {
        'Test::More' => 0,
    },

    PREREQ_PM => {},
);
