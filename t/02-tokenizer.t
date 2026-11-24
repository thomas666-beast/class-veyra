use strict;
use warnings;

use Test::More;

use Class::Veyra::Tokenizer;

my $source = <<'VEYRA';
class Person {
    # fun inside a comment must remain unchanged.
    fun name {
        return "Alice";
    }
}
VEYRA

my $tokens = Class::Veyra::Tokenizer->tokenize($source);

is(
    join('', map { $_->{text} } @$tokens),
    $source,
    'tokenization preserves the complete source',
);

my @identifiers = map {
    $_->{text}
} grep {
    $_->{type} eq 'identifier'
} @$tokens;

is_deeply(
    \@identifiers,
    [qw(class Person fun name return)],
    'recognizes identifiers outside strings and comments',
);

my @comments = grep {
    $_->{type} eq 'comment'
} @$tokens;

is(
    scalar @comments,
    1,
    'recognizes a line comment',
);

my @strings = map {
    $_->{text}
} grep {
    $_->{type} eq 'string'
} @$tokens;

is_deeply(
    \@strings,
    ['"Alice"'],
    'recognizes a quoted string',
);

my $quoted_source = <<'VEYRA';
'fun fake { }'
"act fake { }"
'Alice\'s name'
"A \"quoted\" name"
VEYRA

my $quoted_tokens =
    Class::Veyra::Tokenizer->tokenize($quoted_source);

my @quoted_strings = grep {
    $_->{type} eq 'string'
} @$quoted_tokens;

is(
    scalar @quoted_strings,
    4,
    'handles both quote styles and escaped quotes',
);

is(
    join('', map { $_->{text} } @$quoted_tokens),
    $quoted_source,
    'preserves quoted content exactly',
);

my $offsets_match = 1;

for my $token (@$tokens) {
    my $original = substr(
        $source,
        $token->{offset},
        length($token->{text}),
    );

    if ($original ne $token->{text}) {
        $offsets_match = 0;
        last;
    }
}

ok(
    $offsets_match,
    'token offsets point to the original text',
);

is_deeply(
    Class::Veyra::Tokenizer->tokenize(''),
    [],
    'accepts empty source',
);

my $completed = eval {
    Class::Veyra::Tokenizer->tokenize(
        'fun name { return "unfinished'
    );

    1;
};

my $error = $@;

ok(
    !$completed,
    'rejects an unterminated string',
);

like(
    $error,
    qr/Unterminated string at offset \d+/,
    'unterminated string error includes its location',
);

done_testing;
