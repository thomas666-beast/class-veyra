use strict;
use warnings;

use Test::More;

BEGIN {
    plan skip_all =>
        'Set VEYRA_TEST_INSTALLED=1 to test installed commands'
        unless $ENV{VEYRA_TEST_INSTALLED};
}

use Cwd qw(abs_path getcwd);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin qw($Bin);
use IO::Select;
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

sub find_command {
    my ($name) = @_;

    my @names = $^O eq 'MSWin32'
        ? ("$name.bat", "$name.exe", $name)
        : ($name);

    for my $directory (File::Spec->path) {
        $directory = '.'
            unless length $directory;

        for my $candidate_name (@names) {
            my $candidate = File::Spec->catfile(
                $directory,
                $candidate_name,
            );

            next unless -f $candidate;
            next unless $^O eq 'MSWin32' || -x $candidate;

            my $absolute = abs_path($candidate);

            return $absolute
                if defined $absolute;
        }
    }

    return;
}

sub is_inside {
    my ($path, $directory) = @_;

    my $relative = File::Spec->abs2rel(
        $path,
        $directory,
    );

    return 0
        if File::Spec->file_name_is_absolute($relative);

    my @parts = File::Spec->splitdir($relative);

    return !@parts
        || $parts[0] ne File::Spec->updir;
}

sub run_command {
    my (@command) = @_;

    my $error_handle = gensym;

    my $pid = open3(
        my $input,
        my $output,
        $error_handle,
        @command,
    );

    close $input;

    my %stream_for = (
        fileno($output)       => 'stdout',
        fileno($error_handle) => 'stderr',
    );

    my %captured = (
        stdout => '',
        stderr => '',
    );

    my $selector = IO::Select->new(
        $output,
        $error_handle,
    );

    while ($selector->count) {
        for my $handle ($selector->can_read) {
            my $stream = $stream_for{fileno($handle)};
            my $buffer;

            my $count = sysread(
                $handle,
                $buffer,
                8192,
            );

            unless (defined $count) {
                next if $!{EINTR};

                die "Cannot read command output: $!";
            }

            if ($count == 0) {
                $selector->remove($handle);
                close $handle;

                next;
            }

            $captured{$stream} .= $buffer;
        }
    }

    my $waited;

    do {
        $waited = waitpid $pid, 0;
    } while ($waited == -1 && $!{EINTR});

    die "Cannot wait for command: $!"
        if $waited == -1;

    return {
        status => $?,
        %captured,
    };
}

sub read_file {
    my ($path) = @_;

    open my $handle, '<:raw', $path
        or die "Cannot read '$path': $!";

    local $/;
    my $text = <$handle>;

    close $handle
        or die "Cannot close '$path': $!";

    return defined $text ? $text : '';
}

my $original_directory = getcwd();
my $distribution = abs_path(dirname($Bin));

my $veyra = find_command('veyra');
my $compiler = find_command('veyra-compile');

BAIL_OUT('Cannot find veyra on PATH')
    unless defined $veyra;

BAIL_OUT('Cannot find veyra-compile on PATH')
    unless defined $compiler;

for my $command ($veyra, $compiler) {
    BAIL_OUT(
        "Command resolves inside the source checkout: $command"
    ) if is_inside($command, $distribution);
}

diag("Testing veyra: $veyra");
diag("Testing veyra-compile: $compiler");

local %ENV = %ENV;

delete @ENV{
    qw(
        PERL5LIB
        PERLLIB
        PERL5OPT
        VEYRA_CLI_TEST_EXIT
        VEYRA_CLI_TEST_ARGUMENTS
    )
};

my $temporary = tempdir(
    'veyra installed XXXX',
    TMPDIR  => 1,
    CLEANUP => 1,
);

END {
    if (defined $original_directory) {
        chdir $original_directory;
    }
}

chdir $temporary
    or die "Cannot enter temporary directory: $!";

my $created = run_command(
    $veyra,
    'create',
    'hello',
);

is(
    $created->{status},
    0,
    'installed veyra creates a project without source-tree library paths',
);

is(
    $created->{stdout},
    "Created project 'hello'.\n",
    'installed create reports the project',
);

is(
    $created->{stderr},
    '',
    'installed create produces no diagnostics',
);

my $root = File::Spec->catdir(
    $temporary,
    'hello',
);

BAIL_OUT('Installed create did not produce the project directory')
    unless -d $root;

chdir $root
    or die "Cannot enter created project: $!";

my $ran = run_command(
    $veyra,
    'run',
);

is(
    $ran->{status},
    0,
    'installed run builds and executes an untouched starter',
);

is(
    $ran->{stdout},
    "Hello, world!\n",
    'installed starter prints the expected greeting',
);

is(
    $ran->{stderr},
    '',
    'installed starter runs without diagnostics',
);

for my $command ('check', 'fmt', 'build') {
    my $result = run_command(
        $veyra,
        $command,
    );

    is(
        $result->{status},
        0,
        "installed $command succeeds",
    );

    is(
        $result->{stderr},
        '',
        "installed $command produces no diagnostics",
    );
}

my $format_check = run_command(
    $veyra,
    'fmt',
    '--check',
);

is(
    $format_check->{status},
    0,
    'installed formatting check succeeds after formatting',
);

is(
    $format_check->{stderr},
    '',
    'installed formatting check produces no diagnostics',
);

my $source_directory = File::Spec->catdir(
    $root,
    'src',
    'App',
);

chdir $source_directory
    or die "Cannot enter nested source directory: $!";

my $nested_run = run_command(
    $veyra,
    'run',
);

is(
    $nested_run->{status},
    0,
    'installed run discovers the project from a nested directory',
);

is(
    $nested_run->{stdout},
    "Hello, world!\n",
    'nested installed run preserves starter output',
);

is(
    $nested_run->{stderr},
    '',
    'nested installed run produces no diagnostics',
);

chdir $root
    or die "Cannot return to project root: $!";

my $help = run_command(
    $compiler,
    '--help',
);

is(
    $help->{status},
    0,
    'installed low-level compiler help succeeds',
);

like(
    $help->{stdout},
    qr/veyra-compile/,
    'installed low-level compiler remains available',
);

my $vendor = File::Spec->catdir(
    $root,
    'vendor',
);

make_path($vendor);

my $bundle = File::Spec->catfile(
    $root,
    'standalone.pm',
);

my @compile_command = (
    $compiler,
    '--module',
    'App::Main',
    '-I',
    File::Spec->catdir($root, 'src'),
    '-I',
    $vendor,
    '--output',
    $bundle,
);

my $compiled = run_command(
    @compile_command,
);

is(
    $compiled->{status},
    0,
    'installed low-level compiler accepts repeated include options',
);

is(
    $compiled->{stderr},
    '',
    'installed low-level compilation produces no diagnostics',
);

ok(
    -f $bundle,
    'installed low-level compiler writes its output',
);

BAIL_OUT('Installed low-level compiler did not create its output')
    unless -f $bundle;

my $bundle_before = read_file($bundle);

my $duplicate = run_command(
    @compile_command,
);

is(
    $duplicate->{status},
    1 << 8,
    'installed low-level compiler refuses an existing output',
);

like(
    $duplicate->{stderr},
    qr/existing files are not overwritten/,
    'installed low-level compiler explains overwrite refusal',
);

is(
    read_file($bundle),
    $bundle_before,
    'overwrite refusal preserves the existing bundle',
);

chdir $original_directory
    or die "Cannot restore working directory: $!";

done_testing;
