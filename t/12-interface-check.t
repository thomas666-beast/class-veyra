use strict;
use warnings;

use Test::More;

use Class::Veyra::Parser;
use Class::Veyra::Contract;
use Class::Veyra::InterfaceCheck;

sub check_error {
    my ($source) = @_;

    my $completed = eval {
        my $document =
            Class::Veyra::Parser->parse($source);

        Class::Veyra::Contract->validate($document);
        Class::Veyra::InterfaceCheck->validate($document);

        1;
    };

    my $error = $@;

    return $completed ? '' : $error;
}

my $valid_source = <<'VEYRA';
interface Named {
    fun name;
    act rename ($new_name);
}

class Person implements Named {
    field $name :param;

    fun name {
        return $name;
    }

    act rename ($value) {
        $name = $value;
    }
}
VEYRA

is(
    check_error($valid_source),
    '',
    'class satisfies an interface even when parameter names differ',
);

my $document =
    Class::Veyra::Parser->parse($valid_source);

is_deeply(
    $document->{classes}[0]{implements},
    ['Named'],
    'parser records implemented interfaces',
);

is_deeply(
    Class::Veyra::Parser->parse(
        'class Person {}'
    )->{classes}[0]{implements},
    [],
    'classes without implements have an empty list',
);

my $multiple_source = <<'VEYRA';
interface Named {
    fun name;
}

interface Resettable {
    act reset;
}

class Person implements Named, Resettable {
    fun name {
        return "Alice";
    }

    act reset {
    }
}
VEYRA

is(
    check_error($multiple_source),
    '',
    'class can implement multiple interfaces',
);

is(
    check_error(
        'class Person implements Marker {} interface Marker {}'
    ),
    '',
    'interface may be declared after its implementing class',
);

like(
    check_error('class Person implements Missing {}'),
    qr/unknown interface 'Missing'/,
    'rejects unknown interfaces',
);

like(
    check_error(
        'class Named {} class Person implements Named {}'
    ),
    qr/'Named' is a class, not an interface/,
    'rejects a class used as an interface',
);

like(
    check_error(
        'interface Named { fun name; } '
        . 'class Person implements Named {}'
    ),
    qr/missing fun 'name'/,
    'rejects missing operations',
);

like(
    check_error(
        'interface Named { fun name; } '
        . 'class Person implements Named { field $name; }'
    ),
    qr/missing fun 'name'/,
    'a field does not satisfy an operation requirement',
);

like(
    check_error(
        'interface Named { fun name; } '
        . 'class Person implements Named { act name {} }'
    ),
    qr/operation 'name' must be fun, found act/,
    'checks operation kind',
);

like(
    check_error(
        'interface Renamable { act rename ($value); } '
        . 'class Person implements Renamable { act rename {} }'
    ),
    qr/requires 1 parameter\(s\), found 0/,
    'rejects too few parameters',
);

like(
    check_error(
        'interface Named { fun name; } '
        . 'class Person implements Named { '
        . 'fun name ($extra) { return $extra; } }'
    ),
    qr/requires 0 parameter\(s\), found 1/,
    'rejects too many parameters',
);

like(
    check_error(
        'interface Named {} '
        . 'class Person implements Named, Named {}'
    ),
    qr/Duplicate implemented interface 'Named'/,
    'rejects repeated interface names',
);

like(
    check_error(
        'interface Named {} '
        . 'class Person implements Named, {}'
    ),
    qr/Expected identifier/,
    'rejects a trailing interface-list comma',
);

is(
    check_error(
        'interface Named { fun name (); } '
        . 'class Person implements Named { '
        . 'fun name { return "Alice"; } }'
    ),
    '',
    'omitted and explicit empty signatures both require zero arguments',
);

is(
    Class::Veyra::InterfaceCheck->validate($document),
    1,
    'validator returns true on success',
);

done_testing;
