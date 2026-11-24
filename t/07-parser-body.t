use strict;
use warnings;

use Test::More;

use Class::Veyra::BodyParser;

my $source = <<'VEYRA';
# Person members.
field $name :param;
field $age;

fun name { return $name; }
act rename ($new_name) {
    $name = $new_name;
}
VEYRA

my $members = Class::Veyra::BodyParser->parse($source);

is_deeply(
    [map { $_->{kind} } @$members],
    [qw(field field fun act)],
    'parses members in declaration order',
);

is_deeply(
    [map { $_->{name} } @$members],
    [qw(name age name rename)],
    'records member names',
);

is($members->[0]{parameter}, 1, 'first field is a parameter');
is($members->[1]{parameter}, 0, 'second field is private');

is_deeply(
    [map { $_->{name} } @{ $members->[3]{parameters} }],
    ['new_name'],
    'keeps operation signatures',
);

is(
    $members->[3]{body},
    "\n    \$name = \$new_name;\n",
    'keeps operation bodies',
);

is(
    $members->[2]{offset},
    index($source, 'fun name'),
    'offset points at the member keyword',
);

is_deeply(
    Class::Veyra::BodyParser->parse(''),
    [],
    'accepts an empty body',
);

is_deeply(
    Class::Veyra::BodyParser->parse("# only a comment\n"),
    [],
    'accepts a body containing only comments',
);

is(
    scalar @{
        Class::Veyra::BodyParser->parse(
            'field $name; fun name { return $name; }'
        )
    },
    2,
    'allows a field and an operation with the same name',
);

sub body_error {
    my ($source) = @_;

    my $completed = eval {
        Class::Veyra::BodyParser->parse($source);
        1;
    };

    my $error = $@;

    return $completed ? '' : $error;
}

like(
    body_error('field $a; field $a;'),
    qr/Duplicate field '\$a'/,
    'rejects duplicate fields',
);

like(
    body_error('fun x {} act x {}'),
    qr/Duplicate operation 'x'/,
    'rejects duplicate operations across fun and act',
);

like(
    body_error('field $self;'),
    qr/Reserved field '\$self'/,
    'reserves self',
);

like(
    body_error('method name {}'),
    qr/Unexpected 'method'/,
    'rejects unsupported keywords',
);

like(
    body_error('}'),
    qr/Unexpected '\}'/,
    'rejects stray symbols',
);

like(
    body_error('field $name'),
    qr/Expected ';'/,
    'rejects an unterminated field',
);

like(
    body_error('fun name {'),
    qr/Unclosed body for fun 'name'/,
    'rejects an unclosed operation',
);

like(
    body_error('fun add ($a, $a) {}'),
    qr/Duplicate parameter '\$a'/,
    'propagates signature errors',
);

is(
    scalar @{
        Class::Veyra::BodyParser->parse(
            'fun x { return "}"; } field $y;'
        )
    },
    2,
    'braces inside strings do not end an operation',
);

done_testing;
