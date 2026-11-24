use strict;
use warnings;

use Test::More;

use Class::Veyra::Parser;
use Class::Veyra::Contract;

sub contract_error {
    my ($source) = @_;

    my $completed = eval {
        Class::Veyra::Contract->validate(
            Class::Veyra::Parser->parse($source)
        );
        1;
    };

    my $error = $@;

    return $completed ? '' : $error;
}

is(contract_error('class A { act go { $x = 1; } }'), '',
    'act without return is valid');

is(contract_error('class A { act x { return if $x; $y = 1; return; } }'), '',
    'act may use bare returns');

is(contract_error('class A { fun x { return $v; } }'), '',
    'fun may return a value');

is(contract_error('class A { fun x { return 0 if $a; return 1; } }'), '',
    'fun may return early and end with a return');

is(contract_error('class A { fun x { return { a => 1 }; } }'), '',
    'fun may return a hash reference');

is(contract_error('class A { fun x { return undef; } }'), '',
    'fun may return undef explicitly');

is(contract_error('class A { fun x { return 1 } }'), '',
    'final return may omit the semicolon');

is(contract_error('class A { act x { my $cb = sub { return 1; }; return; } }'), '',
    'return inside an anonymous sub belongs to that sub (act)');

is(contract_error('class A { fun x { my $cb = sub { return; }; return $cb; } }'), '',
    'return inside an anonymous sub belongs to that sub (fun)');

is(contract_error('class A { act x { my $return = 1; my %h = (return => 1); } }'), '',
    'variables and hash keys named return are ignored');

is(contract_error('class A { act x { say "return 5;"; } }'), '',
    'return inside a string is ignored');

like(
    contract_error('class A { act go { return 1; } }'),
    qr/act 'go' must not return a value/,
    'act cannot return a value',
);

like(
    contract_error('class A { act go { return 1 if $x; } }'),
    qr/act 'go' must not return a value/,
    'act cannot return a value conditionally',
);

like(
    contract_error('class A { fun x { return; } }'),
    qr/fun 'x' must not use a bare return/,
    'fun cannot use a bare return',
);

like(
    contract_error('class A { fun x { } }'),
    qr/must end with an unconditional 'return/,
    'empty fun is rejected',
);

like(
    contract_error('class A { fun x { return 1 if $y; } }'),
    qr/must end with an unconditional 'return/,
    'conditional return is not enough',
);

like(
    contract_error('class A { fun x { if ($y) { return 1; } } }'),
    qr/must end with an unconditional 'return/,
    'nested return is not enough',
);

like(
    contract_error('class A { fun x { return 1, 2; } }'),
    qr/must return exactly one value/,
    'fun cannot return a list',
);

like(
    contract_error('class A { act go { return 1; } }'),
    qr/\AClass 'A': act 'go'/,
    'errors name the class and operation',
);

is(
    Class::Veyra::Contract->validate(
        Class::Veyra::Parser->parse('class A { fun x { return 1; } }')
    ),
    1,
    'validate returns true for a valid document',
);

done_testing;
