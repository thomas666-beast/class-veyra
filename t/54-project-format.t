use strict;
use warnings;

use Test::More;

use Cwd qw(getcwd);
use File::Spec;
use File::Temp qw(tempdir);
use IO::Select;
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

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

                close $handle
                    or die "Cannot close command output: $!";

                next;
            }

            $captured{$stream} .= $buffer;
        }
    }

    my $waited;

    do {
        $waited = waitpid $pid, 0;
    } while ($waited == -1 && $!{EINTR});

    die "Cannot wait for test command: $!"
        if $waited == -1;

    return {
        status => $?,
        %captured,
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

my $temporary = tempdir(
    'veyra format XXXX',
    TMPDIR  => 1,
    CLEANUP => 1,
);

END {
    if (defined $distribution) {
        chdir $distribution;
    }
}

chdir $temporary
    or die "Cannot enter temporary directory: $!";

my $root = Class::Veyra::ProjectCreator->create(
    'format-example',
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

my $unused = File::Spec->catfile(
    $source_directory,
    'Unused.veyra',
);

my $build_directory = File::Spec->catdir(
    $root,
    'build',
);

my $main_source = <<'VEYRA';
import App::User;class App::Main{act message{my $user = App::User->new(); print $user->greeting(), "\n";}}
VEYRA

my $user_source = <<'VEYRA';
class App::User{fun greeting{return "Hello, formatter!";}}
VEYRA

my $unused_source =
    "This file is not in the import graph.\n";

write_file($main, $main_source);
write_file($user, $user_source);
write_file($unused, $unused_source);

write_file(
    File::Spec->catfile($root, 'run.pl'),
    <<'PERL',
use v5.38;
use strict;
use warnings;

use FindBin qw($Bin);

require "$Bin/build/Main.pm";

my $app = App::Main->new();

$app->message();
PERL
);

chdir $source_directory
    or die "Cannot enter nested source directory: $!";

my $checked = run_command(
    @cli,
    'fmt',
    '--check',
);

is(
    $checked->{status},
    1 << 8,
    'fmt --check reports formatting changes from a nested directory',
);

is(
    $checked->{stderr},
    '',
    'formatting differences are not reported as errors',
);

like(
    $checked->{stdout},
    qr/Would format .*Main\.veyra\./,
    'reports the entry source',
);

like(
    $checked->{stdout},
    qr/Would format .*User\.veyra\./,
    'reports the imported source',
);

like(
    $checked->{stdout},
    qr/^--- a\/.*Main\.veyra$/m,
    'format check prints the original-file diff header',
);

like(
    $checked->{stdout},
    qr/^\+\+\+ b\/.*Main\.veyra$/m,
    'format check prints the formatted-file diff header',
);

like(
    $checked->{stdout},
    qr/^@@ -\d+,\d+ \+\d+,\d+ @@$/m,
    'format check prints a diff hunk',
);

like(
    $checked->{stdout},
    qr/^\+    act message /m,
    'format check shows the proposed indentation',
);

is(
    read_file($main),
    $main_source,
    'fmt --check leaves the entry source unchanged',
);

is(
    read_file($user),
    $user_source,
    'fmt --check leaves the imported source unchanged',
);

ok(
    !-e $build_directory,
    'fmt --check does not build the project',
);

my $formatted = run_command(
    @cli,
    'fmt',
);

is(
    $formatted->{status},
    0,
    'fmt succeeds',
);

is(
    $formatted->{stderr},
    '',
    'successful formatting produces no diagnostics',
);

like(
    $formatted->{stdout},
    qr/Formatted .*Main\.veyra\./,
    'fmt reports the changed entry source',
);

like(
    $formatted->{stdout},
    qr/Formatted .*User\.veyra\./,
    'fmt reports the changed imported source',
);

unlike(
    $formatted->{stdout},
    qr/^--- a\//m,
    'write mode does not print check-mode diffs',
);

is(
    read_file($main),
    <<'VEYRA',
import App::User;
class App::Main {
    act message {my $user = App::User->new(); print $user->greeting(), "\n";}
}
VEYRA
    'formats the entry declarations while retaining an inline body',
);

is(
    read_file($user),
    <<'VEYRA',
class App::User {
    fun greeting {return "Hello, formatter!";}
}
VEYRA
    'formats the imported declarations while retaining an inline body',
);

is(
    read_file($unused),
    $unused_source,
    'does not visit files outside the entry import graph',
);

ok(
    !-e $build_directory,
    'fmt does not build the project',
);

my $main_formatted = read_file($main);
my $user_formatted = read_file($user);

my $clean = run_command(
    @cli,
    'fmt',
    '--check',
);

is(
    $clean->{status},
    0,
    'fmt --check succeeds after formatting',
);

is(
    $clean->{stdout},
    "All source files are formatted.\n",
    'reports an already formatted project without a diff',
);

is(
    $clean->{stderr},
    '',
    'clean formatting check produces no diagnostics',
);

my $again = run_command(
    @cli,
    'fmt',
);

is(
    $again->{status},
    0,
    'a repeated fmt succeeds',
);

is(
    $again->{stdout},
    "All source files are formatted.\n",
    'a repeated fmt reports no changes',
);

is(
    read_file($main),
    $main_formatted,
    'a repeated fmt preserves the entry source',
);

is(
    read_file($user),
    $user_formatted,
    'a repeated fmt preserves the imported source',
);

my $ran = run_command(
    @cli,
    'run',
);

is(
    $ran->{status},
    0,
    'the formatted project still runs',
);

is(
    $ran->{stdout},
    "Hello, formatter!\n",
    'the formatted project preserves application output',
);

is(
    $ran->{stderr},
    '',
    'the formatted project runs without diagnostics',
);

my $unindented_main = <<'VEYRA';
import App::User;

class App::Main {
act message {
my $user = App::User->new();
print $user->greeting(), "\n";
}
}
VEYRA

write_file($main, $unindented_main);

my $body_check = run_command(
    @cli,
    'fmt',
    '--check',
);

is(
    $body_check->{status},
    1 << 8,
    'format check detects operation-body indentation changes',
);

like(
    $body_check->{stdout},
    qr/^\+        my \$user = App::User->new\(\);$/m,
    'diff shows the proposed body indentation',
);

like(
    $body_check->{stdout},
    qr/^-my \$user = App::User->new\(\);$/m,
    'diff shows the original unindented body line',
);

is(
    read_file($main),
    $unindented_main,
    'checking body indentation does not modify the source',
);

my $body_formatted = run_command(
    @cli,
    'fmt',
);

is(
    $body_formatted->{status},
    0,
    'fmt writes the corrected body indentation',
);

is(
    read_file($main),
    <<'VEYRA',
import App::User;

class App::Main {
    act message {
        my $user = App::User->new();
        print $user->greeting(), "\n";
    }
}
VEYRA
    'formats the operation header, body, and closing brace',
);

my $body_clean = run_command(
    @cli,
    'fmt',
    '--check',
);

is(
    $body_clean->{status},
    0,
    'body formatting is stable on the next check',
);

is(
    $body_clean->{stdout},
    "All source files are formatted.\n",
    'a formatted body produces no further diff',
);

write_file($main, $main_source);

my $invalid_user = <<'VEYRA';
class App::User{fun greeting{print "missing return";}}
VEYRA

write_file($user, $invalid_user);

for my $arguments (
    ['fmt'],
    ['fmt', '--check'],
) {
    my $label = join ' ', @$arguments;

    my $invalid = run_command(
        @cli,
        @$arguments,
    );

    is(
        $invalid->{status},
        1 << 8,
        "$label rejects a project that fails compiler validation",
    );

    like(
        $invalid->{stderr},
        qr/must end with an unconditional/,
        "$label preserves the compiler diagnostic",
    );

    is(
        $invalid->{stdout},
        '',
        "$label prints no success message or diff after validation failure",
    );

    is(
        read_file($main),
        $main_source,
        "$label leaves the entry source unchanged after failure",
    );

    is(
        read_file($user),
        $invalid_user,
        "$label leaves the invalid source unchanged",
    );
}

for my $arguments (
    ['fmt', '--unknown'],
    ['fmt', '--check', 'extra'],
    ['fmt', '--'],
) {
    my $label = join ' ', @$arguments;

    my $result = run_command(
        @cli,
        @$arguments,
    );

    is(
        $result->{status},
        2 << 8,
        "$label is a usage error",
    );

    like(
        $result->{stderr},
        qr/Usage:/,
        "$label reports usage",
    );

    is(
        $result->{stdout},
        '',
        "$label prints no formatting output",
    );
}

opendir my $directory_handle, $source_directory
    or die "Cannot inspect source directory "
        . "'$source_directory': $!";

my @temporary_outputs = sort grep {
    /\A\.veyra-fmt-/
} readdir $directory_handle;

closedir $directory_handle
    or die "Cannot close source directory "
        . "'$source_directory': $!";

is_deeply(
    \@temporary_outputs,
    [],
    'formatter leaves no staged output files',
);

chdir $distribution
    or die "Cannot restore working directory: $!";

done_testing;
