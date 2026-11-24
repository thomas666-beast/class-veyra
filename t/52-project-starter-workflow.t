use strict;
use warnings;

use Test::More;

use Cwd qw(getcwd);
use File::Spec;
use File::Temp qw(tempdir);
use IO::Select;
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

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

    my $ready = IO::Select->new(
        $output,
        $error_handle,
    );

    while ($ready->count) {
        for my $handle ($ready->can_read) {
            my $stream = $stream_for{fileno($handle)};
            my $buffer;

            my $length = sysread(
                $handle,
                $buffer,
                8192,
            );

            unless (defined $length) {
                next if $!{EINTR};

                die "Cannot read command output: $!";
            }

            if ($length == 0) {
                $ready->remove($handle);

                close $handle
                    or die "Cannot close command output: $!";

                next;
            }

            $captured{$stream} .= $buffer;
        }
    }

    waitpid $pid, 0;

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
    'veyra starter XXXX',
    TMPDIR  => 1,
    CLEANUP => 1,
);

for my $case (
    {
        name   => 'hello',
        nested => 0,
        label  => 'fresh project from its root',
    },
    {
        name   => 'nested-hello',
        nested => 1,
        label  => 'fresh project from a nested directory',
    },
) {
    subtest $case->{label} => sub {
        chdir $temporary
            or die "Cannot enter temporary directory: $!";

        my $created = run_command(
            @cli,
            'create',
            $case->{name},
        );

        is(
            $created->{status},
            0,
            'create succeeds',
        );

        is(
            $created->{stdout},
            "Created project '$case->{name}'.\n",
            'create reports the new project',
        );

        is(
            $created->{stderr},
            '',
            'create produces no diagnostics',
        );

        my $root = File::Spec->catdir(
            $temporary,
            $case->{name},
        );

        unless (-d $root) {
            fail('project directory exists');
            return;
        }

        my $build_directory = File::Spec->catdir(
            $root,
            'build',
        );

        my $output = File::Spec->catfile(
            $build_directory,
            'Main.pm',
        );

        ok(
            !-e $build_directory,
            'project has not been built',
        );

        my $working_directory = $case->{nested}
            ? File::Spec->catdir($root, 'src', 'App')
            : $root;

        chdir $working_directory
            or die "Cannot enter project directory: $!";

        my $ran = run_command(
            @cli,
            'run',
        );

        is(
            $ran->{status},
            0,
            'run succeeds without a separate build step',
        );

        is(
            $ran->{stdout},
            "Hello, world!\n",
            'untouched starter prints the expected greeting',
        );

        is(
            $ran->{stderr},
            '',
            'starter runs without diagnostics',
        );

        ok(
            -f $output,
            'run creates the configured build output',
        );

        my $ran_again = run_command(
            @cli,
            'run',
        );

        is(
            $ran_again->{status},
            0,
            'running again succeeds without deleting output',
        );

        is(
            $ran_again->{stdout},
            "Hello, world!\n",
            'repeated run prints the same greeting',
        );

        is(
            $ran_again->{stderr},
            '',
            'repeated run produces no diagnostics',
        );
    };
}

chdir $distribution
    or die "Cannot restore working directory: $!";

done_testing;
