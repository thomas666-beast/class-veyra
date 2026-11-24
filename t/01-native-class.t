use Class::Veyra;

use Test::More;

class VeyraTest::Person {
    field $name :param;

    method name {
        return $name;
    }
}

class VeyraTest::Employee :isa(VeyraTest::Person) {
    field $employee_id :param;

    method employee_id {
        return $employee_id;
    }
}

my $person = VeyraTest::Person->new(
    name => 'Alice',
);

isa_ok(
    $person,
    'VeyraTest::Person',
);

is(
    $person->name,
    'Alice',
    'class stores and returns an instance field',
);

my $employee = VeyraTest::Employee->new(
    name        => 'Bob',
    employee_id => 42,
);

isa_ok(
    $employee,
    'VeyraTest::Employee',
);

isa_ok(
    $employee,
    'VeyraTest::Person',
);

is(
    $employee->name,
    'Bob',
    'subclass inherits a parent method and constructor parameter',
);

is(
    $employee->employee_id,
    42,
    'subclass has its own instance field',
);

is(
    $person->name,
    'Alice',
    'different objects retain independent field values',
);

done_testing;
