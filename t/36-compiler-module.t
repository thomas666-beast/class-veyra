use strict;
use warnings;

use Test::More;

use Cwd qw(abs_path);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);

use Class::Veyra::Compiler;
use Class::Veyra::SourceCollector;

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

    return abs_path($path);
}

sub error_from {
    my ($code) = @_;

    my $completed = eval {
        $code->();
        1;
    };

    my $error = $@;

    return $completed ? '' : $error;
}

my $root = tempdir(CLEANUP => 1);

my $employee_path = write_source(
    $root,
    'ModuleDemo::Employee',
    <<'VEYRA',
import ModuleDemo::Person;
import ModuleDemo::Contracts::Named;

class ModuleDemo::Employee
    extends ModuleDemo::Person
    implements ModuleDemo::Contracts::Named
{
    fun description {
        return "employee";
    }
}
VEYRA
);

my $person_path = write_source(
    $root,
    'ModuleDemo::Person',
    <<'VEYRA',
class ModuleDemo::Person {
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

my $interface_path = write_source(
    $root,
    'ModuleDemo::Contracts::Named',
    <<'VEYRA',
interface ModuleDemo::Contracts::Named {
    fun name;
    act rename ($new_name);
}
VEYRA
);

my $project = Class::Veyra::Compiler->analyze_module(
    'ModuleDemo::Employee',
    include_paths => [$root],
);

is(
    $project->{source_name},
    '<project>',
    'module analysis returns a project document',
);

is(
    scalar @{ $project->{classes} },
    2,
    'analyzes the entry class and imported parent',
);

is(
    scalar @{ $project->{interfaces} },
    1,
    'analyzes an imported interface',
);

is_deeply(
    [map { $_->{source_name} } @{ $project->{sources} }],
    [
        $employee_path,
        $person_path,
        $interface_path,
    ],
    'preserves collected source names and order',
);

is(
    $project->{sources}[0]{imports}[0]{name},
    'ModuleDemo::Person',
    'retains import metadata in source documents',
);

my $generated = Class::Veyra::Compiler->compile_module(
    'ModuleDemo::Employee',
    include_paths => [$root],
);

like(
    $generated,
    qr/class ModuleDemo::Employee :isa\(ModuleDemo::Person\)/,
    'module compilation generates qualified inheritance',
);

my $collector = Class::Veyra::SourceCollector->new(
    include_paths => [$root],
);

is(
    $generated,
    Class::Veyra::Compiler->compile_sources(
        $collector->collect('ModuleDemo::Employee'),
    ),
    'module compilation uses the existing project pipeline',
);

my $runner = <<'PERL';

my $employee = ModuleDemo::Employee->new(
    name => 'Alice',
);

die "Inherited constructor or fun failed\n"
    unless $employee->name eq 'Alice';

die "Override dispatch failed\n"
    unless $employee->description eq 'employee';

my @result = $employee->rename('Bob');

die "Act returned values\n"
    if @result;

die "Inherited state update failed\n"
    unless $employee->name eq 'Bob';

die "Interface became a runtime parent\n"
    if $employee->isa('ModuleDemo::Contracts::Named');

my @veyra_modules = grep {
    m{\AClass/Veyra(?:/|\.pm\z)}
} keys %INC;

die "Generated program loaded Veyra modules\n"
    if @veyra_modules;

print "VEYRA_MODULE_OK\n";
PERL

my $pid = open my $child, '-|',
    $^X,
    '-e',
    $generated . "\n" . $runner;

unless (defined $pid) {
    BAIL_OUT("Cannot start module runtime test: $!");
}

my $stdout = do {
    local $/;
    <$child>;
};

$stdout = '' unless defined $stdout;

close $child;
my $status = $?;

is(
    $status & 127,
    0,
    'module runtime process does not terminate by signal',
);

is(
    $status >> 8,
    0,
    'compiled module project executes successfully',
);

is(
    $stdout,
    "VEYRA_MODULE_OK\n",
    'imported project runs without loading Veyra modules',
);

like(
    error_from(sub {
        Class::Veyra::Compiler->analyze_module(
            'Missing::Entry',
            include_paths => [$root],
        );
    }),
    qr/Cannot find Veyra source 'Missing::Entry'/,
    'module analysis preserves missing-entry diagnostics',
);

like(
    error_from(sub {
        Class::Veyra::Compiler->compile_module(
            'ModuleDemo::Employee',
        );
    }),
    qr/non-empty include_paths array/,
    'module compilation requires explicit search directories',
);

write_source(
    $root,
    'Broken::Mismatch',
    'class Broken::Other {}',
);

like(
    error_from(sub {
        Class::Veyra::Compiler->analyze_module(
            'Broken::Mismatch',
            include_paths => [$root],
        );
    }),
    qr/does not declare 'Broken::Mismatch'/,
    'module analysis preserves declaration-name checks',
);

write_source(
    $root,
    'Broken::Contract',
    <<'VEYRA',
import ModuleDemo::Contracts::Named;

class Broken::Contract
    implements ModuleDemo::Contracts::Named
{}
VEYRA
);

isnt(
    error_from(sub {
        Class::Veyra::Compiler->compile_module(
            'Broken::Contract',
            include_paths => [$root],
        );
    }),
    '',
    'module compilation validates imported interface obligations',
);

write_source(
    $root,
    'Broken::Duplicates',
    <<'VEYRA',
import ModuleDemo::Person;

class Broken::Duplicates {}

class ModuleDemo::Person {}
VEYRA
);

like(
    error_from(sub {
        Class::Veyra::Compiler->analyze_module(
            'Broken::Duplicates',
            include_paths => [$root],
        );
    }),
    qr/Duplicate declaration 'ModuleDemo::Person'/,
    'module analysis checks cross-file duplicate declarations',
);

done_testing;
