use strict;
use warnings;

use Test::More;

use Class::Veyra::Compiler;

my $sources = [
    {
        source_name => 'src/Employee.veyra',
        source      => <<'VEYRA',
class VeyraProjectEmployee
    extends VeyraProjectPerson
    implements VeyraProjectNamed
{
    field $title :param;

    fun title {
        return $title;
    }

    fun description {
        return "employee";
    }

    act rename_via_self ($new_name) {
        $self->rename($new_name);
    }
}
VEYRA
    },
    {
        source_name => 'src/Named.veyra',
        source      => <<'VEYRA',
interface VeyraProjectNamed {
    fun name;
    act rename ($new_name);
}
VEYRA
    },
    {
        source_name => 'src/Person.veyra',
        source      => <<'VEYRA',
class VeyraProjectPerson {
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
    },
];

my $generated;

my $compiled = eval {
    $generated =
        Class::Veyra::Compiler->compile_sources($sources);

    1;
};

my $compile_error = $@;

ok(
    $compiled,
    'compiles three sources into one project bundle',
) or diag $compile_error;

unless ($compiled) {
    done_testing;
    exit;
}

unlike(
    $generated,
    qr/use Class::Veyra/,
    'generated project does not declare a Veyra runtime dependency',
);

my $runner = <<'PERL';

my $employee = VeyraProjectEmployee->new(
    name  => 'Alice',
    title => 'Developer',
);

die "Child identity failed\n"
    unless $employee->isa('VeyraProjectEmployee');

die "Parent identity failed\n"
    unless $employee->isa('VeyraProjectPerson');

die "Interface unexpectedly became a parent\n"
    if $employee->isa('VeyraProjectNamed');

die "Inherited constructor parameter or fun failed\n"
    unless $employee->name eq 'Alice';

die "Child constructor parameter or field failed\n"
    unless $employee->title eq 'Developer';

die "Override dispatch failed\n"
    unless $employee->description eq 'employee';

my @names = $employee->name;

die "Inherited fun returned the wrong values\n"
    unless @names == 1 && $names[0] eq 'Alice';

my @renamed = $employee->rename('Bob');

die "Inherited act returned values\n"
    if @renamed;

die "Inherited act failed to update parent state\n"
    unless $employee->name eq 'Bob';

my $result = $employee->rename_via_self('Carol');

die "Child act returned a defined value\n"
    if defined $result;

die "Child-to-parent operation call failed\n"
    unless $employee->name eq 'Carol';

my $parent = VeyraProjectPerson->new(
    name => 'Parent',
);

die "Child override changed parent dispatch\n"
    unless $parent->description eq 'person';

die "Parent instance state is incorrect\n"
    unless $parent->name eq 'Parent';

die "Instance state is not independent\n"
    unless $employee->name eq 'Carol';

my @veyra_modules = grep {
    m{\AClass/Veyra(?:/|\.pm\z)}
} keys %INC;

die "Generated project loaded Veyra modules: "
    . join(', ', @veyra_modules)
    . "\n"
    if @veyra_modules;

print "VEYRA_PROJECT_RUNTIME_OK\n";
PERL

my $program = $generated . "\n" . $runner;

my $pid = open my $child, '-|',
    $^X,
    '-e',
    $program;

unless (defined $pid) {
    BAIL_OUT("Cannot start project runtime test: $!");
}

my $stdout = do {
    local $/;
    <$child>;
};

$stdout = '' unless defined $stdout;

close $child;
my $status = $?;

my $signal = $status & 127;
my $exit_code = $status >> 8;

is(
    $signal,
    0,
    'generated project process does not terminate by signal',
);

is(
    $exit_code,
    0,
    'generated project runs successfully',
);

is(
    $stdout,
    "VEYRA_PROJECT_RUNTIME_OK\n",
    'cross-file runtime checks pass without loading Veyra',
);

if ($signal || $exit_code || $stdout ne "VEYRA_PROJECT_RUNTIME_OK\n") {
    diag "Child process status: $status";
    diag "Child output: $stdout";
}

done_testing;
