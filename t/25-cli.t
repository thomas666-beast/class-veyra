use strict;
use warnings;

use Test::More;
use File::Spec;
use File::Temp qw(tempdir);

use Class::Veyra::Compiler;

my $script = File::Spec->catfile(
    'script',
    'veyra-compile',
);

ok(
    -f $script,
    'command-line script exists',
);

sub write_file {
    my ($path, $content) = @_;

    open my $handle, '>:raw', $path
        or die "Cannot create test file '$path': $!";

    print {$handle} $content
        or die "Cannot write test file '$path': $!";

    close $handle
        or die "Cannot close test file '$path': $!";
}

sub read_file {
    my ($path) = @_;

    open my $handle, '<:raw', $path
        or die "Cannot read test file '$path': $!";

    local $/;
    my $content = <$handle>;

    close $handle
        or die "Cannot close test file '$path': $!";

    return defined $content ? $content : '';
}

sub run_cli {
    my (@arguments) = @_;

    my $pid = open my $child, '-|',
        $^X,
        '-Ilib',
        $script,
        @arguments;

    die "Cannot start command-line compiler: $!"
        unless defined $pid;

    my $stdout = do {
        local $/;
        <$child>;
    };

    $stdout = '' unless defined $stdout;

    close $child;
    my $status = $?;

    die "Command-line compiler terminated by signal "
        . ($status & 127)
        . "\n"
        if $status & 127;

    return ($status >> 8, $stdout);
}

my ($help_status, $help_output) = run_cli('--help');

is(
    $help_status,
    0,
    'help exits successfully',
);

like(
    $help_output,
    qr/Usage:/,
    'help prints usage to standard output',
);

my $directory = tempdir(CLEANUP => 1);

my $input = File::Spec->catfile(
    $directory,
    'example source.veyra',
);

my $output = File::Spec->catfile(
    $directory,
    'example output.pm',
);

my $source = <<'VEYRA';
class VeyraCliExample {
    field $name :param;

    fun name {
        return $name;
    }
}
VEYRA

write_file($input, $source);

my ($success_status, $success_output) = run_cli(
    '--output',
    $output,
    $input,
);

is(
    $success_status,
    0,
    'valid compilation exits successfully',
);

is(
    $success_output,
    '',
    'successful compilation is silent',
);

is(
    read_file($output),
    Class::Veyra::Compiler->compile($source),
    'CLI writes the expected generated Perl',
);

my $original_output = read_file($output);

my ($existing_status) = run_cli(
    '--output',
    $output,
    $input,
);

is(
    $existing_status,
    1,
    'existing output produces a file-error exit status',
);

is(
    read_file($output),
    $original_output,
    'CLI preserves existing output',
);

my $invalid_input = File::Spec->catfile(
    $directory,
    'invalid.veyra',
);

my $invalid_output = File::Spec->catfile(
    $directory,
    'invalid.pm',
);

write_file(
    $invalid_input,
    'class VeyraCliInvalid { fun broken {} }',
);

my ($invalid_status) = run_cli(
    '-o',
    $invalid_output,
    $invalid_input,
);

is(
    $invalid_status,
    1,
    'invalid source produces a compilation-error exit status',
);

ok(
    !-e $invalid_output,
    'invalid source does not create output',
);

my ($missing_output_status) = run_cli($input);

is(
    $missing_output_status,
    2,
    'missing output option produces a usage-error exit status',
);

my ($missing_input_status) = run_cli(
    '--output',
    $output,
);

is(
    $missing_input_status,
    2,
    'missing input produces a usage-error exit status',
);

my ($unknown_option_status) = run_cli(
    '--unknown-option',
);

is(
    $unknown_option_status,
    2,
    'unknown option produces a usage-error exit status',
);

done_testing;
