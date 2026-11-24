use strict;
use warnings;

use Test::More;

use Class::Veyra::OperationParser;

my $without_signature =
    Class::Veyra::OperationParser->parse(
        'fun name { return $name; }'
    );

is(
    $without_signature->{has_signature},
    0,
    'records an omitted signature',
);

is_deeply(
    $without_signature->{parameters},
    [],
    'omitted signature has no declared parameters',
);

my $empty_signature =
    Class::Veyra::OperationParser->parse(
        'fun name () { return $name; }'
    );

is(
    $empty_signature->{has_signature},
    1,
    'records an explicit signature',
);

is_deeply(
    $empty_signature->{parameters},
    [],
    'accepts an empty signature',
);

my $addition =
    Class::Veyra::OperationParser->parse(
        'fun add ($left, $right) { return $left + $right; }'
    );

is_deeply(
    [map { $_->{name} } @{ $addition->{parameters} }],
    [qw(left right)],
    'preserves parameter order',
);

is_deeply(
    [map { $_->{sigil} } @{ $addition->{parameters} }],
    ['$', '$'],
    'records scalar parameter sigils',
);

is(
    $addition->{body},
    ' return $left + $right; ',
    'preserves the body after parsing a signature',
);

my $commented_source = <<'VEYRA';
act rename (
    $new_name, # Required name.
    $reason
) {
    $name = $new_name;
}
VEYRA

my $commented =
    Class::Veyra::OperationParser->parse($commented_source);

is_deeply(
    [map { $_->{name} } @{ $commented->{parameters} }],
    [qw(new_name reason)],
    'allows multiline signatures and comments',
);

sub signature_error {
    my ($source) = @_;

    my $completed = eval {
        Class::Veyra::OperationParser->parse($source);
        1;
    };

    my $error = $@;

    return $completed ? '' : $error;
}

like(
    signature_error('fun add ($value, $value) {}'),
    qr/Duplicate parameter '\$value'/,
    'rejects duplicate parameter names',
);

like(
    signature_error('act rename ($self) {}'),
    qr/Reserved parameter '\$self'/,
    'reserves self for the object',
);

like(
    signature_error('fun add (left) {}'),
    qr/Expected '\$'/,
    'requires scalar parameter sigils',
);

like(
    signature_error('fun add (@values) {}'),
    qr/Expected '\$'/,
    'rejects array parameters',
);

like(
    signature_error('fun add ($left $right) {}'),
    qr/Expected ','/,
    'requires commas between parameters',
);

like(
    signature_error('fun add ($left,) {}'),
    qr/Expected '\$'/,
    'rejects trailing commas',
);

like(
    signature_error('fun add ($left = 1) {}'),
    qr/Expected ','/,
    'rejects parameter defaults',
);

like(
    signature_error('fun add ($left'),
    qr/Expected ','.*end of operation declaration/,
    'rejects an unfinished signature',
);

done_testing;
