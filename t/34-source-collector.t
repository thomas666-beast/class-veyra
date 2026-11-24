use strict;
use warnings;

use Test::More;

use Cwd qw(abs_path);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);

use Class::Veyra::Compiler;
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

my $main_text = <<'VEYRA';
import Demo::Left;
import Demo::Right;

class Demo::Main extends Demo::Left {}
VEYRA

my $main_path = write_source(
    $root,
    'Demo::Main',
    $main_text,
);

my $left_path = write_source(
    $root,
    'Demo::Left',
    <<'VEYRA',
import Demo::Shared;

class Demo::Left extends Demo::Shared {}
VEYRA
);

my $shared_path = write_source(
    $root,
    'Demo::Shared',
    <<'VEYRA',
class Demo::Shared {
    fun value {
        return 42;
    }
}
VEYRA
);

my $right_path = write_source(
    $root,
    'Demo::Right',
    <<'VEYRA',
import Demo::Shared;

class Demo::Right extends Demo::Shared {}
VEYRA
);

my $collector = Class::Veyra::SourceCollector->new(
    include_paths => [$root],
);

isa_ok(
    $collector,
    'Class::Veyra::SourceCollector',
);

my $sources = $collector->collect('Demo::Main');

is_deeply(
    [map { $_->{source_name} } @$sources],
    [
        $main_path,
        $left_path,
        $shared_path,
        $right_path,
    ],
    'collects sources in entry-first depth-first order',
);

is(
    scalar @$sources,
    4,
    'collects a shared transitive dependency once',
);

is(
    $sources->[0]{source},
    $main_text,
    'preserves the entry source contents',
);

my $project =
    Class::Veyra::Compiler->analyze_sources($sources);

is(
    scalar @{ $project->{classes} },
    4,
    'collected sources work with project analysis',
);

my $generated =
    Class::Veyra::Compiler->compile_sources($sources);

my $shared_position =
    index $generated, 'class Demo::Shared {';

my $left_position =
    index $generated, 'class Demo::Left :isa(';

my $main_position =
    index $generated, 'class Demo::Main :isa(';

ok(
    $shared_position >= 0
        && $left_position > $shared_position
        && $main_position > $left_position,
    'compiler orders imported ancestors before descendants',
);

my $again = $collector->collect('Demo::Main');

is_deeply(
    $again,
    $sources,
    'supports repeated collection calls',
);

my $changed_text = <<'VEYRA';
class Demo::Shared {
    fun value {
        return 43;
    }
}
VEYRA

write_source(
    $root,
    'Demo::Shared',
    $changed_text,
);

my $changed = $collector->collect('Demo::Main');

is(
    $changed->[2]{source},
    $changed_text,
    'reloads source contents on a later collection call',
);

my $cycle_a_path = write_source(
    $root,
    'Cycle::A',
    <<'VEYRA',
import Cycle::B;
class Cycle::A {}
VEYRA
);

my $cycle_b_path = write_source(
    $root,
    'Cycle::B',
    <<'VEYRA',
import Cycle::A;
class Cycle::B {}
VEYRA
);

my $cycle = $collector->collect('Cycle::A');

is_deeply(
    [map { $_->{source_name} } @$cycle],
    [$cycle_a_path, $cycle_b_path],
    'terminates circular imports without duplicating sources',
);

my $cycle_project =
    Class::Veyra::Compiler->analyze_sources($cycle);

is(
    scalar @{ $cycle_project->{classes} },
    2,
    'circular imports do not imply circular inheritance',
);

my $self_path = write_source(
    $root,
    'Cycle::Self',
    <<'VEYRA',
import Cycle::Self;
class Cycle::Self {}
VEYRA
);

is_deeply(
    [
        map { $_->{source_name} }
        @{ $collector->collect('Cycle::Self') }
    ],
    [$self_path],
    'collects a self-importing source once',
);

my $broken_path = write_source(
    $root,
    'Broken::Main',
    <<'VEYRA',
# Missing dependency
import Missing::Dependency;
class Broken::Main {}
VEYRA
);

my $missing_error = error_from(sub {
    $collector->collect('Broken::Main');
});

like(
    $missing_error,
    qr/Import 'Missing::Dependency'/,
    'identifies the failed import',
);

like(
    $missing_error,
    qr/\Q$broken_path\E/,
    'identifies the importing source',
);

like(
    $missing_error,
    qr/at offset 21:/,
    'reports the source-local import keyword offset',
);

like(
    $missing_error,
    qr/Cannot find Veyra source 'Missing::Dependency'/,
    'preserves the source-loader diagnostic',
);

my $malformed_path = write_source(
    $root,
    'Broken::Syntax',
    'class Broken::Syntax {',
);

my $syntax_error = error_from(sub {
    $collector->collect('Broken::Syntax');
});

like(
    $syntax_error,
    qr/Cannot parse Veyra source '\Q$malformed_path\E'/,
    'adds the filename to a parser error',
);

like(
    $syntax_error,
    qr/Unclosed body/,
    'preserves the underlying parser diagnostic',
);

like(
    error_from(sub {
        $collector->collect('Missing::Entry');
    }),
    qr/Cannot find Veyra source 'Missing::Entry'/,
    'reports a missing entry source',
);

my $recovered = $collector->collect('Demo::Main');

is(
    scalar @$recovered,
    4,
    'a failed collection does not contaminate later calls',
);

done_testing;
