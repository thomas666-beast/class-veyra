use strict;
use warnings;

use Test::More;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

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

    return $path;
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

sub run_cli {
    my (@arguments) = @_;

    my $error_handle = gensym;

    my $pid = open3(
        my $input,
        my $output,
        $error_handle,
        $^X,
        '-Iblib/lib',
        '-Ilib',
        'script/veyra-compile',
        @arguments,
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

my $root = tempdir(CLEANUP => 1);

write_source(
    $root,
    'Failure::Missing',
    <<'VEYRA',
import Failure::Middle;
class Failure::Missing {}
VEYRA
);

write_source(
    $root,
    'Failure::Middle',
    <<'VEYRA',
import Failure::Absent;
class Failure::Middle {}
VEYRA
);

write_source(
    $root,
    'Failure::Mismatch',
    <<'VEYRA',
import Failure::WrongName;
class Failure::Mismatch {}
VEYRA
);

write_source(
    $root,
    'Failure::WrongName',
    'class Failure::SomethingElse {}',
);

write_source(
    $root,
    'Failure::Named',
    <<'VEYRA',
interface Failure::Named {
    fun name;
}
VEYRA
);

write_source(
    $root,
    'Failure::Contract',
    <<'VEYRA',
import Failure::Named;

class Failure::Contract implements Failure::Named {}
VEYRA
);

write_source(
    $root,
    'Failure::CycleA',
    <<'VEYRA',
import Failure::CycleB;
class Failure::CycleA extends Failure::CycleB {}
VEYRA
);

write_source(
    $root,
    'Failure::CycleB',
    <<'VEYRA',
import Failure::CycleA;
class Failure::CycleB extends Failure::CycleA {}
VEYRA
);

my @cases = (
    {
        name  => 'Failure::Missing',
        label => 'missing transitive import',
    },
    {
        name  => 'Failure::Mismatch',
        label => 'mismatched imported declaration',
    },
    {
        name  => 'Failure::Contract',
        label => 'unmet imported interface contract',
    },
    {
        name  => 'Failure::CycleA',
        label => 'cross-file inheritance cycle',
    },
);

my %results;

for my $case (@cases) {
    my $filename = $case->{name};
    $filename =~ s/::/-/g;

    my $output_path = File::Spec->catfile(
        $root,
        "$filename.pm",
    );

    my $result = run_cli(
        '--module', $case->{name},
        '-I', $root,
        '--output', $output_path,
    );

    $results{ $case->{name} } = $result;

    is(
        $result->{status},
        1 << 8,
        "$case->{label}: returns compilation failure",
    );

    is(
        $result->{stdout},
        '',
        "$case->{label}: produces no standard output",
    );

    like(
        $result->{stderr},
        qr/\Aveyra-compile: \S/,
        "$case->{label}: reports a compilation diagnostic",
    );

    ok(
        !-e $output_path,
        "$case->{label}: creates no output file",
    );
}

like(
    $results{'Failure::Missing'}{stderr},
    qr/Import 'Failure::Middle'.*Import 'Failure::Absent'.*Cannot find Veyra source 'Failure::Absent'/s,
    'missing transitive dependency reports the import chain',
);

like(
    $results{'Failure::Mismatch'}{stderr},
    qr/does not declare 'Failure::WrongName'/,
    'mismatched dependency reports the requested declaration',
);

write_source(
    $root,
    'Failure::Absent',
    'class Failure::Absent {}',
);

my $recovered_output = File::Spec->catfile(
    $root,
    'Failure-Missing.pm',
);

my $recovered = run_cli(
    '--module', 'Failure::Missing',
    '-I', $root,
    '--output', $recovered_output,
);

is(
    $recovered->{status},
    0,
    'correcting the missing dependency permits a later build',
);

is(
    $recovered->{stderr},
    '',
    'the recovered build produces no error diagnostics',
);

like(
    -f $recovered_output
        ? read_file($recovered_output)
        : '',
    qr/class Failure::Absent \{/,
    'the recovered bundle includes the corrected dependency',
);

done_testing;
