use strict;
use warnings;

use Test::More;

use Class::Veyra::Tokenizer;
use Class::Veyra::QualifiedName;

sub read_name {
    my ($source) = @_;

    my $tokens =
        Class::Veyra::Tokenizer->tokenize($source);

    return Class::Veyra::QualifiedName->read($tokens);
}

sub name_error {
    my ($source) = @_;

    my $completed = eval {
        read_name($source);
        1;
    };

    my $error = $@;

    return $completed ? '' : $error;
}

for my $name (
    'Person',
    'MyApp::Person',
    'MyApp::Interfaces::Named',
    '_Private::Item2',
) {
    is(
        read_name($name)->{name},
        $name,
        "reads $name",
    );
}

my $leading = read_name("  # source comment\nMyApp::Person");

is(
    $leading->{name},
    'MyApp::Person',
    'skips leading whitespace and comments',
);

is(
    $leading->{offset},
    length("  # source comment\n"),
    'preserves the original source offset',
);

my $tokens =
    Class::Veyra::Tokenizer->tokenize(
        'class MyApp::Person extends MyApp::Base {}'
    );

my $result =
    Class::Veyra::QualifiedName->read($tokens, 1);

is(
    $result->{name},
    'MyApp::Person',
    'reads a name from a supplied token index',
);

is(
    $tokens->[ $result->{next_index} ]{type},
    'whitespace',
    'leaves following whitespace unconsumed',
);

my $tail = join '',
    map { $_->{text} }
    @$tokens[ $result->{next_index} .. $#$tokens ];

is(
    $tail,
    ' extends MyApp::Base {}',
    'does not consume the rest of the declaration',
);

my $original = 'MyApp::Person';

my $original_tokens =
    Class::Veyra::Tokenizer->tokenize($original);

Class::Veyra::QualifiedName->read($original_tokens);

is(
    join('', map { $_->{text} } @$original_tokens),
    $original,
    'does not modify token text',
);

for my $invalid (
    '',
    '::Person',
    'MyApp:',
    'MyApp::',
    'MyApp:::Person',
    'MyApp::::Person',
    'MyApp::2Person',
    'MyApp:: Person',
    'MyApp: :Person',
) {
    isnt(
        name_error($invalid),
        '',
        "rejects malformed name '$invalid'",
    );
}

done_testing;
