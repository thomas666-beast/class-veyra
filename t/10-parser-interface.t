use strict;
use warnings;

use Test::More;

use Class::Veyra::InterfaceParser;

my $source = <<'VEYRA';
interface Named {
    fun name;
    act rename ($new_name);
}
VEYRA

my $interface =
    Class::Veyra::InterfaceParser->parse($source);

is(
    $interface->{kind},
    'interface',
    'returns an interface node',
);

is(
    $interface->{name},
    'Named',
    'records the interface name',
);

is_deeply(
    [map { $_->{kind} } @{ $interface->{requirements} }],
    [qw(fun act)],
    'preserves requirement kinds and order',
);

is_deeply(
    [map { $_->{name} } @{ $interface->{requirements} }],
    [qw(name rename)],
    'records requirement names',
);

is_deeply(
    [
        map { $_->{name} }
        @{ $interface->{requirements}[1]{parameters} }
    ],
    ['new_name'],
    'parses requirement parameters',
);

ok(
    !exists $interface->{requirements}[0]{body},
    'requirements have no implementation body',
);

is(
    $interface->{requirements}[1]{offset},
    index($source, 'act rename'),
    'requirement offset points into the interface source',
);

is(
    $interface->{requirements}[1]{parameters}[0]{offset},
    index($source, 'new_name'),
    'parameter offset points into the interface source',
);

is_deeply(
    Class::Veyra::InterfaceParser->parse(
        'interface Marker {}'
    )->{requirements},
    [],
    'accepts an empty marker interface',
);

my $commented_source = <<'VEYRA';
# Public contract.
interface Named {
    fun name (); # Explicit zero arguments.

    act rename (
        $new_name # Required name.
    );
}
VEYRA

my $commented =
    Class::Veyra::InterfaceParser->parse($commented_source);

is(
    $commented->{requirements}[0]{has_signature},
    1,
    'preserves an explicit empty signature',
);

is(
    scalar @{ $commented->{requirements}[1]{parameters} },
    1,
    'allows comments and multiline signatures',
);

sub interface_error {
    my ($source) = @_;

    my $completed = eval {
        Class::Veyra::InterfaceParser->parse($source);
        1;
    };

    my $error = $@;

    return $completed ? '' : $error;
}

like(
    interface_error('interface Named { fun name {} }'),
    qr/bodies are not allowed/,
    'rejects requirement bodies',
);

like(
    interface_error('interface Named { field $name; }'),
    qr/Expected 'fun' or 'act'/,
    'rejects fields',
);

like(
    interface_error('interface Named { fun name; act name; }'),
    qr/Duplicate requirement 'name'/,
    'rejects duplicate names across operation kinds',
);

like(
    interface_error('interface Named { fun name }'),
    qr/Expected ';'/,
    'requires a requirement terminator',
);

like(
    interface_error('interface Named {'),
    qr/Unclosed interface 'Named'/,
    'requires a closing interface brace',
);

like(
    interface_error('interface Named { act rename ($x, $x); }'),
    qr/Duplicate parameter '\$x'/,
    'rejects duplicate parameters',
);

like(
    interface_error('interface Named {} unexpected'),
    qr/Unexpected content after interface declaration/,
    'rejects trailing content',
);

done_testing;
