use strict;
use warnings;

use Test::More;

use Class::Veyra::Compiler;

my $source = <<'VEYRA';
interface Named {
    fun name;
    act rename ($new_name);
}

class Employee extends Person implements Named {
    fun employee_id {
        return 42;
    }
}

class Person {
    field $name :param;

    fun name {
        return $name;
    }

    act rename ($value) {
        $name = $value;
    }
}
VEYRA

my $document =
    Class::Veyra::Compiler->analyze($source);

is(
    $document->{kind},
    'document',
    'analysis returns a document AST',
);

is_deeply(
    [map { $_->{name} } @{ $document->{classes} }],
    [qw(Employee Person)],
    'analysis preserves class declaration order',
);

is_deeply(
    [map { $_->{name} } @{ $document->{interfaces} }],
    ['Named'],
    'analysis preserves interfaces',
);

is(
    $document->{classes}[0]{parent},
    'Person',
    'analysis preserves inheritance declarations',
);

is_deeply(
    $document->{classes}[0]{implements},
    ['Named'],
    'analysis preserves interface declarations',
);

is_deeply(
    Class::Veyra::Compiler->analyze('')->{declarations},
    [],
    'accepts an empty document',
);

sub analyze_error {
    my ($source) = @_;

    my $completed = eval {
        Class::Veyra::Compiler->analyze($source);
        1;
    };

    my $error = $@;

    return $completed ? '' : $error;
}

like(
    analyze_error(undef),
    qr/Compiler requires a defined source string/,
    'rejects undefined input',
);

like(
    analyze_error([]),
    qr/Compiler source must not be a reference/,
    'rejects reference input',
);

like(
    analyze_error('class Person { field name; }'),
    qr/Expected '\$'/,
    'runs declaration parsing',
);

like(
    analyze_error(
        'class Calculator { '
        . 'fun half ($value) { return $value / 2; } }'
    ),
    qr/Unsupported symbol '\/'/,
    'runs the syntax guard',
);

like(
    analyze_error(
        'class Person { act rename { return 1; } }'
    ),
    qr/act 'rename' must not return a value/,
    'checks act return contracts',
);

like(
    analyze_error(
        'class Person { fun name {} }'
    ),
    qr/must end with an unconditional/,
    'checks fun return contracts',
);

like(
    analyze_error('class Employee extends Missing {}'),
    qr/unknown parent 'Missing'/,
    'resolves parent classes',
);

like(
    analyze_error(
        'class A extends B {} class B extends A {}'
    ),
    qr/Inheritance cycle/,
    'rejects inheritance cycles',
);

like(
    analyze_error('class Person implements Missing {}'),
    qr/unknown interface 'Missing'/,
    'checks interface references',
);

like(
    analyze_error(
        'interface Named { fun name; } '
        . 'class Person implements Named {}'
    ),
    qr/missing fun 'name'/,
    'checks required implementations',
);

like(
    analyze_error(
        'class Parent { fun value { return 1; } } '
        . 'class Child extends Parent { act value {} }'
    ),
    qr/override 'value' must remain fun/,
    'checks override compatibility',
);

like(
    analyze_error(
        'class Example { act run { '
        . 'my $callback = sub { return 1; }; } }'
    ),
    qr/Unsupported word 'sub'/,
    'compiler rejects nested subs even if a component accepts them',
);

like(
    analyze_error(
        'class Example { act run { return 1 / 2; } }'
    ),
    qr/Unsupported symbol '\/'/,
    'syntax validation runs before return-contract validation',
);

my $unchanged = $source;

Class::Veyra::Compiler->analyze($source);

is(
    $source,
    $unchanged,
    'analysis does not modify the input source',
);

done_testing;
