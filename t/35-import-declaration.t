use strict;
use warnings;

use Test::More;

use Cwd qw(abs_path);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);

use Class::Veyra::SourceCollector;

sub write_source {
    my ($root, $name, $source) = @_;

    my @parts = split /::/, $name;
    my $filename = pop(@parts) . '.veyra';

    my $directory = File::Spec->catdir(
        $root,
        @parts,
    );

    make_path($directory);

    my $path = File::Spec->catfile(
        $directory,
        $filename,
    );

    open my $handle, '>:raw', $path
        or die "Cannot write test source '$path': $!";

    print {$handle} $source
        or die "Cannot write test source '$path': $!";

    close $handle
        or die "Cannot close test source '$path': $!";

    return abs_path($path);
}

sub error_from {
    my ($code) = @_;

    my $completed = eval {
        $code->();
        1;
    };

    my $error = $@;

    return $completed ? '' : $error;
}

my $root = tempdir(CLEANUP => 1);

my $collector = Class::Veyra::SourceCollector->new(
    include_paths => [$root],
);

write_source(
    $root,
    'Good::Person',
    'class Good::Person {}',
);

is(
    scalar @{ $collector->collect('Good::Person') },
    1,
    'accepts a matching class declaration',
);

write_source(
    $root,
    'Good::Named',
    'interface Good::Named { fun name; }',
);

is(
    scalar @{ $collector->collect('Good::Named') },
    1,
    'accepts a matching interface declaration',
);

write_source(
    $root,
    'Good::Bundle',
    <<'VEYRA',
interface Good::ExtraContract {
    fun value;
}

class Good::Helper {}

class Good::Bundle {}
VEYRA
);

is(
    scalar @{ $collector->collect('Good::Bundle') },
    1,
    'allows additional declarations before the requested declaration',
);

my $wrong_path = write_source(
    $root,
    'Wrong::Person',
    'class Wrong::Other {}',
);

my $wrong_error = error_from(sub {
    $collector->collect('Wrong::Person');
});

like(
    $wrong_error,
    qr/requested as 'Wrong::Person'/,
    'identifies the requested logical entry name',
);

like(
    $wrong_error,
    qr/does not declare 'Wrong::Person'/,
    'rejects a file declaring a different name',
);

like(
    $wrong_error,
    qr/\Q$wrong_path\E/,
    'identifies the mismatched source file',
);

write_source(
    $root,
    'Wrong::Empty',
    '',
);

like(
    error_from(sub {
        $collector->collect('Wrong::Empty');
    }),
    qr/does not declare 'Wrong::Empty'/,
    'rejects an empty file as a named entry',
);

write_source(
    $root,
    'Wrong::ImportOnly',
    'import Good::Person;',
);

like(
    error_from(sub {
        $collector->collect('Wrong::ImportOnly');
    }),
    qr/does not declare 'Wrong::ImportOnly'/,
    'an import does not count as a matching declaration',
);

my $main_path = write_source(
    $root,
    'App::Main',
    <<'VEYRA',
import Wrong::Person;
class App::Main {}
VEYRA
);

my $import_error = error_from(sub {
    $collector->collect('App::Main');
});

like(
    $import_error,
    qr/Import 'Wrong::Person' in '\Q$main_path\E' at offset 0:/,
    'preserves the importing filename and offset',
);

like(
    $import_error,
    qr/does not declare 'Wrong::Person'/,
    'reports a declaration mismatch in an imported file',
);

write_source(
    $root,
    'App::Contracts',
    <<'VEYRA',
import Good::Named;
class App::Contracts {}
VEYRA
);

is(
    scalar @{ $collector->collect('App::Contracts') },
    2,
    'accepts an imported interface as a matching declaration',
);

write_source(
    $root,
    'Case::Person',
    'class Case::person {}',
);

like(
    error_from(sub {
        $collector->collect('Case::Person');
    }),
    qr/does not declare 'Case::Person'/,
    'requires an exact case-sensitive declaration name',
);

write_source(
    $root,
    'Wrong::Person',
    'class Wrong::Person {}',
);

is(
    scalar @{ $collector->collect('App::Main') },
    2,
    'a corrected dependency succeeds on a later collection call',
);

done_testing;
