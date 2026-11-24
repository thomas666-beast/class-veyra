use strict;
use warnings;

use Test::More;

use Class::Veyra::Parser;

my $source = <<'VEYRA';
# A class declaration.
class Person {
    field $name :param;

    fun name {
        return $name;
    }
}

class Employee {
}
VEYRA

my $document = Class::Veyra::Parser->parse($source);

is(
    $document->{kind},
    'document',
    'parser returns a document',
);

is_deeply(
    [map { $_->{name} } @{ $document->{classes} }],
    [qw(Person Employee)],
    'parses multiple class declarations in order',
);

is(
    $document->{classes}[0]{kind},
    'class',
    'class node has the expected kind',
);

my $expected_body = <<'BODY';

    field $name :param;

    fun name {
        return $name;
    }
BODY

is(
    $document->{classes}[0]{body},
    $expected_body,
    'preserves class body including nested braces',
);

my $quoted_source = <<'VEYRA';
class Messages {
    fun text {
        # These braces must not affect nesting: } {
        return "}";
    }
}
VEYRA

my $quoted_document =
    Class::Veyra::Parser->parse($quoted_source);

is(
    $quoted_document->{classes}[0]{name},
    'Messages',
    'braces inside strings and comments do not close the class',
);

is_deeply(
    Class::Veyra::Parser->parse('')->{classes},
    [],
    'accepts an empty document',
);

sub parse_error {
    my ($source) = @_;

    my $completed = eval {
        Class::Veyra::Parser->parse($source);
        1;
    };

    my $error = $@;

    return $completed ? '' : $error;
}

like(
    parse_error('class Person {'),
    qr/Unclosed body for class 'Person'/,
    'rejects an unclosed class body',
);

like(
    parse_error('class Person {} class Person {}'),
    qr/Duplicate class 'Person'/,
    'rejects duplicate class declarations',
);

like(
    parse_error('class {}'),
    qr/Expected identifier/,
    'requires a class name',
);

like(
    parse_error('class Person;'),
    qr/Expected '\{'/,
    'requires a class body',
);

like(
    parse_error('package Person;'),
    qr/Expected 'class' or 'interface'/,
    'rejects unsupported top-level statements',
);

like(
    parse_error('class Person {} unexpected'),
    qr/Expected 'class' or 'interface'/,
    'rejects unexpected content after a class',
);

done_testing;
