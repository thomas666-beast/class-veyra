package Class::Veyra::Tokenizer;

use v5.38;
use strict;
use warnings;

sub tokenize {
    my ($class, $source) = @_;

    die "Tokenizer requires a defined source string\n"
        unless defined $source;

    die "Tokenizer source must not be a reference\n"
        if ref $source;

    my @tokens;

    pos($source) = 0;

    while (pos($source) < length($source)) {
        my $offset = pos($source);

        if ($source =~ /\G(\s+)/gc) {
            push @tokens, {
                type   => 'whitespace',
                text   => $1,
                offset => $offset,
            };

            next;
        }

        if ($source =~ /\G(\#[^\r\n]*)/gc) {
            push @tokens, {
                type   => 'comment',
                text   => $1,
                offset => $offset,
            };

            next;
        }

        my $character = substr($source, $offset, 1);

        if ($character eq q{'} || $character eq q{"}) {
            my $end = _string_end(
                $source,
                $offset,
                $character,
            );

            push @tokens, {
                type   => 'string',
                text   => substr($source, $offset, $end - $offset),
                offset => $offset,
            };

            pos($source) = $end;

            next;
        }

        if ($source =~ /\G([A-Za-z_][A-Za-z0-9_]*)/gc) {
            push @tokens, {
                type   => 'identifier',
                text   => $1,
                offset => $offset,
            };

            next;
        }

        $source =~ /\G(.)/gcs
            or die "Tokenizer stopped at offset $offset\n";

        push @tokens, {
            type   => 'symbol',
            text   => $1,
            offset => $offset,
        };
    }

    return \@tokens;
}

sub _string_end {
    my ($source, $start, $quote) = @_;

    my $cursor = $start + 1;
    my $length = length($source);

    while ($cursor < $length) {
        my $character = substr($source, $cursor, 1);

        if ($character eq '\\') {
            $cursor += 2;
            next;
        }

        if ($character eq $quote) {
            return $cursor + 1;
        }

        ++$cursor;
    }

    die "Unterminated string at offset $start\n";
}

1;
