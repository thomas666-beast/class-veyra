package Class::Veyra::LoopFacts;

use v5.38;
use strict;
use warnings;

use Class::Veyra::Tokenizer;

sub written_variables {
    my ($class, $source) = @_;

    my $all = Class::Veyra::Tokenizer->tokenize($source);

    my $text = join '', map {
        my $token = $_;
        my $piece = $token->{text};

        if (
            $token->{type} eq 'string'
            || $token->{type} eq 'comment'
        ) {
            $piece =~ s/[^\n]/ /g;
        }

        $piece;
    } @$all;

    my %written;

    while (
        $text =~ /
            (?<![\w:\$\@%>])
            \b(?:for|foreach|while|until)\b
        /gx
    ) {
        my $start = $-[0];
        my $after_keyword = $+[0];

        my $end = _loop_end(
            $text,
            $after_keyword,
        );

        # Unbraced or postfix loops need broader treatment.
        my $region = defined $end
            ? substr($text, $start, $end - $start)
            : $text;

        my $names = _writes($region);

        $written{$_} = 1
            for keys %$names;

        # A loop can use the implicit iteration variable.
        $written{'_'} = 1;
    }

    return \%written;
}

sub _loop_end {
    my ($text, $start) = @_;

    my $tail = substr($text, $start);

    my $all = Class::Veyra::Tokenizer->tokenize($tail);

    my @tokens = grep {
        $_->{type} ne 'whitespace'
            && $_->{type} ne 'comment'
    } @$all;

    my @expected;
    my $body_start;

    my %closing = (
        '(' => ')',
        '[' => ']',
        '{' => '}',
    );

    for my $i (0 .. $#tokens) {
        my $token = $tokens[$i];

        next unless $token->{type} eq 'symbol';

        my $symbol = $token->{text};

        return if !@expected && $symbol eq ';';

        if (!@expected && $symbol eq '{') {
            $body_start = $i;
            last;
        }

        if (exists $closing{$symbol}) {
            push @expected, $closing{$symbol};
        }
        elsif (
            $symbol eq ')'
            || $symbol eq ']'
            || $symbol eq '}'
        ) {
            return unless @expected
                && pop(@expected) eq $symbol;
        }
    }

    return unless defined $body_start;

    my $body_end = _block_end(
        \@tokens,
        $body_start,
    );

    return unless defined $body_end;

    my $last = $body_end;

    my $following = $tokens[$body_end + 1];

    if (
        $following
        && $following->{type} eq 'identifier'
        && $following->{text} eq 'continue'
    ) {
        my $opening = $tokens[$body_end + 2];

        return unless $opening
            && $opening->{type} eq 'symbol'
            && $opening->{text} eq '{';

        $last = _block_end(
            \@tokens,
            $body_end + 2,
        );

        return unless defined $last;
    }

    return $start + $tokens[$last]{offset} + 1;
}

sub _block_end {
    my ($tokens, $start) = @_;

    my $depth = 0;

    for my $i ($start .. $#$tokens) {
        my $token = $tokens->[$i];

        next unless $token->{type} eq 'symbol';

        if ($token->{text} eq '{') {
            ++$depth;
        }
        elsif ($token->{text} eq '}') {
            --$depth;

            return $i if $depth == 0;
        }
    }

    return;
}

sub _writes {
    my ($text) = @_;

    my %names;

    while (
        $text =~ /
            \$(\w+)\s*
            (?:
                =(?![=~>])
                |
                (?:\+|-|\*|\/|%|\.|x|\||&|\^|
                   \*\*|\/\/|\|\||&&)=
                |
                \+\+
                |
                --
            )
        /gx
    ) {
        $names{$1} = 1;
    }

    while ($text =~ /(?:\+\+|--)\s*\$(\w+)/g) {
        $names{$1} = 1;
    }

    while ($text =~ /\bmy\s+\$(\w+)/g) {
        $names{$1} = 1;
    }

    while (
        $text =~ /
            \b(?:for|foreach)\s+
            (?:my\s+)?
            \$(\w+)
        /gx
    ) {
        $names{$1} = 1;
    }

    return \%names;
}

1;
