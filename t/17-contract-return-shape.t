use strict;
use warnings;

use Test::More;

use Class::Veyra::Compiler;

sub analyze_error {
    my ($source) = @_;

    my $completed = eval {
        Class::Veyra::Compiler->analyze($source);
        1;
    };

    my $error = $@;

    return $completed ? '' : $error;
}

my @valid = (
    [
        'class A { fun value { return (1); } }',
        'parenthesized scalar',
    ],
    [
        'class A { fun value { return (((1))); } }',
        'nested parenthesized scalar',
    ],
    [
        'class A { fun value { return [1, 2]; } }',
        'array reference',
    ],
    [
        'class A { fun value { return ({ a => 1, b => 2 }); } }',
        'parenthesized hash reference',
    ],
    [
        'class A { fun value { return ([1, 2]); } }',
        'parenthesized array reference',
    ],
    [
        'class A { fun value { return ("a,b"); } }',
        'comma inside a string',
    ],
    [
        'class A { fun value { return (1) if $ready; return 0; } }',
        'conditional parenthesized scalar followed by final return',
    ],
    [
        'class A { act stop { return (); } }',
        'explicit empty-list return from act',
    ],
);

for my $case (@valid) {
    is(
        analyze_error($case->[0]),
        '',
        "accepts $case->[1]",
    );
}

my @lists = (
    'return 1, 2;',
    'return (1, 2);',
    'return ((1, 2));',
    'return (((1, 2)));',
    'return (1), (2);',
);

for my $statement (@lists) {
    like(
        analyze_error(
            "class A { fun value { $statement } }"
        ),
        qr/must return exactly one value/,
        "rejects explicit list: $statement",
    );
}

for my $statement ('return ();', 'return ((()));') {
    like(
        analyze_error(
            "class A { fun value { $statement } }"
        ),
        qr/must not use a bare return/,
        "rejects empty return expression: $statement",
    );
}

like(
    analyze_error(
        'class A { act stop { return (1); } }'
    ),
    qr/act 'stop' must not return a value/,
    'act cannot return a parenthesized value',
);

like(
    analyze_error(
        'class A { fun value { '
        . 'return (1, 2) if $ready; return 0; } }'
    ),
    qr/must return exactly one value/,
    'checks early conditional returns as well',
);

done_testing;
