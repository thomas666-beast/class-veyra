use strict;
use warnings;

use Test::More;

use Class::Veyra::Compiler;

my $source = <<'VEYRA';
class VeyraGeneratedEmployee extends VeyraGeneratedPersonBase {
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

class VeyraGeneratedPersonBase {
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

class VeyraGeneratedManager extends VeyraGeneratedEmployee {
    fun description {
        return "manager";
    }
}
VEYRA

my $generated =
    Class::Veyra::Compiler->compile($source);

like(
    $generated,
    qr/class VeyraGeneratedEmployee :isa\(VeyraGeneratedPersonBase\)/,
    'generates the employee parent declaration',
);

like(
    $generated,
    qr/class VeyraGeneratedManager :isa\(VeyraGeneratedEmployee\)/,
    'generates a second inheritance level',
);

my $parent_position =
    index $generated, 'class VeyraGeneratedPersonBase {';

my $employee_position =
    index $generated, 'class VeyraGeneratedEmployee :isa(';

my $manager_position =
    index $generated, 'class VeyraGeneratedManager :isa(';

ok(
    $parent_position >= 0
        && $employee_position > $parent_position
        && $manager_position > $employee_position,
    'emits classes parent-first despite child-first source',
);

my $loaded = eval $generated;
my $load_error = $@;

ok(
    $loaded,
    'generated inheritance hierarchy compiles and loads',
) or diag $load_error;

unless ($loaded) {
    done_testing;
    exit;
}

my $employee = VeyraGeneratedEmployee->new(
    name  => 'Alice',
    title => 'Developer',
);

isa_ok(
    $employee,
    'VeyraGeneratedEmployee',
);

isa_ok(
    $employee,
    'VeyraGeneratedPersonBase',
);

is(
    $employee->name,
    'Alice',
    'inherited constructor parameter and fun work',
);

is(
    $employee->title,
    'Developer',
    'child constructor parameter and field work',
);

is(
    $employee->description,
    'employee',
    'child override is dispatched',
);

my @rename_result = $employee->rename('Bob');

is(
    $employee->name,
    'Bob',
    'inherited act updates parent state',
);

is_deeply(
    \@rename_result,
    [],
    'inherited act preserves its void-result contract',
);

$employee->rename_via_self('Carol');

is(
    $employee->name,
    'Carol',
    'child operation can call an inherited act through self',
);

my $manager = VeyraGeneratedManager->new(
    name  => 'Dana',
    title => 'Lead',
);

isa_ok(
    $manager,
    'VeyraGeneratedPersonBase',
);

is(
    $manager->name,
    'Dana',
    'constructor parameter is inherited through two levels',
);

is(
    $manager->title,
    'Lead',
    'middle-class field and operation are inherited',
);

is(
    $manager->description,
    'manager',
    'most-derived override is dispatched',
);

$manager->rename_via_self('Erin');

is(
    $manager->name,
    'Erin',
    'inherited child operation calls inherited parent operation',
);

my $parent = VeyraGeneratedPersonBase->new(
    name => 'Parent',
);

is(
    $parent->description,
    'person',
    'child overrides do not change parent dispatch',
);

is(
    $employee->name,
    'Carol',
    'instances retain independent parent-field state',
);

done_testing;
