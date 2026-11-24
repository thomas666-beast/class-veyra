use strict;
use warnings;

use Test::More;

use Class::Veyra::Parser;
use Class::Veyra::Inheritance;

sub resolve_source {
    my ($source) = @_;

    return Class::Veyra::Inheritance->resolve(
        Class::Veyra::Parser->parse($source)
    );
}

sub inheritance_error {
    my ($source) = @_;

    my $completed = eval {
        resolve_source($source);
        1;
    };

    my $error = $@;

    return $completed ? '' : $error;
}

my $source = <<'VEYRA';
interface Named {
    fun name;
}

class Employee extends Person implements Named {
    fun employee_id {
        return 42;
    }
}

class Person {
    fun name {
        return "Alice";
    }

    act rename ($value) {
    }
}
VEYRA

my $document = Class::Veyra::Parser->parse($source);

is(
    $document->{classes}[0]{parent},
    'Person',
    'parses a parent class',
);

is_deeply(
    $document->{classes}[0]{implements},
    ['Named'],
    'allows implements after extends',
);

is(
    $document->{classes}[1]{parent},
    undef,
    'root class has no parent',
);

my $resolved =
    Class::Veyra::Inheritance->resolve($document);

is_deeply(
    $resolved->{order},
    [qw(Person Employee)],
    'resolves parents before children despite source order',
);

is_deeply(
    [sort keys %{ $resolved->{operations}{Employee} }],
    [qw(employee_id name rename)],
    'child has inherited and local operations',
);

is(
    $resolved->{operations}{Employee}{name},
    $resolved->{operations}{Person}{name},
    'unmodified inherited operation refers to the parent declaration',
);

my $override = resolve_source(<<'VEYRA');
class Parent {
    fun value ($input) {
        return $input;
    }
}

class Child extends Parent {
    fun value ($different_name) {
        return $different_name + 1;
    }
}
VEYRA

is(
    $override->{operations}{Child}{value}{parameters}[0]{name},
    'different_name',
    'valid override replaces the inherited declaration',
);

my $chain = resolve_source(
    'class A { act go {} } '
    . 'class B extends A {} '
    . 'class C extends B {}'
);

ok(
    exists $chain->{operations}{C}{go},
    'inherits operations through multiple generations',
);

like(
    inheritance_error('class Child extends Missing {}'),
    qr/unknown parent 'Missing'/,
    'rejects unknown parents',
);

like(
    inheritance_error(
        'interface Named {} class Child extends Named {}'
    ),
    qr/parent 'Named' is an interface/,
    'rejects an interface as a parent class',
);

like(
    inheritance_error('class A extends A {}'),
    qr/Inheritance cycle: A -> A/,
    'rejects direct self-inheritance',
);

like(
    inheritance_error(
        'class A extends B {} class B extends A {}'
    ),
    qr/Inheritance cycle: A -> B -> A/,
    'rejects inheritance cycles',
);

like(
    inheritance_error(
        'class A { fun name { return 1; } } '
        . 'class B extends A { act name {} }'
    ),
    qr/override 'name' must remain fun, found act/,
    'override cannot change operation kind',
);

like(
    inheritance_error(
        'class A { act rename ($value) {} } '
        . 'class B extends A { act rename {} }'
    ),
    qr/override 'rename' requires 1 parameter\(s\), found 0/,
    'override cannot change argument count',
);

is_deeply(
    resolve_source(''),
    {
        order      => [],
        operations => {},
    },
    'resolves an empty document',
);

done_testing;
