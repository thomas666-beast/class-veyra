use strict;
use warnings;

use Test::More;

use Class::Veyra::OperationParser;

is_deeply(
    Class::Veyra::OperationParser->parse(
        'fun name { return $name; }'
    ),
    {
        kind          => 'fun',
        name          => 'name',
        parameters    => [],
        has_signature => 0,
        body          => ' return $name; ',
        offset        => 0,
    },
    'parses a value-returning operation',
);

is_deeply(
    Class::Veyra::OperationParser->parse(
        'act reset { $value = 0; }'
    ),
    {
        kind          => 'act',
        name          => 'reset',
        parameters    => [],
        has_signature => 0,
        body          => ' $value = 0; ',
        offset        => 0,
    },
    'parses a void operation',
);

my $nested_source = <<'VEYRA';
fun snapshot {
    return {
        person => {
            name => $name,
        },
    };
}
VEYRA

my $nested =
    Class::Veyra::OperationParser->parse($nested_source);

my $expected_body = <<'BODY';

    return {
        person => {
            name => $name,
        },
    };
BODY

is(
    $nested->{body},
    $expected_body,
    'preserves nested braces and body formatting',
);

my $quoted_source = <<'VEYRA';
fun message {
    # A closing brace in a comment: }
    return "}";
}
VEYRA

my $quoted =
    Class::Veyra::OperationParser->parse($quoted_source);

is(
    $quoted->{name},
    'message',
    'ignores braces inside strings and comments',
);

is(
    Class::Veyra::OperationParser->parse(
        'act nothing {}'
    )->{body},
    '',
    'accepts an empty operation body structurally',
);

my $commented =
    Class::Veyra::OperationParser->parse(
        "# Before\nfun name { return 1; }\n# After\n"
    );

is(
    $commented->{kind},
    'fun',
    'allows comments around a declaration',
);

sub operation_error {
    my ($source) = @_;

    my $completed = eval {
        Class::Veyra::OperationParser->parse($source);
        1;
    };

    my $error = $@;

    return $completed ? '' : $error;
}

like(
    operation_error('method name {}'),
    qr/Expected 'fun' or 'act'/,
    'rejects unsupported operation keywords',
);

like(
    operation_error('fun {}'),
    qr/Expected identifier/,
    'requires an operation name',
);

like(
    operation_error('fun name;'),
    qr/Expected '\{'/,
    'requires an operation body',
);

like(
    operation_error('fun name {'),
    qr/Unclosed body for fun 'name'/,
    'rejects an unclosed operation body',
);

like(
    operation_error('fun name {} act reset {}'),
    qr/Unexpected content after operation declaration/,
    'parses exactly one operation declaration',
);

is_deeply(
    [
        map { $_->{name} }
        @{
            Class::Veyra::OperationParser->parse(
                'act rename ($new_name) {}'
            )->{parameters}
        }
    ],
    ['new_name'],
    'accepts a scalar argument signature',
);
done_testing;
