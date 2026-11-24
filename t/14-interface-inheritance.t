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

is(
    check_error(<<'VEYRA'),
interface Named {
    fun name;
}

class Person {
    fun name {
        return "Alice";
    }
}

class Employee extends Person implements Named {
}
VEYRA
    '',
    'an inherited operation satisfies a declared interface',
);

is(
    check_error(<<'VEYRA'),
interface Named {
    fun name;
}

class Person implements Named {
    fun name {
        return "Alice";
    }
}

class Employee extends Person {
}
VEYRA
    '',
    'subclass inherits parent interface obligations',
);

is(
    check_error(<<'VEYRA'),
interface Named {
    fun name;
}

class Person implements Named {
    fun name {
        return "Alice";
    }
}

class Employee extends Person implements Named {
}
VEYRA
    '',
    'subclass may explicitly repeat an inherited interface',
);

is(
    check_error(<<'VEYRA'),
interface Named {
    fun name;
}

interface Resettable {
    act reset;
}

class Person implements Named {
    fun name {
        return "Alice";
    }
}

class Employee extends Person implements Resettable {
    act reset {
    }
}
VEYRA
    '',
    'subclass may add an interface to inherited obligations',
);

is(
    check_error(<<'VEYRA'),
interface Named {
    fun name;
}

class Person implements Named {
    fun name {
        return "Alice";
    }
}

class Employee extends Person {
    fun name {
        return "Employee";
    }
}

class Manager extends Employee {
}
VEYRA
    '',
    'valid overrides preserve an interface across generations',
);

is(
    check_error(<<'VEYRA'),
class Employee extends Person implements Named {
}

interface Named {
    fun name;
}

class Person {
    fun name {
        return "Alice";
    }
}
VEYRA
    '',
    'validation does not depend on declaration order',
);

like(
    check_error(<<'VEYRA'),
interface Named {
    fun name;
}

class Person {
}

class Employee extends Person implements Named {
}
VEYRA
    qr/Class 'Employee' implementing 'Named': missing fun 'name'/,
    'missing inherited implementation is rejected',
);

like(
    check_error(<<'VEYRA'),
interface Named {
    fun name;
}

class Person {
    act name {
    }
}

class Employee extends Person implements Named {
}
VEYRA
    qr/operation 'name' must be fun, found act/,
    'inherited operation must have the required kind',
);

like(
    check_error(<<'VEYRA'),
interface Renamable {
    act rename ($value);
}

class Person {
    act rename {
    }
}

class Employee extends Person implements Renamable {
}
VEYRA
    qr/requires 1 parameter\(s\), found 0/,
    'inherited operation must have the required argument count',
);

like(
    check_error(<<'VEYRA'),
interface Named {
    fun name;
}

class Person implements Named {
    fun name {
        return "Alice";
    }
}

class Employee extends Person {
    act name {
    }
}
VEYRA
    qr/override 'name' must remain fun, found act/,
    'override cannot change an inherited interface operation kind',
);

like(
    check_error(<<'VEYRA'),
interface Renamable {
    act rename ($value);
}

class Person implements Renamable {
    act rename ($value) {
    }
}

class Employee extends Person {
    act rename {
    }
}
VEYRA
    qr/override 'rename' requires 1 parameter\(s\), found 0/,
    'override cannot change an inherited interface operation arity',
);

like(
    check_error(<<'VEYRA'),
interface Named {
    fun name;
}

class Person implements Named {
}

class Employee extends Person {
    fun name {
        return "Alice";
    }
}
VEYRA
    qr/Class 'Person' implementing 'Named': missing fun 'name'/,
    'a child implementation does not repair an invalid concrete parent',
);

done_testing;
