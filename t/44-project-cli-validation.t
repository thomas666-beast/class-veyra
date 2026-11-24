use strict;
use warnings;

use Test::More;

use Cwd qw(getcwd);
use File::Spec;
use File::Temp qw(tempdir);
use IPC::Open3 qw(open3);
use JSON::PP ();
use Symbol qw(gensym);

use Class::Veyra::ProjectCreator;

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

my $distribution = getcwd();

my @cli = (
    $^X,
    '-I' . File::Spec->catdir(
        $distribution,
        'blib',
        'lib',
    ),
    '-I' . File::Spec->catdir(
        $distribution,
        'lib',
    ),
    File::Spec->catfile(
        $distribution,
        'script',
        'veyra',
    ),
);

my $temporary = tempdir(CLEANUP => 1);

chdir $temporary
    or die "Cannot enter temporary directory: $!";

my $root = Class::Veyra::ProjectCreator->create(
    'cli-validation',
);

my $source_directory = File::Spec->catdir(
    $root,
    'src',
    'App',
);

my $main = File::Spec->catfile(
    $source_directory,
    'Main.veyra',
);

my $user = File::Spec->catfile(
    $source_directory,
    'User.veyra',
);

my $output = File::Spec->catfile(
    $root,
    'build',
    'Main.pm',
);

my $marker = File::Spec->catfile(
    $root,
    'runner-started.txt',
);

write_file(
    $user,
    <<'VEYRA',
class App::User {
    fun greeting {
        return "RUN_OK";
    }
}
VEYRA
);

my $valid_main = <<'VEYRA';
import App::User;

class App::Main {
    act message {
        my $user = App::User->new();
        print $user->greeting(), "\n";
    }
}
VEYRA

write_file($main, $valid_main);

write_file(
    File::Spec->catfile($root, 'run.pl'),
    <<'PERL',
use v5.38;
use strict;
use warnings;

use Cwd qw(getcwd);
use FindBin qw($Bin);
use JSON::PP qw(encode_json);

open my $marker, '>:raw', "$Bin/runner-started.txt"
    or die "Cannot create runner marker: $!";

print {$marker} getcwd()
    or die "Cannot write runner marker: $!";

close $marker
    or die "Cannot close runner marker: $!";

require "$Bin/build/Main.pm";

my $app = App::Main->new();

$app->message();

if ($ENV{VEYRA_CLI_TEST_ARGUMENTS}) {
    print encode_json(\@ARGV), "\n";
}

exit(
    defined $ENV{VEYRA_CLI_TEST_EXIT}
        ? $ENV{VEYRA_CLI_TEST_EXIT}
        : 0
);
PERL
);

chdir $source_directory
    or die "Cannot enter nested source directory: $!";

local $ENV{VEYRA_CLI_TEST_ARGUMENTS} = 0;

{
    local $ENV{VEYRA_CLI_TEST_EXIT} = 0;

    my $checked = run_command(@cli, 'check');

    is(
        $checked->{status},
        0,
        'check accepts a valid project from a nested directory',
    );

    is(
        $checked->{stderr},
        '',
        'valid check produces no error output',
    );

    ok(
        !-e $output,
        'check does not create the configured build output',
    );

    ok(
        !-e $marker,
        'check does not execute the runner',
    );

    my $ran = run_command(@cli, 'run');

    is(
        $ran->{status},
        0,
        'run builds and executes a valid project',
    );

    is(
        $ran->{stdout},
        "RUN_OK\n",
        'run forwards application output',
    );

    is(
        $ran->{stderr},
        '',
        'valid run produces no error output',
    );

    ok(
        -f $output,
        'run creates the generated bundle',
    );

    ok(
        -f $marker,
        'run executes the configured runner',
    );

    unless (-f $output && -f $marker) {
        chdir $distribution
            or die "Cannot restore working directory: $!";

        BAIL_OUT('Valid project did not build and run');
    }

    is(
        read_file($marker),
        $root,
        'runner executes from the project root',
    );
}

{
    local $ENV{VEYRA_CLI_TEST_EXIT} = 7;

    my $ran = run_command(@cli, 'run');

    is(
        $ran->{status},
        7 << 8,
        'run returns the application exit code',
    );
}

