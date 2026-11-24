use strict;
use warnings;

use Test::More;

use Class::Veyra::Parser;
use Class::Veyra::Contract;

my $source = <<'VEYRA';
# Public contract.
interface Named {
    fun name;
    act rename ($new_name);
}

class Person {
    field $name :param;

    fun name {
        return $name;
    }

    act rename ($new_name) {
        $name = $new_name;
    }
}

interface Resettable {
    act reset;
}

class Counter {
    act reset {
    }
}
VEYRA

my $document = Class::Veyra::Parser->parse($source);

is(
    $document->{kind},
    'document',
    'returns a document node',
);

is_deeply(
    [map { $_->{name} } @{ $document->{classes} }],
    [qw(Person Counter)],
    'collects classes',
);

is_deeply(
    [map { $_->{name} } @{ $document->{interfaces} }],
    [qw(Named Resettable)],
    'collects interfaces',
);

is_deeply(
    [map { $_->{name} } @{ $document->{declarations} }],
    [qw(Named Person Resettable Counter)],
    'preserves declaration order',
);

is_deeply(
    [map { $_->{kind} } @{ $document->{declarations} }],
    [qw(interface class interface class)],
    'preserves declaration kinds',
);

is(
    $document->{interfaces}[0]{offset},
    index($source, 'interface Named'),
    'interface offset is relative to the full document',
);

is(
    $document->{interfaces}[0]{requirements}[1]{offset},
    index($source, 'act rename'),
    'requirement offset is relative to the full document',
);

is(
    $document->{interfaces}[0]
        {requirements}[1]{parameters}[0]{offset},
    index($source, 'new_name'),
    'parameter offset is relative to the full document',
);

is(
    Class::Veyra::Contract->validate($document),
    1,
    'existing contract validation accepts a mixed document',
);

my $empty = Class::Veyra::Parser->parse('');

is_deeply(
    [
        $empty->{classes},
        $empty->{interfaces},
        $empty->{declarations},
    ],
    [[], [], []],
    'empty document has empty declaration collections',
);

sub document_error {
    my ($source) = @_;

    my $completed = eval {
        Class::Veyra::Parser->parse($source);
        1;
    };

    my $error = $@;

    return $completed ? '' : $error;
}

like(
    document_error('interface Named {} interface Named {}'),
    qr/Duplicate interface 'Named'/,
    'rejects duplicate interface names',
);

like(
    document_error('interface Named {} class Named {}'),
    qr/Declaration name 'Named' is already used by a interface/,
    'rejects a class name already used by an interface',
);

like(
    document_error('class Named {} interface Named {}'),
    qr/Declaration name 'Named' is already used by a class/,
    'rejects an interface name already used by a class',
);

like(
    document_error('interface Named { field $name; }'),
    qr/Expected 'fun' or 'act'/,
    'validates interface contents during document parsing',
);

done_testing;
