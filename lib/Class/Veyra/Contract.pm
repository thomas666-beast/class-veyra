package Class::Veyra::Contract;

use v5.38;
use strict;
use warnings;

use Class::Veyra::Tokenizer;

my %MODIFIER = map { $_ => 1 } qw(if unless while until for foreach);

sub validate {
    my ($class, $document) = @_;

    for my $class_node (@{ $document->{classes} }) {
        for my $member (@{ $class_node->{members} }) {
            next unless $member->{kind} eq 'fun'
                || $member->{kind} eq 'act';

            my $ok = eval {
                $class->check_operation($member);
                1;
            };

            die "Class '$class_node->{name}': $@" unless $ok;
        }
    }

    return 1;
}

sub check_operation {
    my ($class, $operation) = @_;

    my ($returns, $count, $tokens) = _analyze($operation->{body});

    my $kind = $operation->{kind};
    my $name = $operation->{name};

    if ($kind eq 'act') {
        for my $return (@$returns) {
            die "act '$name' must not return a value "
                . "(return at body offset $return->{offset})\n"
                if $return->{has_value};
        }

        return 1;
    }

    for my $return (@$returns) {
        die "fun '$name' must not use a bare return "
            . "(return at body offset $return->{offset})\n"
            unless $return->{has_value};
    }

    for my $return (@$returns) {
        die "fun '$name' must return exactly one value "
            . "(return at body offset $return->{offset})\n"
            if $return->{comma};
    }

    my $terminal = 0;

    for my $return (@$returns) {
        next unless $return->{depth} == 0;
        next if $return->{conditional};

        my $end = $return->{terminator};

        if (
            $end == $count
            || (
                $end == $count - 1
                && $tokens->[$end]{text} eq ';'
            )
        ) {
            $terminal = 1;
            last;
        }
    }

    die "fun '$name' must end with an unconditional "
        . "'return <value>;'\n"
        unless $terminal;

    return 1;
}

sub _analyze {
    my ($source) = @_;

    my $all = Class::Veyra::Tokenizer->tokenize($source);

    my @tokens = grep {
        $_->{type} ne 'whitespace' && $_->{type} ne 'comment'
    } @$all;

    my @returns;
    my $depth = 0;
    my $i = 0;

    while ($i < @tokens) {
        my $token = $tokens[$i];

        if ($token->{type} eq 'symbol') {
            ++$depth if $token->{text} eq '{';
            --$depth if $token->{text} eq '}';

            ++$i;
            next;
        }

        if (
            $token->{type} eq 'identifier'
            && _is_keyword(\@tokens, $i)
        ) {
            if ($token->{text} eq 'sub') {
                $i = _skip_sub(\@tokens, $i);
                next;
            }

            if ($token->{text} eq 'return') {
                push @returns, _describe_return(\@tokens, $i, $depth);
            }
        }

        ++$i;
    }

    return (\@returns, scalar(@tokens), \@tokens);
}

sub _is_keyword {
    my ($tokens, $i) = @_;

    my $previous = $i > 0 ? $tokens->[$i - 1] : undef;
    my $next     = $tokens->[$i + 1];

    if ($previous && $previous->{type} eq 'symbol') {
        return 0 if $previous->{text} =~ /\A[\$\@%&:]\z/;

        if ($previous->{text} eq '>' && $i > 1) {
            return 0 if $tokens->[$i - 2]{text} eq '-';
        }
    }

    if ($next && $next->{type} eq 'symbol' && $next->{text} eq '=') {
        my $after = $tokens->[$i + 2];

        return 0 if $after && $after->{text} eq '>';
    }

    if (
        $previous
        && $previous->{text} eq '{'
        && $next
        && $next->{text} eq '}'
    ) {
        return 0;
    }

    return 1;
}

sub _skip_sub {
    my ($tokens, $i) = @_;

    my $j = $i + 1;

    ++$j if $j < @$tokens && $tokens->[$j]{type} eq 'identifier';

    if ($j < @$tokens && $tokens->[$j]{text} eq '(') {
        my $paren = 0;

        while ($j < @$tokens) {
            my $text = $tokens->[$j]{text};

            ++$paren if $text eq '(';
            --$paren if $text eq ')';

            ++$j;

            last if $paren == 0;
        }
    }

    return $i + 1
        unless $j < @$tokens && $tokens->[$j]{text} eq '{';

    my $depth = 0;

    while ($j < @$tokens) {
        my $token = $tokens->[$j++];

        next unless $token->{type} eq 'symbol';

        ++$depth if $token->{text} eq '{';
        --$depth if $token->{text} eq '}';

        return $j if $depth == 0;
    }

    return scalar @$tokens;
}

sub _describe_return {
    my ($tokens, $i, $depth) = @_;

    my $nesting = 0;
    my $conditional = 0;
    my $value_end;

    my $j = $i + 1;

    for (; $j < @$tokens; ++$j) {
        my $token = $tokens->[$j];

        if ($token->{type} eq 'symbol') {
            my $text = $token->{text};

            if ($text =~ /\A[(\[{]\z/) {
                ++$nesting;
            }
            elsif ($text =~ /\A[)\]}]\z/) {
                last if $nesting == 0;
                --$nesting;
            }
            elsif ($nesting == 0 && $text eq ';') {
                last;
            }
        }
        elsif (
            $nesting == 0
            && $token->{type} eq 'identifier'
            && $MODIFIER{ $token->{text} }
            && _is_keyword($tokens, $j)
        ) {
            $conditional = 1;

            $value_end = $j
                unless defined $value_end;
        }
    }

    $value_end = $j unless defined $value_end;

    my @expression;

    if ($value_end > $i + 1) {
        @expression = @$tokens[
            ($i + 1) .. ($value_end - 1)
        ];
    }

    my ($has_value, $comma) =
        _return_shape(\@expression);

    return {
        offset      => $tokens->[$i]{offset},
        depth       => $depth,
        has_value   => $has_value,
        conditional => $conditional,
        comma       => $comma,
        terminator  => $j,
    };
}

sub _return_shape {
    my ($expression) = @_;

    my @tokens = @$expression;

    while (
        @tokens >= 2
        && $tokens[0]{type} eq 'symbol'
        && $tokens[0]{text} eq '('
        && $tokens[-1]{type} eq 'symbol'
        && $tokens[-1]{text} eq ')'
    ) {
        my $depth = 0;
        my $wraps_all = 1;

        for my $index (0 .. $#tokens) {
            my $token = $tokens[$index];

            next unless $token->{type} eq 'symbol';

            ++$depth if $token->{text} eq '(';
            --$depth if $token->{text} eq ')';

            if ($depth == 0 && $index < $#tokens) {
                $wraps_all = 0;
                last;
            }
        }

        last unless $wraps_all && $depth == 0;

        shift @tokens;
        pop @tokens;
    }

    return (0, 0) unless @tokens;

    my $nesting = 0;
    my $comma = 0;

    for my $token (@tokens) {
        next unless $token->{type} eq 'symbol';

        my $text = $token->{text};

        if ($text =~ /\A[(\[{]\z/) {
            ++$nesting;
        }
        elsif ($text =~ /\A[)\]}]\z/) {
            --$nesting;
        }
        elsif ($text eq ',' && $nesting == 0) {
            $comma = 1;
        }
    }

    return (1, $comma);
}

1;
