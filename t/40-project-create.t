use strict;
use warnings;

use Test::More;

use Cwd qw(getcwd);
use File::Spec;
use File::Temp qw(tempdir);
use IPC::Open3 qw(open3);
use JSON::PP qw(decode_json);
use Symbol qw(gensym);

use Class::Veyra::Compiler;
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

sub error_from {
    my ($code) = @_;

    my $completed = eval {
        $code->();
        1;
    };

    my $error = $@;

    return $completed ? '' : $error;
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

    my $stdout = do {
        local $/;
        <$output>;
    };

    my $stderr = do {
        local $/;
        <$error_handle>;
    };

    close $output;
    close $error_handle;

    waitpid $pid, 0;
    my $status = $?;

    return {
        status => $status,
        stdout => defined $stdout ? $stdout : '',
        stderr => defined $stderr ? $stderr : '',
    };
}

my $original_directory = getcwd();

my $script = File::Spec->catfile(
    $original_directory,
    'script',
    'veyra',
);

my @command = (
    $^X,
    '-I' . File::Spec->catdir(
        $original_directory,
        'blib',
        'lib',
    ),
    '-I' . File::Spec->catdir(
        $original_directory,
        'lib',
    ),
    $script,
);

my $temporary = tempdir(CLEANUP => 1);

chdir $temporary
    or die "Cannot enter temporary directory: $!";

my $created = run_command(
    @command,
    'create',
    'hello',
);

is(
    $created->{status},
    0,
    'veyra create succeeds',
);

is(
    $created->{stdout},
    "Created project 'hello'.\n",
    'reports the created project',
);

is(
    $created->{stderr},
    '',
    'successful creation has no error output',
);

my $root = File::Spec->catdir(
    $temporary,
    'hello',
);

for my $parts (
    ['veyra.json'],
    ['src', 'App', 'Main.veyra'],
    ['run.pl'],
    ['.gitignore'],
) {
    ok(
        -f File::Spec->catfile($root, @$parts),
        'creates ' . join('/', @$parts),
    );
}

my $configuration = decode_json(
    read_file(
        File::Spec->catfile($root, 'veyra.json'),
    ),
);

is_deeply(
    $configuration,
    {
        entry         => 'App::Main',
        include_paths => ['src'],
        output        => 'build/Main.pm',
        run           => 'run.pl',
    },
    'creates the expected project configuration',
);

is(
    read_file(
        File::Spec->catfile($root, '.gitignore'),
    ),
    "/build/\n",
    'ignores generated build output',
);

ok(
    !-d File::Spec->catdir($root, 'build'),
    'does not create build output during project creation',
);

my $project = Class::Veyra::Compiler->analyze_module(
    $configuration->{entry},
    include_paths => [
        File::Spec->catdir($root, 'src'),
    ],
);

is(
    $project->{classes}[0]{name},
    'App::Main',
    'generated starter source passes compiler analysis',
);

my $source_path = File::Spec->catfile(
    $root,
    'src',
    'App',
    'Main.veyra',
);

my $source_before = read_file($source_path);

my $duplicate = run_command(
    @command,
    'create',
    'hello',
);

is(
    $duplicate->{status},
    1 << 8,
    'refuses an existing project destination',
);

like(
    $duplicate->{stderr},
    qr/already exists/,
    'explains why duplicate creation failed',
);

is(
    read_file($source_path),
    $source_before,
    'duplicate creation leaves existing source unchanged',
);

for my $invalid (
    '',
    '../outside',
    'nested/project',
    '123project',
    'bad name',
) {
    like(
        error_from(sub {
            Class::Veyra::ProjectCreator->create($invalid);
        }),
        qr/Project name must/,
        'rejects an invalid project name',
    );
}

my $missing_name = run_command(
    @command,
    'create',
);

is(
    $missing_name->{status},
    2 << 8,
    'create requires exactly one project name',
);

my $help = run_command(
    @command,
    'help',
);

is(
    $help->{status},
    0,
    'help succeeds',
);

like(
    $help->{stdout},
    qr/veyra create NAME/,
    'help documents project creation',
);

chdir $original_directory
    or die "Cannot restore working directory: $!";

done_testing;
