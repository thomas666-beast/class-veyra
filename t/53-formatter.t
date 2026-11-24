use strict;
use warnings;

use Test::More;

use Class::Veyra::Formatter;
use Class::Veyra::Tokenizer;

sub error_from {
    my ($code) = @_;

    my $completed = eval {
        $code->();
        1;
    };

    return $completed ? '' : $@;
}

sub token_texts {
    my ($source, $type) = @_;

    my $tokens =
        Class::Veyra::Tokenizer->tokenize($source);

    return [
        map {
            $_->{text}
        } grep {
            $_->{type} eq $type
        } @$tokens
    ];
}

my $compact =
    'class   App::Main{'
    . 'field   $name:param;'
    . 'act message( $value ){print "literal";}'
    . '}';

my $compact_expected = <<'VEYRA';
class App::Main {
    field $name :param;
    act message ($value) {print "literal";}
}
VEYRA

is(
    Class::Veyra::Formatter->format($compact),
    $compact_expected,
    'formats declarations without expanding inline bodies',
);

my $reported_source = <<'VEYRA';
class App::Main {
    fun message {
        return "Hello, world!";
    }

act say_name ($name) {
say 'Hello ' . $name;
    }
}
VEYRA

my $reported_expected = <<'VEYRA';
class App::Main {
    fun message {
        return "Hello, world!";
    }

    act say_name ($name) {
        say 'Hello ' . $name;
    }
}
VEYRA

is(
    Class::Veyra::Formatter->format($reported_source),
    $reported_expected,
    'indents the reported operation header and body',
);

my $nested_source = <<'VEYRA';
class App::Main{
act message{
if (1) {
say "yes";
} else {
say "no";
}
my $items = [
1,
2,
];
my $data = {
items => $items,
};
}
}
VEYRA

my $nested_expected = <<'VEYRA';
class App::Main {
    act message {
        if (1) {
            say "yes";
        } else {
            say "no";
        }
        my $items = [
            1,
            2,
        ];
        my $data = {
            items => $items,
        };
    }
}
VEYRA

is(
    Class::Veyra::Formatter->format($nested_source),
    $nested_expected,
    'indents nested blocks, arrays, and hashes',
);

my $continuation_source = <<'VEYRA';
class App::Main {
act message {
some_function(
[
1,
2,
]);
}
}
VEYRA

my $continuation_expected = <<'VEYRA';
class App::Main {
    act message {
        some_function(
            [
                1,
                2,
        ]);
    }
}
VEYRA

is(
    Class::Veyra::Formatter->format($continuation_source),
    $continuation_expected,
    'dedents a line containing multiple closing delimiters',
);

my $string_source = <<'VEYRA';
class App::Main{
act message{
my $text = "first line
  preserve these spaces
last line";
say $text;
say "{ braces inside a string }";
}
}
VEYRA

my $formatted_strings =
    Class::Veyra::Formatter->format($string_source);

is_deeply(
    token_texts($formatted_strings, 'string'),
    token_texts($string_source, 'string'),
    'preserves all string contents including multiline indentation',
);

like(
    $formatted_strings,
    qr/^        say \$text;$/m,
    'resumes normal indentation after a multiline string',
);

my $comment_source = <<'VEYRA';
# Leading comment.
class App::Main{
act message{
# Body comment.
if (1) {
# Nested comment.
say "# not a comment"; # Trailing comment.
}
}
}
VEYRA

my $formatted_comments =
    Class::Veyra::Formatter->format($comment_source);

is_deeply(
    token_texts($formatted_comments, 'comment'),
    token_texts($comment_source, 'comment'),
    'preserves comment text and order',
);

like(
    $formatted_comments,
    qr/^        # Body comment\.$/m,
    'indents body comments',
);

like(
    $formatted_comments,
    qr/^            # Nested comment\.$/m,
    'indents nested comments',
);

my $crlf_source =
    "class App::Main {\r\n"
    . "act message {\r\n"
    . "say \"Hello\";\r\n"
    . "}\r\n"
    . "}\r\n";

my $formatted_crlf =
    Class::Veyra::Formatter->format($crlf_source);

like(
    $formatted_crlf,
    qr/\{\r\n        say "Hello";\r\n    \}/,
    'changes body indentation while preserving body CRLF line endings',
);

for my $case (
    {
        label  => 'compact declarations',
        source => $compact,
    },
    {
        label  => 'reported indentation',
        source => $reported_source,
    },
    {
        label  => 'nested delimiters',
        source => $nested_source,
    },
    {
        label  => 'continuation lines',
        source => $continuation_source,
    },
    {
        label  => 'multiline strings',
        source => $string_source,
    },
    {
        label  => 'comments',
        source => $comment_source,
    },
    {
        label  => 'CRLF bodies',
        source => $crlf_source,
    },
) {
    my $once = Class::Veyra::Formatter->format(
        $case->{source},
    );

    my $twice = Class::Veyra::Formatter->format(
        $once,
    );

    is(
        $twice,
        $once,
        "formatting is idempotent for $case->{label}",
    );

    is(
        Class::Veyra::Formatter->token_fingerprint($once),
        Class::Veyra::Formatter->token_fingerprint(
            $case->{source},
        ),
        "preserves non-whitespace tokens for $case->{label}",
    );
}

is(
    Class::Veyra::Formatter->format(
        'import App::User;class App::Main{}',
    ),
    <<'VEYRA',
import App::User;
class App::Main {
}
VEYRA
    'formats imports and empty classes',
);

is(
    Class::Veyra::Formatter->format(
        'interface App::Empty{}',
    ),
    <<'VEYRA',
interface App::Empty {
}
VEYRA
    'formats an empty interface',
);

is(
    Class::Veyra::Formatter->format(''),
    '',
    'accepts empty source',
);

is(
    Class::Veyra::Formatter->format(" \n\t"),
    '',
    'normalizes whitespace-only source',
);

is(
    Class::Veyra::Formatter->format(
        '   # Comment-only source.',
    ),
    "# Comment-only source.\n",
    'preserves comment-only source',
);

like(
    error_from(sub {
        Class::Veyra::Formatter->format(
            'class App::Main {',
        );
    }),
    qr/Unclosed body/,
    'rejects an unclosed class',
);

like(
    error_from(sub {
        Class::Veyra::Formatter->format(
            'class App::Main { act message { q{text}; } }',
        );
    }),
    qr/Unsupported word 'q'/,
    'refuses unsupported alternate quoting before reindenting a body',
);

done_testing;
