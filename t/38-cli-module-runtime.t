use strict;
use warnings;

use Test::More;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use IPC::Open3 qw(open3);
use Symbol qw(gensym);

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

my $root = tempdir(CLEANUP => 1);

my $src = File::Spec->catdir($root, 'src');
my $vendor = File::Spec->catdir($root, 'vendor');

make_path(
    File::Spec->catdir($src, 'CliRuntime'),
    File::Spec->catdir($src, 'CliRuntime', 'Contracts'),
    File::Spec->catdir($vendor, 'CliRuntime'),
);

write_file(
    File::Spec->catfile(
        $src,
        'CliRuntime',
        'Employee.veyra',
    ),
    <<'VEYRA',
import CliRuntime::Person;

class CliRuntime::Employee extends CliRuntime::Person {
    fun description {
        return "employee";
    }
}
VEYRA
);

write_file(
    File::Spec->catfile(
        $vendor,
        'CliRuntime',
        'Person.veyra',
    ),
    <<'VEYRA',
import CliRuntime::Contracts::Named;

class CliRuntime::Person
    implements CliRuntime::Contracts::Named
{
    field $name :param;

    fun name {
        return $name;
    }

    fun description {
        return "person";
    }

    act rename ($new_name) {
        $name = $new_name;
    }
}
VEYRA
);

write_file(
    File::Spec->catfile(
        $src,
        'CliRuntime',
        'Contracts',
        'Named.veyra',
    ),
    <<'VEYRA',
interface CliRuntime::Contracts::Named {
    fun name;
    act rename ($new_name);
}
VEYRA
);

my $output = File::Spec->catfile($root, 'Employee.pm');

my @compile_command = (
    $^X,
    '-Iblib/lib',
    '-Ilib',
    'script/veyra-compile',
    '--module', 'CliRuntime::Employee',
    '-I', $src,
    '-I', $vendor,
);

my $compiled = run_command(
    @compile_command,
    '--output', $output,
);

is(
    $compiled->{status},
    0,
    'CLI compiles an entry with transitive cross-directory imports',
);

is(
    $compiled->{stdout},
    '',
    'compilation produces no standard output',
);

is(
    $compiled->{stderr},
    '',
    'compilation produces no standard error',
);

ok(
    -f $output,
    'CLI creates the generated bundle',
);

unless (-f $output) {
    BAIL_OUT('No generated bundle is available for runtime testing');
}

my $generated = read_file($output);

like(
    $generated,
    qr/class CliRuntime::Employee :isa\(CliRuntime::Person\)/,
    'bundle contains the qualified child class',
);

my $parent_position =
    index $generated, 'class CliRuntime::Person {';

my $child_position =
    index $generated, 'class CliRuntime::Employee :isa(';

ok(
    $parent_position >= 0
        && $child_position > $parent_position,
    'bundle places the imported parent before the entry class',
);

my $runner = File::Spec->catfile($root, 'run-generated.pl');

write_file(
    $runner,
    <<'PERL'
use v5.38;
use strict;
use warnings;

my $bundle = shift @ARGV;

die "Expected an absolute bundle path\n"
    unless defined $bundle;

require $bundle;

my $employee = CliRuntime::Employee->new(
    name => 'Alice',
);

die "Native inheritance failed\n"
    unless $employee->isa('CliRuntime::Person');

my @name = $employee->name;

die "Inherited fun did not return exactly one value\n"
    unless @name == 1;

die "Inherited constructor state failed\n"
    unless $name[0] eq 'Alice';

my @description = $employee->description;

die "Override dispatch or fun result failed\n"
    unless (
        @description == 1
        && $description[0] eq 'employee'
    );

my @result = $employee->rename('Bob');

die "Inherited act returned values\n"
    if @result;

die "Inherited act did not update state\n"
    unless $employee->name eq 'Bob';

die "Interface became a runtime parent\n"
    if $employee->isa('CliRuntime::Contracts::Named');

my @veyra_modules = grep {
    m{\AClass/Veyra(?:/|\.pm\z)}
} keys %INC;

die "Generated bundle loaded Veyra modules\n"
    if @veyra_modules;

print "VEYRA_CLI_RUNTIME_OK\n";
PERL
);

my $runtime = run_command(
    $^X,
    $runner,
    File::Spec->rel2abs($output),
);

is(
    $runtime->{status} & 127,
    0,
    'generated bundle process does not terminate by signal',
);

is(
    $runtime->{status} >> 8,
    0,
    'generated bundle executes successfully in a fresh process',
);

is(
    $runtime->{stdout},
    "VEYRA_CLI_RUNTIME_OK\n",
    'runtime verifies inherited operations and no Veyra dependency',
);

is(
    $runtime->{stderr},
    '',
    'generated bundle executes without diagnostics',
);

my $second_output =
    File::Spec->catfile($root, 'Employee-again.pm');

my $recompiled = run_command(
    @compile_command,
    '--output', $second_output,
);

is(
    $recompiled->{status},
    0,
    'the same module project compiles a second time',
);

is(
    -f $second_output ? read_file($second_output) : undef,
    $generated,
    'unchanged inputs produce identical generated output',
);

done_testing;
