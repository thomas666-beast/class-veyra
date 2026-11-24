use strict;
use warnings;

use Test::More;

use Cwd qw(getcwd);
use File::Spec;
use File::Temp qw(tempdir);

use Class::Veyra::Project;
use Class::Veyra::ProjectCreator;

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

my $original_directory = getcwd();
my $temporary = tempdir(CLEANUP => 1);

chdir $temporary
    or die "Cannot enter temporary directory: $!";

my $root = Class::Veyra::ProjectCreator->create('hello');

chdir $root
    or die "Cannot enter project directory: $!";

my $project = Class::Veyra::Project->load;

is(
    $project->entry,
    'App::Main',
    'loads the configured entry module',
);

is(
    $project->output_label,
    'build/Main.pm',
    'loads the configured output path',
);

my $output = File::Spec->catfile(
    $root,
    'build',
    'Main.pm',
);

my $build_directory = File::Spec->catdir(
    $root,
    'build',
);

$project->check;

ok(
    !-e $output,
    'check does not generate output',
);

ok(
    !-d $build_directory,
    'check does not create the build directory',
);

is(
    $project->build,
    $output,
    'build returns the generated output path',
);

ok(
    -f $output,
    'build creates the output file',
);

my $first_build = read_file($output);

like(
    $first_build,
    qr/class App::Main \{/,
    'output contains the entry class',
);

like(
    $first_build,
    qr/Hello, world!/,
    'output contains the starter message',
);

$project->build;

is(
    read_file($output),
    $first_build,
    'rebuilding succeeds without manually deleting output',
);

my $source_directory = File::Spec->catdir(
    $root,
    'src',
    'App',
);

chdir $source_directory
    or die "Cannot enter source directory: $!";

my $nested_project = Class::Veyra::Project->load;

is(
    $nested_project->entry,
    'App::Main',
    'finds project configuration from a nested directory',
);

$nested_project->check;
$nested_project->build;

is(
    read_file($output),
    $first_build,
    'resolves project paths relative to configuration',
);

my $source_path = File::Spec->catfile(
    $source_directory,
    'Main.veyra',
);

write_file(
    $source_path,
    <<'VEYRA',
class App::Main {
    fun message {
        return "Updated message";
    }
}
VEYRA
);

$nested_project->build;

my $updated_build = read_file($output);

like(
    $updated_build,
    qr/Updated message/,
    'rebuild replaces output with newly compiled source',
);

write_file(
    $source_path,
    <<'VEYRA',
import Missing::Dependency;

class App::Main {}
VEYRA
);

my $completed = eval {
    $nested_project->build;
    1;
};

my $error = $@;

ok(
    !$completed,
    'build fails when an imported module is missing',
);

like(
    $error,
    qr/Cannot find Veyra source 'Missing::Dependency'/,
    'build preserves the compiler diagnostic',
);

is(
    read_file($output),
    $updated_build,
    'failed compilation preserves the previous output',
);

my @temporary_outputs = glob(
    File::Spec->catfile(
        $build_directory,
        '.veyra-build-*',
    ),
);

is_deeply(
    \@temporary_outputs,
    [],
    'build leaves no temporary output files',
);

chdir $root
    or die "Cannot return to project directory: $!";

write_file(
    File::Spec->catfile($root, 'veyra.json'),
    "{invalid JSON\n",
);

$completed = eval {
    Class::Veyra::Project->load;
    1;
};

$error = $@;

ok(
    !$completed,
    'rejects invalid project JSON',
);

like(
    $error,
    qr/Cannot parse .*veyra\.json/s,
    'identifies the invalid configuration file',
);

chdir $original_directory
    or die "Cannot restore working directory: $!";

done_testing;
