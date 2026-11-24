use strict;
use warnings;

use Test::More;

use Cwd qw(getcwd);
use File::Spec;
use File::Temp qw(tempdir);
use IO::Select;
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

use Class::Veyra ();

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

my $temporary = tempdir(CLEANUP => 1);

chdir $temporary
    or die "Cannot enter temporary directory: $!";

for my $command ('version', '--version') {
    my $result = run_command(
        @cli,
        $command,
    );

    is(
        $result->{status},
        0,
        "$command succeeds without a local project",
    );

    is(
        $result->{stdout},
        "veyra $Class::Veyra::VERSION\n",
        "$command reports the module version",
    );

    is(
        $result->{stderr},
        '',
        "$command produces no diagnostics",
    );
}

for my $arguments (
    ['version', 'extra'],
    ['--version', 'extra'],
    ['version', '--'],
    ['--version', '--help'],
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

    is(
        $result->{stdout},
        '',
        "$label does not print a version",
    );

    like(
        $result->{stderr},
        qr/Usage:/,
        "$label reports usage",
    );
}

my $help = run_command(
    @cli,
    'help',
);

is(
    $help->{status},
    0,
    'help still succeeds',
);

like(
    $help->{stdout},
    qr/^\s+veyra version$/m,
    'help documents the version command',
);

like(
    $help->{stdout},
    qr/^\s+veyra --version$/m,
    'help documents the version option',
);

ok(
    !-e File::Spec->catfile($temporary, 'veyra.json'),
    'version commands do not create project configuration',
);

ok(
    !-e File::Spec->catdir($temporary, 'build'),
    'version commands do not create build output',
);

chdir $distribution
    or die "Cannot restore working directory: $!";

done_testing;
