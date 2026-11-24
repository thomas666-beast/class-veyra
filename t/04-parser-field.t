use strict;
use warnings;

use Test::More;

use Class::Veyra::FieldParser;

is_deeply(
    Class::Veyra::FieldParser->parse(
        'field $name;'
    ),
    {
        kind      => 'field',
        name      => 'name',
        sigil     => '$',
        parameter => 0,
        offset    => 0,
    },
    'parses a private scalar field',
);

is_deeply(
    Class::Veyra::FieldParser->parse(
        'field $name :param;'
    ),
    {
        kind      => 'field',
        name      => 'name',
        sigil     => '$',
        parameter => 1,
        offset    => 0,
    },
    'parses a constructor parameter field',
);

my $commented = <<'VEYRA';
# Constructor parameter.
field $employee_id
    :param; # An identifier.
VEYRA

my $field = Class::Veyra::FieldParser->parse($commented);

is(
    $field->{name},
    'employee_id',
    'allows whitespace and comments between tokens',
);

is(
    $field->{parameter},
    1,
    'retains the parameter attribute across lines',
);

sub field_error {
    my ($source) = @_;

    my $completed = eval {
        Class::Veyra::FieldParser->parse($source);
        1;
    };

    my $error = $@;

    return $completed ? '' : $error;
}

like(
    field_error('field name;'),
    qr/Expected '\$'/,
    'requires a scalar sigil',
);

like(
    field_error('field $;'),
    qr/Expected identifier/,
    'requires a field name',
);

like(
    field_error('field $name'),
    qr/Expected ';'/,
    'requires a terminating semicolon',
);

like(
    field_error('field $name :unknown;'),
    qr/Expected 'param'/,
    'rejects unsupported attributes',
);

like(
    field_error('field $name :param :param;'),
    qr/Expected ';'/,
    'rejects a repeated parameter attribute',
);

like(
    field_error('field $name = "Alice";'),
    qr/Expected ';'/,
    'rejects initializers until they are implemented',
);

like(
    field_error('field @names;'),
    qr/Expected '\$'/,
    'rejects unsupported field sigils',
);

like(
    field_error('field $name; field $age;'),
    qr/Unexpected content after field declaration/,
    'parses exactly one field declaration',
);

done_testing;
