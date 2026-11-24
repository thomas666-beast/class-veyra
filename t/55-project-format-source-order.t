use strict;
use warnings;

use Test::More;

use Cwd qw(getcwd);
use File::Spec;
use File::Temp qw(tempdir);

use Class::Veyra::Compiler;
use Class::Veyra::Generator;
use Class::Veyra::ProjectCreator;
use Class::Veyra::ProjectFormatter;

sub read_file {
    my ($path) = @_;

    open my $handle, '<:raw', $path
        or die "Cannot read test file '$path': $!";

    local $/;
    my $text = <$handle>;

    close $handle
        or die "Cannot close test file '$path': $!";

    return defined $text ? $text : '';
}

sub write_file {
    my ($path, $text) = @_;

    open my $handle, '>:raw', $path
        or die "Cannot write test file '$path': $!";

    print {$handle} $text
        or die "Cannot write test file '$path': $!";

    close $handle
        or die "Cannot close test file '$path': $!";

    return;
}

sub generated_perl {
    my ($include_directory) = @_;

    my $document =
        Class::Veyra::Compiler->analyze_module(
            'App::Main',
            include_paths => [$include_directory],
        );

    return Class::Veyra::Generator->generate(
        $document,
    );
}

my $original_directory = getcwd();
my $temporary = tempdir(CLEANUP => 1);

chdir $temporary
    or die "Cannot enter temporary directory: $!";

my $root = Class::Veyra::ProjectCreator->create(
    'source-order',
);

my $include_directory = File::Spec->catdir(
    $root,
    'src',
);

my $source_directory = File::Spec->catdir(
    $include_directory,
    'App',
);

my $main = File::Spec->catfile(
    $source_directory,
    'Main.veyra',
);

my $dependency = File::Spec->catfile(
    $source_directory,
    'A.veyra',
);

my $main_source = <<'VEYRA';
import App::A;class App::Main{act message{print "Hello";}}
VEYRA

my $dependency_source = <<'VEYRA';
class App::A{}
VEYRA

write_file($main, $main_source);
write_file($dependency, $dependency_source);

chdir $root
    or die "Cannot enter project directory: $!";

my $project = Class::Veyra::ProjectFormatter->load;

my $before = generated_perl($include_directory);

my $expected_labels = [
    File::Spec->catfile('src', 'App', 'A.veyra'),
    File::Spec->catfile('src', 'App', 'Main.veyra'),
];

my $check_result;

my $check_completed = eval {
    $check_result = $project->format(
        check_only => 1,
    );

    1;
};

my $check_error = $@;

ok(
    $check_completed,
    'format check preserves source order during validation',
);

is(
    $check_error,
    '',
    'different filename order does not trigger an equivalence error',
);

is_deeply(
    $check_result,
    $expected_labels,
    'changed-file reporting remains sorted',
);

is(
    read_file($main),
    $main_source,
    'check mode leaves the entry source unchanged',
);

is(
    read_file($dependency),
    $dependency_source,
    'check mode leaves the dependency unchanged',
);

my $format_result;

my $format_completed = eval {
    $format_result = $project->format;

    1;
};

my $format_error = $@;

ok(
    $format_completed,
    'formats sources whose collection order differs from filename order',
);

is(
    $format_error,
    '',
    'formatting produces no source-order error',
);

is_deeply(
    $format_result,
    $expected_labels,
    'format mode reports changed files in sorted order',
);

is(
    read_file($main),
    <<'VEYRA',
import App::A;
class App::Main {
    act message {print "Hello";}
}
VEYRA
    'formats the entry source',
);

is(
    read_file($dependency),
    <<'VEYRA',
class App::A {
}
VEYRA
    'formats the dependency',
);

is(
    generated_perl($include_directory),
    $before,
    'formatting preserves generated Perl and declaration order',
);

my $second_result;

my $second_completed = eval {
    $second_result = $project->format(
        check_only => 1,
    );

    1;
};

my $second_error = $@;

ok(
    $second_completed,
    'checking the formatted project succeeds',
);

is(
    $second_error,
    '',
    'repeated validation produces no error',
);

is_deeply(
    $second_result,
    [],
    'the formatted project needs no further changes',
);

chdir $original_directory
    or die "Cannot restore working directory: $!";

done_testing;
