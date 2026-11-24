use strict;
use warnings;

use Test::More;

use Class::Veyra::Parser;
use Class::Veyra::InterfaceParser;
use Class::Veyra::Compiler;

sub parse_error {
    my ($source) = @_;

    my $completed = eval {
        Class::Veyra::Parser->parse($source);
        1;
    };

    my $error = $@;

    return $completed ? '' : $error;
}

my $sources = [
    {
        source_name => 'src/Example/Employee.veyra',
        source      => <<'VEYRA',
class VeyraQualified::Employee
    extends VeyraQualified::Person
    implements VeyraQualified::Contracts::Named
{
    fun description {
        return "employee";
    }
}
VEYRA
    },
    {
        source_name => 'src/Example/Person.veyra',
        source      => <<'VEYRA',
interface VeyraQualified::Contracts::Named {
    fun name;
    act rename ($new_name);
}

class VeyraQualified::Person {
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

my $project =
    Class::Veyra::Compiler->analyze_sources($sources);

is(
    $project->{classes}[0]{name},
    'VeyraQualified::Employee',
    'parses a qualified child name',
);

is(
    $project->{classes}[1]{name},
    'VeyraQualified::Person',
    'parses a qualified parent name',
);

is(
    $project->{interfaces}[0]{name},
    'VeyraQualified::Contracts::Named',
    'parses a multi-segment interface name',
);

is(
    $project->{classes}[0]{parent},
    'VeyraQualified::Person',
    'preserves the qualified parent reference',
);

is_deeply(
    $project->{classes}[0]{implements},
    ['VeyraQualified::Contracts::Named'],
    'preserves the qualified interface reference',
);

my $standalone_interface =
    Class::Veyra::InterfaceParser->parse(
        'interface Standalone::Contracts::Named { fun name; }'
    );

is(
    $standalone_interface->{name},
    'Standalone::Contracts::Named',
    'standalone interface parser supports qualified names',
);

my $generated =
    Class::Veyra::Compiler->compile_sources($sources);

like(
    $generated,
    qr/class VeyraQualified::Employee :isa\(VeyraQualified::Person\)/,
    'generates qualified native inheritance',
);

my $parent_position =
    index $generated, 'class VeyraQualified::Person {';

my $child_position =
    index $generated, 'class VeyraQualified::Employee :isa(';

ok(
    $parent_position >= 0
        && $child_position > $parent_position,
    'orders qualified classes parent-first',
);

my $runner = <<'PERL';

my $person = VeyraQualified::Employee->new(
    name => 'Alice',
);

die "Qualified parent identity failed\n"
    unless $person->isa('VeyraQualified::Person');

die "Inherited fun failed\n"
    unless $person->name eq 'Alice';

die "Qualified override failed\n"
    unless $person->description eq 'employee';

my @result = $person->rename('Bob');

die "Inherited act returned values\n"
    if @result;

die "Inherited act failed\n"
    unless $person->name eq 'Bob';

die "Interface became a runtime parent\n"
    if $person->isa('VeyraQualified::Contracts::Named');

print "VEYRA_QUALIFIED_PROJECT_OK\n";
PERL

my $pid = open my $child, '-|',
    $^X,
    '-e',
    $generated . "\n" . $runner;

unless (defined $pid) {
    BAIL_OUT("Cannot start qualified project test: $!");
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
    'qualified project process does not terminate by signal',
);

is(
    $status >> 8,
    0,
    'qualified project executes successfully',
);

is(
    $stdout,
    "VEYRA_QUALIFIED_PROJECT_OK\n",
    'qualified classes and inherited operations work at runtime',
);

isnt(
    parse_error('class MyApp :: Person {}'),
    '',
    'rejects spaces inside a qualified declaration name',
);

isnt(
    parse_error('class Child extends MyApp:: {}'),
    '',
    'rejects an incomplete qualified parent name',
);

isnt(
    parse_error('interface MyApp:::Named {}'),
    '',
    'rejects a malformed qualified interface name',
);

isnt(
    parse_error(
        'class Example { fun MyApp::value { return 1; } }'
    ),
    '',
    'does not enable qualified operation names',
);

done_testing;
