use strict;
use warnings;

use Test::More;

use Class::Veyra::Parser;

sub parse_error {
    my ($source) = @_;

    my $completed = eval {
        Class::Veyra::Parser->parse($source);
        1;
    };

    my $error = $@;

    return $completed ? '' : $error;
}

my $source = <<'VEYRA';
# Entry source
import MyApp::Person;

class MyApp::Employee extends MyApp::Person {}

import MyApp::Contracts::Named;

interface MyApp::Local {
    fun name;
}
VEYRA

my $document = Class::Veyra::Parser->parse(
    $source,
    'src/MyApp/Employee.veyra',
);

is_deeply(
    [map { $_->{name} } @{ $document->{imports} }],
    [
        'MyApp::Person',
        'MyApp::Contracts::Named',
    ],
    'records imports in source order',
);

is(
    $document->{imports}[0]{kind},
    'import',
    'marks import nodes with their own kind',
);

is(
    $document->{imports}[0]{source_name},
    'src/MyApp/Employee.veyra',
    'records the import source name',
);

is(
    $document->{imports}[0]{offset},
    index($source, 'import MyApp::Person;'),
    'records the first import keyword offset',
);

is(
    $document->{imports}[1]{offset},
    index($source, 'import MyApp::Contracts::Named;'),
    'records an import after a class',
);

is_deeply(
    [map { $_->{kind} } @{ $document->{declarations} }],
    ['class', 'interface'],
    'keeps imports out of the declarations array',
);

is(
    $document->{classes}[0]{name},
    'MyApp::Employee',
    'preserves class parsing alongside imports',
);

is(
    $document->{interfaces}[0]{name},
    'MyApp::Local',
    'preserves interface parsing alongside imports',
);

my $empty = Class::Veyra::Parser->parse('');

is_deeply(
    $empty->{imports},
    [],
    'returns an empty imports array for an empty source',
);

my $plain = Class::Veyra::Parser->parse(
    'class Plain {}'
);

is_deeply(
    $plain->{imports},
    [],
    'returns an empty imports array when imports are absent',
);

my $simple = Class::Veyra::Parser->parse(
    'import Person;'
);

is(
    $simple->{imports}[0]{name},
    'Person',
    'accepts an unqualified import name',
);

is(
    $simple->{imports}[0]{source_name},
    '<string>',
    'uses the default source name for imports',
);

is_deeply(
    $simple->{declarations},
    [],
    'accepts an import-only document',
);

my $commented = Class::Veyra::Parser->parse(
    "import # requested declaration\n"
        . "MyApp::Person # terminator follows\n"
        . ";"
);

is(
    $commented->{imports}[0]{name},
    'MyApp::Person',
    'allows comments around a contiguous import name',
);

like(
    parse_error('import MyApp::Person'),
    qr/Expected ';'/,
    'requires an import terminator',
);

like(
    parse_error('import ;'),
    qr/Expected identifier/,
    'requires an import name',
);

isnt(
    parse_error('import MyApp::;'),
    '',
    'rejects an incomplete qualified import name',
);

isnt(
    parse_error('import MyApp :: Person;'),
    '',
    'rejects whitespace within a qualified import name',
);

like(
    parse_error(
        "import MyApp::Person;\n"
            . "import MyApp::Person;"
    ),
    qr/Duplicate import 'MyApp::Person'/,
    'rejects duplicate imports in one source',
);

like(
    parse_error(
        'import MyApp::Person, MyApp::Other;'
    ),
    qr/Expected ';'/,
    'requires a separate statement for each import',
);

my $string_body = Class::Veyra::Parser->parse(
    <<'VEYRA'
class Example {
    fun text {
        return "import MyApp::Person;";
    }
}
VEYRA
);

is_deeply(
    $string_body->{imports},
    [],
    'does not treat operation-body string content as an import',
);

done_testing;
