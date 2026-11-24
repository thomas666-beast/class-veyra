use strict;
use warnings;

use Test::More;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

use Class::Veyra::FileCompiler;

sub write_file {
    my ($path, $text) = @_;

    open my $handle, '>:raw', $path
        or die "Cannot write test file '$path': $!";

    print {$handle} $text
        or die "Cannot write test file '$path': $!";

    close $handle
        or die "Cannot close test file '$path': $!";
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

my $src = File::Spec->catdir($root, 'src');
my $vendor = File::Spec->catdir($root, 'vendor');

make_path(
    File::Spec->catdir($src, 'CliModule'),
    File::Spec->catdir($vendor, 'CliModule'),
);

write_file(
    File::Spec->catfile($src, 'CliModule', 'Main.veyra'),
    <<'VEYRA',
import CliModule::Parent;

class CliModule::Main extends CliModule::Parent {}
VEYRA
);

write_file(
    File::Spec->catfile($vendor, 'CliModule', 'Parent.veyra'),
    <<'VEYRA',
class CliModule::Parent {
    fun value {
        return 42;
    }
}
VEYRA
);

my $output = File::Spec->catfile($root, 'Main.pm');

my @module_arguments = (
    '--module', 'CliModule::Main',
    '-I', $src,
    '--include', $vendor,
    '--output', $output,
);

my $success = run_cli(@module_arguments);

is(
    $success->{status},
    0,
    'module CLI compilation succeeds with repeated include options',
);

is(
    $success->{stdout},
    '',
    'successful compilation writes no standard output',
);

is(
    $success->{stderr},
    '',
    'successful compilation writes no standard error',
);

ok(
    -f $output,
    'creates the generated output file',
);

my $generated = read_file($output);

like(
    $generated,
    qr/class CliModule::Main :isa\(CliModule::Parent\)/,
    'output includes the entry class and qualified inheritance',
);

like(
    $generated,
    qr/class CliModule::Parent \{/,
    'output includes the imported parent',
);

my $existing = run_cli(@module_arguments);

is(
    $existing->{status},
    1 << 8,
    'existing output is a compilation failure',
);

like(
    $existing->{stderr},
    qr/existing files are not overwritten/,
    'explains overwrite refusal',
);

is(
    read_file($output),
    $generated,
    'leaves existing output unchanged',
);

my $missing_output = File::Spec->catfile($root, 'Missing.pm');

my $missing = run_cli(
    '--module', 'Missing::Entry',
    '-I', $src,
    '-o', $missing_output,
);

is(
    $missing->{status},
    1 << 8,
    'missing module returns compilation failure',
);

like(
    $missing->{stderr},
    qr/veyra-compile: .*Cannot find Veyra source 'Missing::Entry'/,
    'reports the module-loading diagnostic',
);

ok(
    !-e $missing_output,
    'does not create output when module collection fails',
);

my $no_include = run_cli(
    '--module', 'CliModule::Main',
    '-o', File::Spec->catfile($root, 'NoInclude.pm'),
);

is(
    $no_include->{status},
    2 << 8,
    'module mode requires an include directory',
);

my $extra_input = run_cli(
    '--module', 'CliModule::Main',
    '-I', $src,
    '-o', File::Spec->catfile($root, 'Extra.pm'),
    'extra.veyra',
);

is(
    $extra_input->{status},
    2 << 8,
    'module mode rejects positional input',
);

my $legacy_input = File::Spec->catfile($root, 'Legacy.veyra');
my $legacy_output = File::Spec->catfile($root, 'Legacy.pm');

write_file(
    $legacy_input,
    'class CliLegacy {}',
);

my $legacy = run_cli(
    '-o', $legacy_output,
    $legacy_input,
);

is(
    $legacy->{status},
    0,
    'preserves positional file compilation',
);

like(
    read_file($legacy_output),
    qr/class CliLegacy \{/,
    'legacy mode still generates its input class',
);

my $legacy_include = run_cli(
    '-I', $src,
    '-o', File::Spec->catfile($root, 'LegacyInclude.pm'),
    $legacy_input,
);

is(
    $legacy_include->{status},
    2 << 8,
    'rejects include options outside module mode',
);

my $help = run_cli('--help');

is(
    $help->{status},
    0,
    'help succeeds',
);

like(
    $help->{stdout},
    qr/--module NAME/,
    'help documents module mode',
);

my $api_output = File::Spec->catfile($root, 'Api.pm');

is(
    Class::Veyra::FileCompiler->compile_module_file(
        'CliModule::Main',
        $api_output,
        include_paths => [$src, $vendor],
    ),
    $api_output,
    'file compiler module API returns the output path',
);

is(
    read_file($api_output),
    $generated,
    'CLI and file compiler API generate the same output',
);

done_testing;
