use strict;
use warnings;

use Test::More;

use Class::Veyra::Parser;

my $source = <<'VEYRA';
class Person {
    field $name :param;

    fun name {
        return $name;
    }
}

class Employee {
    field $id :param;

    act touch {
    }
}
VEYRA

my $document = Class::Veyra::Parser->parse($source);
my ($person, $employee) = @{ $document->{classes} };

is(scalar @{ $person->{members} }, 2, 'Person has two members');

is_deeply(
    [map { $_->{kind} } @{ $person->{members} }],
    [qw(field fun)],
    'Person member kinds',
);

is_deeply(
    [map { $_->{name} } @{ $employee->{members} }],
    [qw(id touch)],
    'Employee member names',
);

like(
    $person->{body},
    qr/field \$name/,
    'raw body is still available',
);

sub class_error {
    my ($source) = @_;

    my $completed = eval {
        Class::Veyra::Parser->parse($source);
        1;
    };

    my $error = $@;

    return $completed ? '' : $error;
}

like(
    class_error('class Bad { field name; }'),
    qr/\AClass 'Bad': /,
    'member errors name the class',
);

like(
    class_error('class A { fun x {} fun x {} }'),
    qr/Class 'A': Duplicate operation 'x'/,
    'duplicate operations are reported with the class name',
);

is(
    scalar @{
        Class::Veyra::Parser->parse(
            'class A { fun x {} } class B { fun x {} }'
        )->{classes}
    },
    2,
    'different classes may use the same operation name',
);

done_testing;
