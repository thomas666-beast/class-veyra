package Class::Veyra::ArgumentCheck;

use v5.38;
use strict;
use warnings;

use Class::Veyra::Tokenizer;

sub validate {
    my (
        $class,
        $operation,
        $source,
        $after_method,
        $target,
        $line,
    ) = @_;

    return 1 unless $operation->{has_signature};

    my $arguments = _call_arguments(
        $source,
        $after_method,
    );

    return 1 unless defined $arguments;

    my $actual = _count($arguments);

    return 1 unless defined $actual;

    my $expected = scalar @{
        $operation->{parameters}
    };

    return 1 if $actual == $expected;

    my $word = $expected == 1
        ? 'argument'
        : 'arguments';

    die "Method '$target' expects $expected $word, "
        . "got $actual at body line $line.\n";
}

sub _call_arguments {
    my ($source, $after_method) = @_;

    my $tail = substr($source, $after_method);

    my $all = Class::Veyra::Tokenizer->tokenize($tail);

    my @tokens = grep {
        $_->{type} ne 'whitespace'
            && $_->{type} ne 'comment'
    } @$all;

    return unless @tokens
        && $tokens[0]{type} eq 'symbol'
        && $tokens[0]{text} eq '(';

    my %closing = (
        '(' => ')',
        '[' => ']',
        '{' => '}',
    );

    my @expected;
    my @arguments;

    for my $i (0 .. $#tokens) {
        my $token = $tokens[$i];

        if ($token->{type} eq 'symbol') {
            my $symbol = $token->{text};

            if (exists $closing{$symbol}) {
                push @expected, $closing{$symbol};
            }
            elsif (
                $symbol eq ')'
                || $symbol eq ']'
                || $symbol eq '}'
            ) {
                return unless @expected
                    && $symbol eq $expected[-1];

                pop @expected;

                return \@arguments
                    unless @expected;
            }
        }

        push @arguments, $token
            if $i > 0;
    }

    return;
}

sub _count {
    my ($tokens) = @_;

    return 0 unless @$tokens;

    my %closing = (
        '(' => ')',
        '[' => ']',
        '{' => '}',
    );

    my @expected;
    my @parts = ([]);

    for my $i (0 .. $#$tokens) {
        my $token = $tokens->[$i];

        if ($token->{type} eq 'symbol') {
            my $symbol = $token->{text};

            if (!@expected && $symbol eq ',') {
                push @parts, [];
                next;
            }

            # Leave fat-comma expressions to later analysis.
            return if !@expected
                && $symbol eq '='
                && $tokens->[$i + 1]
                && $tokens->[$i + 1]{text} eq '>';

            if (exists $closing{$symbol}) {
                push @expected, $closing{$symbol};
            }
            elsif (
                $symbol eq ')'
                || $symbol eq ']'
                || $symbol eq '}'
            ) {
                return unless @expected
                    && $symbol eq $expected[-1];

                pop @expected;
            }
        }

        push @{ $parts[-1] }, $token;
    }

    return if @expected;

    # A trailing comma does not introduce another argument.
    pop @parts
        if @parts > 1 && !@{ $parts[-1] };

    my $count = 0;

    for my $part (@parts) {
        return unless @$part;

        my $part_count = _expression_count($part);

        return unless defined $part_count;

        $count += $part_count;
    }

    return $count;
}

sub _expression_count {
    my ($tokens) = @_;

    if (@$tokens == 1) {
        my $token = $tokens->[0];

        return 1 if $token->{type} eq 'string';

        return 1 if $token->{type} eq 'identifier'
            && $token->{text} eq 'undef';
    }

    if (
        @$tokens == 2
        && $tokens->[0]{type} eq 'symbol'
        && $tokens->[0]{text} eq '$'
        && $tokens->[1]{type} eq 'identifier'
    ) {
        return 1;
    }

    my $text = join '', map {
        $_->{text}
    } @$tokens;

    return 1 if $text =~
        /\A[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?\z/;

    if (_wrapped($tokens, '(', ')')) {
        my @inside = @$tokens;

        shift @inside;
        pop @inside;

        return _count(\@inside);
    }

    return 1 if _wrapped($tokens, '[', ']');
    return 1 if _wrapped($tokens, '{', '}');

    return;
}

sub _wrapped {
    my ($tokens, $opening, $closing) = @_;

    return 0 unless @$tokens >= 2;

    return 0 unless $tokens->[0]{type} eq 'symbol'
        && $tokens->[0]{text} eq $opening;

    return 0 unless $tokens->[-1]{type} eq 'symbol'
        && $tokens->[-1]{text} eq $closing;

    my %closing_for = (
        '(' => ')',
        '[' => ']',
        '{' => '}',
    );

    my @expected;

    for my $i (0 .. $#$tokens) {
        my $token = $tokens->[$i];

        next unless $token->{type} eq 'symbol';

        my $symbol = $token->{text};

        if (exists $closing_for{$symbol}) {
            push @expected, $closing_for{$symbol};
        }
        elsif (
            $symbol eq ')'
            || $symbol eq ']'
            || $symbol eq '}'
        ) {
            return 0 unless @expected
                && $symbol eq $expected[-1];

            pop @expected;

            return 0 if !@expected
                && $i < $#$tokens;
        }
    }

    return @expected ? 0 : 1;
}

sub call_arguments {
    my ($class, $source, $after_method) = @_;

    return _call_arguments($source, $after_method);
}

sub count_values {
    my ($class, $tokens) = @_;

    return _count($tokens);
}

1;
