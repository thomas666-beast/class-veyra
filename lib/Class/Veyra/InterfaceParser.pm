package Class::Veyra::InterfaceParser;

use v5.38;
use strict;
use warnings;

use Class::Veyra::Tokenizer;
use Class::Veyra::OperationParser;
use Class::Veyra::QualifiedName;

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

        die "Expected $expected, found end of interface declaration\n"
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

    my $keyword = $expect->('identifier', 'interface');

    my $qualified = Class::Veyra::QualifiedName->read(
        \@tokens,
        $index,
    );

    $index = $qualified->{next_index};

    my $name = {
        text   => $qualified->{name},
        offset => $qualified->{offset},
    };

    $expect->('symbol', '{');

    my @requirements;
    my %seen;
    my $closed = 0;

    while ($index < @tokens) {
        my $token = $tokens[$index];

        if (
            $token->{type} eq 'symbol'
            && $token->{text} eq '}'
        ) {
            ++$index;
            $closed = 1;
            last;
        }

        unless (
            $token->{type} eq 'identifier'
            && (
                $token->{text} eq 'fun'
                || $token->{text} eq 'act'
            )
        ) {
            die "Expected 'fun' or 'act' in interface "
                . "'$name->{text}' at offset $token->{offset}\n";
        }

        my $start = $token->{offset};
        my $semicolon;

        while ($index < @tokens) {
            my $current = $tokens[$index];

            if ($current->{type} eq 'symbol') {
                if ($current->{text} eq ';') {
                    $semicolon = $current;
                    ++$index;
                    last;
                }

                if (
                    $current->{text} eq '{'
                    || $current->{text} eq '}'
                ) {
                    die "Expected ';' before "
                        . "'$current->{text}' in interface "
                        . "'$name->{text}' at offset "
                        . "$current->{offset}; bodies are not allowed\n";
                }
            }

            ++$index;
        }

        die "Unterminated requirement in interface '$name->{text}'\n"
            unless $semicolon;

        my $header = substr(
            $source,
            $start,
            $semicolon->{offset} - $start,
        );

        my $operation =
            Class::Veyra::OperationParser->parse(
                $header . "\n{}"
            );

        die "Duplicate requirement '$operation->{name}' "
            . "in interface '$name->{text}'\n"
            if $seen{ $operation->{name} }++;

        delete $operation->{body};

        $operation->{offset} = $start;

        for my $parameter (@{ $operation->{parameters} }) {
            $parameter->{offset} += $start;
        }

        push @requirements, $operation;
    }

    die "Unclosed interface '$name->{text}'\n"
        unless $closed;

    if ($index < @tokens) {
        my $extra = $tokens[$index];

        die "Unexpected content after interface declaration "
            . "at offset $extra->{offset}\n";
    }

    return {
        kind         => 'interface',
        name         => $name->{text},
        requirements => \@requirements,
        offset       => $keyword->{offset},
    };
}

1;
