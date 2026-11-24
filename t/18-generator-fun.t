use strict;
use warnings;

use Test::More;

use Class::Veyra::Compiler;

my $source = <<'VEYRA';
class VeyraGeneratedPerson {
    field $name :param;

    fun name {
        return $name;
    }

    fun greeting {
        return "Hello, $name";
    }

    fun nothing {
        return undef;
    }

    fun snapshot {
        return { name => $name };
    }
}
VEYRA

my $generated =
    Class::Veyra::Compiler->compile($source);

like(
    $generated,
    qr/class VeyraGeneratedPerson \{/,
    'generates a native class',
);

like(
    $generated,
    qr/field \$name :param;/,
    'generates a constructor parameter field',
);

like(
    $generated,
    qr/method name \(\)/,
    'generates an explicit zero-argument method',
);

unlike(
    $generated,
    qr/use Class::Veyra/,
    'generated code does not load Class::Veyra',
);

my $loaded = eval $generated;
my $load_error = $@;

ok(
    $loaded,
    'generated Perl compiles and loads',
) or diag $load_error;

unless ($loaded) {
    done_testing;
    exit;
}

my $alice = VeyraGeneratedPerson->new(
    name => 'Alice',
);

my $bob = VeyraGeneratedPerson->new(
    name => 'Bob',
);

isa_ok(
    $alice,
    'VeyraGeneratedPerson',
);

is(
    $alice->name,
    'Alice',
    'generated fun reads a private field',
);

is(
    $alice->greeting,
    'Hello, Alice',
    'generated fun interpolates a field',
);

is(
    $bob->name,
    'Bob',
    'instances keep independent field values',
);

is(
    $alice->nothing,
    undef,
    'generated fun can return undef',
);

is_deeply(
    $alice->snapshot,
    { name => 'Alice' },
    'generated fun can return a reference',
);

my @names = $alice->name;

is_deeply(
    \@names,
    ['Alice'],
    'fun returns one value in list context',
);

my @nothing = $alice->nothing;

is(
    scalar @nothing,
    1,
    'undef is one returned value, not an empty list',
);

my $accepted_extra_argument = eval {
    $alice->name('unexpected');
    1;
};

ok(
    !$accepted_extra_argument,
    'zero-argument fun rejects extra arguments',
);

sub compile_error {
    my ($source) = @_;

    my $completed = eval {
        Class::Veyra::Compiler->compile($source);
        1;
    };

    my $error = $@;

    return $completed ? '' : $error;
}

like(
    Class::Veyra::Compiler->compile(
        'class Example { act reset {} }'
    ),
    qr/method reset \(\)/,
    'supports act generation',
);

like(
    Class::Veyra::Compiler->compile(
        'class Example { fun echo ($value) { return $value; } }'
    ),
    qr/method echo \(\$value\)/,
    'supports argument generation',
);

like(
    Class::Veyra::Compiler->compile(
        'class Parent {} class Child extends Parent {}'
    ),
    qr/class Child :isa\(Parent\)/,
    'supports inheritance generation',
);

like(
    Class::Veyra::Compiler->compile(
        'class Parent {} class Child extends Parent {}'
    ),
    qr/class Child :isa\(Parent\)/,
    'supports inheritance generation',
);

like(
    compile_error('class Example { fun new { return 1; } }'),
    qr/operation name 'new' is reserved/,
    'protects the generated constructor name',
);

done_testing;
