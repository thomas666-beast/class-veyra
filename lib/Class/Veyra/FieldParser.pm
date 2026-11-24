package Class::Veyra::FieldParser;

use v5.38;
use strict;
use warnings;

use Class::Veyra::Tokenizer;

sub parse {
    my ($class, $source) = @_;

    my $all_tokens =
        Class::Veyra::Tokenizer->tokenize($source);

    my @tokens = grep {
        $_->{type} ne 'whitespace'
            && $_->{type} ne 'comment'
    } @$all_tokens;

    my $index = 0;

    my $expect = sub {
        my ($type, $text) = @_;

        my $token = $tokens[$index];

        my $expected = defined $text
            ? "'$text'"
            : $type;

        die "Expected $expected, found end of field declaration\n"
            unless $token;

        if (
            $token->{type} ne $type
            || (defined $text && $token->{text} ne $text)
        ) {
            die "Expected $expected at offset $token->{offset}, "
                . "found '$token->{text}'\n";
        }

        ++$index;

        return $token;
    };

    my $keyword = $expect->('identifier', 'field');

    $expect->('symbol', '$');

    my $name = $expect->('identifier');

    my $is_parameter = 0;

    if (
        $index < @tokens
        && $tokens[$index]{type} eq 'symbol'
        && $tokens[$index]{text} eq ':'
    ) {
        $expect->('symbol', ':');
        $expect->('identifier', 'param');

        $is_parameter = 1;
    }

    $expect->('symbol', ';');

    if ($index < @tokens) {
        my $token = $tokens[$index];

        die "Unexpected content after field declaration "
            . "at offset $token->{offset}\n";
    }

    return {
        kind      => 'field',
        name      => $name->{text},
        sigil     => '$',
        parameter => $is_parameter,
        offset    => $keyword->{offset},
    };
}

1;
