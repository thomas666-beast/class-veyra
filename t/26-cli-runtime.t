use strict;
use warnings;

use Test::More;
use File::Spec;
use File::Temp qw(tempdir);

my $script = File::Spec->catfile(
    'blib',
    'script',
    'veyra-compile',
);

unless (-f $script) {
    plan skip_all =>
        'Build the staged script with make before running this test';
}

sub write_file {
    my ($path, $content) = @_;

    open my $handle, '>:raw', $path
        or die "Cannot create test file '$path': $!";

    print {$handle} $content
        or die "Cannot write test file '$path': $!";

    close $handle
        or die "Cannot close test file '$path': $!";
}

sub run_perl {
    my (@arguments) = @_;

    my $pid = open my $child, '-|',
        $^X,
        @arguments;

    die "Cannot start Perl subprocess: $!"
        unless defined $pid;

    my $stdout = do {
        local $/;
        <$child>;
    };

    $stdout = '' unless defined $stdout;

    close $child;
    my $status = $?;

    die "Perl subprocess terminated by signal "
        . ($status & 127)
        . "\n"
        if $status & 127;

    return ($status >> 8, $stdout);
}

my $directory = tempdir(
    TMPDIR  => 1,
    CLEANUP => 1,
);

my $input = File::Spec->catfile(
    $directory,
    'standalone source.veyra',
);

my $output = File::Spec->catfile(
    $directory,
    'standalone output.pm',
);

my $source = <<'VEYRA';
interface VeyraStandaloneNamed {
    fun name;
    act rename ($new_name);
}

class VeyraStandalonePerson implements VeyraStandaloneNamed {
    field $name :param;

    fun name {
        return $name;
    }

    act rename ($new_name) {
        $name = $new_name;
    }
}
VEYRA

write_file($input, $source);

my ($compile_status, $compile_stdout) = run_perl(
    '-Mblib',
    $script,
    '--output',
    $output,
    $input,
);

is(
    $compile_status,
    0,
    'staged CLI compiles interface-bearing source',
);

is(
    $compile_stdout,
    '',
    'staged CLI is silent on success',
);

ok(
    -f $output,
    'staged CLI creates the generated file',
);

unless ($compile_status == 0 && -f $output) {
    done_testing;
    exit;
}

my $runner = <<'PERL';
use strict;
use warnings;

my $path = shift @ARGV;

die "Missing generated file path\n"
    unless defined $path;

my $loaded = do $path;
my $load_error = $@;
my $os_error = "$!";

die "Generated code failed: $load_error\n"
    if length $load_error;

die "Cannot load generated file: $os_error\n"
    unless defined $loaded;

die "Generated file returned false\n"
    unless $loaded;

my $person = VeyraStandalonePerson->new(
    name => 'Alice',
);

die "Constructor or fun failed\n"
    unless $person->name eq 'Alice';

my @names = $person->name;

die "Fun did not return exactly one value\n"
    unless @names == 1 && $names[0] eq 'Alice';

my @renamed = $person->rename('Bob');

die "Act returned values in list context\n"
    if @renamed;

die "Act did not update the field\n"
    unless $person->name eq 'Bob';

my $renamed = $person->rename('Carol');

die "Act returned a defined value in scalar context\n"
    if defined $renamed;

die "Second rename failed\n"
    unless $person->name eq 'Carol';

die "Interface unexpectedly became a parent class\n"
    if $person->isa('VeyraStandaloneNamed');

my @veyra_modules = grep {
    m{\AClass/Veyra(?:/|\.pm\z)}
} keys %INC;

die "Generated code loaded Class::Veyra modules: "
    . join(', ', @veyra_modules)
    . "\n"
    if @veyra_modules;

print "VEYRA_STANDALONE_OK\n";
PERL

my ($runtime_status, $runtime_stdout) = run_perl(
    '-e',
    $runner,
    $output,
);

is(
    $runtime_status,
    0,
    'generated file runs successfully in a fresh Perl process',
);

is(
    $runtime_stdout,
    "VEYRA_STANDALONE_OK\n",
    'standalone runtime checks pass without loading Class::Veyra',
);

done_testing;