{
    local $ENV{VEYRA_CLI_TEST_EXIT} = 7;
    local $ENV{VEYRA_CLI_TEST_ARGUMENTS} = 1;

    my @arguments = (
        'Alice',
        '--verbose',
        '',
        'two words',
        q{quotes: 'single' and "double"},
        '$HOME; echo not-a-shell-command',
        "first line\nsecond line",
        '--',
        '--help',
    );

    my $ran = run_command(
        @cli,
        'run',
        '--',
        @arguments,
    );

    is(
        $ran->{status},
        7 << 8,
        'argument forwarding preserves the application exit code',
    );

    is(
        $ran->{stderr},
        '',
        'argument forwarding produces no diagnostics',
    );

    my $expected_arguments =
        JSON::PP::encode_json(\@arguments);

    is(
        $ran->{stdout},
        "RUN_OK\n$expected_arguments\n",
        'forwards arguments unchanged, including empty and special values',
    );
}

{
    local $ENV{VEYRA_CLI_TEST_EXIT} = 0;
    local $ENV{VEYRA_CLI_TEST_ARGUMENTS} = 1;

    my $ran = run_command(
        @cli,
        'run',
        '--',
    );

    is(
        $ran->{status},
        0,
        'accepts an argument separator without application arguments',
    );

    is(
        $ran->{stdout},
        "RUN_OK\n[]\n",
        'an empty forwarded argument list remains empty',
    );

    is(
        $ran->{stderr},
        '',
        'an empty forwarded argument list produces no diagnostics',
    );
}

for my $case (
    {
        label     => 'run arguments without a separator',
        arguments => ['run', 'Alice'],
    },
    {
        label     => 'run option without a separator',
        arguments => ['run', '--help'],
    },
    {
        label     => 'check with a separator',
        arguments => ['check', '--'],
    },
    {
        label     => 'build with application arguments',
        arguments => ['build', '--', 'Alice'],
    },
) {
    unlink $marker
        or die "Cannot remove runner marker: $!"
        if -e $marker;

    my $result = run_command(
        @cli,
        @{ $case->{arguments} },
    );

    is(
        $result->{status},
        2 << 8,
        "rejects $case->{label}",
    );

    like(
        $result->{stderr},
        qr/Usage:/,
        "reports usage for $case->{label}",
    );

    is(
        $result->{stdout},
        '',
        "prints no success output for $case->{label}",
    );

    ok(
        !-e $marker,
        "does not execute the runner for $case->{label}",
    );
}

my $previous_output = read_file($output);

for my $case (
    {
        name => 'unknown class',
        body => <<'VEYRA',
import App::User;

class App::Main {
    act message {
        my $user = App::Users->new();
        $user->greeting();
    }
}
VEYRA
        diagnostic => qr/Unknown class 'App::Users'/,
    },
    {
        name => 'unknown method',
        body => <<'VEYRA',
import App::User;

class App::Main {
    act message {
        my $user = App::User->new();
        $user->greetng();
    }
}
VEYRA
        diagnostic => qr/Unknown method 'greetng' on 'App::User'/,
    },
) {
    write_file($main, $case->{body});

    unlink $marker
        or die "Cannot remove runner marker: $!"
        if -e $marker;

    for my $command ('check', 'build', 'run') {
        my @arguments = $command eq 'run'
            ? ('--', 'Alice', '--verbose')
            : ();

        my $result = run_command(
            @cli,
            $command,
            @arguments,
        );

        is(
            $result->{status},
            1 << 8,
            "$command rejects $case->{name}",
        );

        like(
            $result->{stderr},
            $case->{diagnostic},
            "$command reports $case->{name}",
        );

        is(
            $result->{stdout},
            '',
            "$command reports no success for $case->{name}",
        );

        is(
            read_file($output),
            $previous_output,
            "$command preserves previous output after $case->{name}",
        );

        ok(
            !-e $marker,
            "$command does not execute the runner after $case->{name}",
        );
    }
}

write_file($main, $valid_main);

{
    local $ENV{VEYRA_CLI_TEST_EXIT} = 0;

    my $recovered = run_command(@cli, 'run');

    is(
        $recovered->{status},
        0,
        'run succeeds after correcting the source',
    );

    is(
        $recovered->{stdout},
        "RUN_OK\n",
        'corrected application executes normally',
    );

    is(
        $recovered->{stderr},
        '',
        'corrected application produces no diagnostics',
    );
}

chdir $distribution
    or die "Cannot restore working directory: $!";

done_testing;
