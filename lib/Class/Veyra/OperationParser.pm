package Class::Veyra::OperationParser;

use v5.38;
use strict;
use warnings;

use Class::Veyra::Tokenizer;

sub parse {
    my ($class, $source) = @_;

    my $tokens =
        Class::Veyra::Tokenizer->tokenize($source);

    my $index = 0;

    my $peek = sub {
        while ($index < @$tokens) {
            my $token = $tokens->[$index];

            if (
                $token->{type} eq 'whitespace'
                || $token->{type} eq 'comment'
            ) {
                ++$index;
                next;
            }

            return $token;
        }

        return;
    };

    my $expect = sub {
        my ($type, $text) = @_;

        my $token = $peek->();

        my $expected = defined $text
            ? "'$text'"
            : $type;

        die "Expected $expected, found end of operation declaration\n"
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

    my $keyword = $expect->('identifier');

    unless (
        $keyword->{text} eq 'fun'
        || $keyword->{text} eq 'act'
    ) {
        die "Expected 'fun' or 'act' "
            . "at offset $keyword->{offset}\n";
    }

    my $name = $expect->('identifier');

    my @parameters;
    my %seen_parameters;
    my $has_signature = 0;

    my $next = $peek->();

    if (
        $next
        && $next->{type} eq 'symbol'
        && $next->{text} eq '('
    ) {
        $has_signature = 1;

        $expect->('symbol', '(');

        my $first = $peek->();

        if (
            $first
            && $first->{type} eq 'symbol'
            && $first->{text} eq ')'
        ) {
            $expect->('symbol', ')');
        }
        else {
            while (1) {
                $expect->('symbol', '$');

                my $parameter = $expect->('identifier');
                my $parameter_name = $parameter->{text};

                die "Reserved parameter '\$self' "
                    . "at offset $parameter->{offset}\n"
                    if $parameter_name eq 'self';

                die "Duplicate parameter '\$$parameter_name' "
                    . "at offset $parameter->{offset}\n"
                    if $seen_parameters{$parameter_name}++;

                push @parameters, {
                    name   => $parameter_name,
                    sigil  => '$',
                    offset => $parameter->{offset},
                };

                my $separator = $peek->();

                if (
                    $separator
                    && $separator->{type} eq 'symbol'
                    && $separator->{text} eq ')'
                ) {
                    $expect->('symbol', ')');
                    last;
                }

                $expect->('symbol', ',');
            }
        }
    }

    $expect->('symbol', '{');

    my @body;
    my $depth = 1;
    my $closed = 0;

    while ($index < @$tokens) {
        my $token = $tokens->[$index++];

        if ($token->{type} eq 'symbol') {
            if ($token->{text} eq '{') {
                ++$depth;
            }
            elsif ($token->{text} eq '}') {
                --$depth;

                if ($depth == 0) {
                    $closed = 1;
                    last;
                }
            }
        }

        push @body, $token;
    }

    die "Unclosed body for $keyword->{text} '$name->{text}'\n"
        unless $closed;

    if (my $extra = $peek->()) {
        die "Unexpected content after operation declaration "
            . "at offset $extra->{offset}\n";
    }

    return {
        kind          => $keyword->{text},
        name          => $name->{text},
        parameters    => \@parameters,
        has_signature => $has_signature,
        body          => join('', map { $_->{text} } @body),
        offset        => $keyword->{offset},
    };
}

1;
