package Class::Veyra::Formatter;

use v5.38;
use strict;
use warnings;

use Class::Veyra::Parser;
use Class::Veyra::SyntaxGuard;
use Class::Veyra::Tokenizer;

sub format {
    my ($class, $source, $source_name) = @_;

    $source_name = '<string>'
        unless defined $source_name;

    Class::Veyra::Parser->parse(
        $source,
        $source_name,
    );

    my $atoms = _atoms($source);
    my $output = '';

    for my $i (0 .. $#$atoms) {
        my $current = $atoms->[$i];

        if ($i > 0) {
            $output .= _gap(
                $source,
                $atoms,
                $i,
            );
        }

        $output .= $current->{text};
    }

    $output .= "\n"
        if length $output;

    Class::Veyra::Parser->parse(
        $output,
        $source_name,
    );

    die "Formatter changed source tokens\n"
        unless $class->token_fingerprint($source)
            eq $class->token_fingerprint($output);

    return $output;
}

sub token_fingerprint {
    my ($class, $source) = @_;

    my $tokens =
        Class::Veyra::Tokenizer->tokenize($source);

    return join '', map {
        my $type = $_->{type};
        my $text = $_->{text};

        length($type) . ':' . $type
            . length($text) . ':' . $text;
    } grep {
        $_->{type} ne 'whitespace'
    } @$tokens;
}

sub _atoms {
    my ($source) = @_;

    my $all = Class::Veyra::Tokenizer->tokenize($source);

    my @tokens = grep {
        $_->{type} ne 'whitespace'
    } @$all;

    my @atoms;

    my $phase = 'top';
    my $container;
    my $declaration;
    my $member;

    for (my $i = 0; $i < @tokens; ++$i) {
        my $token = $tokens[$i];

        my $atom = {
            type        => $token->{type},
            text        => $token->{text},
            offset      => $token->{offset},
            end         => $token->{offset}
                + length($token->{text}),
            indent      => defined $container ? 1 : 0,
            starts_line => 0,
            ends_line   => 0,
        };

        if ($token->{type} eq 'comment') {
            push @atoms, $atom;
            next;
        }

        if ($phase eq 'top') {
            $declaration = $token->{text};

            $atom->{starts_line} = 1;
            $phase = 'declaration_header';
        }
        elsif ($phase eq 'declaration_header') {
            if (
                $declaration eq 'import'
                && _symbol($token, ';')
            ) {
                $atom->{ends_line} = 1;
                $phase = 'top';
            }
            elsif (_symbol($token, '{')) {
                $container = $declaration;

                $atom->{ends_line} = 1;
                $phase = 'members';
            }
        }
        elsif ($phase eq 'members') {
            if (_symbol($token, '}')) {
                $atom->{indent} = 0;
                $atom->{starts_line} = 1;
                $atom->{ends_line} = 1;

                $container = undef;
                $phase = 'top';
            }
            else {
                $member = $token->{text};

                $atom->{starts_line} = 1;
                $phase = 'member_header';
            }
        }
        elsif ($phase eq 'member_header') {
            if (_symbol($token, ';')) {
                $atom->{ends_line} = 1;
                $phase = 'members';
            }
            elsif (
                $container eq 'class'
                && (
                    $member eq 'fun'
                    || $member eq 'act'
                )
                && _symbol($token, '{')
            ) {
                my $end_index = _body_end(
                    \@tokens,
                    $i,
                );

                my $closing = $tokens[$end_index];

                $atom->{type} = 'body';
                $atom->{end} = $closing->{offset}
                    + length($closing->{text});

                my $body = substr(
                    $source,
                    $atom->{offset},
                    $atom->{end} - $atom->{offset},
                );

                Class::Veyra::SyntaxGuard->check_body(
                    substr($body, 1, length($body) - 2),
                );

                $atom->{text} = _indent_body($body);
                $atom->{ends_line} = 1;

                $i = $end_index;
                $phase = 'members';
            }
        }

        push @atoms, $atom;
    }

    return \@atoms;
}

sub _body_end {
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

    die "Formatter encountered an unclosed operation body\n";
}

sub _indent_body {
    my ($source) = @_;

    my $tokens =
        Class::Veyra::Tokenizer->tokenize($source);

    my %closing_for = (
        '(' => ')',
        '[' => ']',
        '{' => '}',
    );

    my @expected;
    my @edits;
    my $line_start;

    for my $i (0 .. $#$tokens) {
        my $token = $tokens->[$i];

        if ($token->{type} ne 'whitespace') {
            if (defined $line_start) {
                my $prefix = substr(
                    $source,
                    $line_start,
                    $token->{offset} - $line_start,
                );

                if ($prefix =~ /\A[ \t]*\z/) {
                    my $dedent = _leading_closers(
                        $tokens,
                        $i,
                    );

                    my $level = 1 + @expected - $dedent;

                    $level = 1 if $level < 1;

                    my $indent = '    ' x $level;

                    if ($prefix ne $indent) {
                        push @edits, {
                            offset => $line_start,
                            length => length($prefix),
                            text   => $indent,
                        };
                    }
                }
            }

            if ($token->{type} eq 'symbol') {
                my $symbol = $token->{text};

                if (exists $closing_for{$symbol}) {
                    push @expected, $closing_for{$symbol};
                }
                elsif (
                    $symbol eq ')'
                    || $symbol eq ']'
                    || $symbol eq '}'
                ) {
                    die "Formatter encountered mismatched "
                        . "delimiter '$symbol'\n"
                        unless @expected
                            && $symbol eq $expected[-1];

                    pop @expected;
                }
            }
        }

        my $last_newline = rindex(
            $token->{text},
            "\n",
        );

        if ($last_newline >= 0) {
            $line_start = $token->{offset}
                + $last_newline + 1;
        }
    }

    die "Formatter encountered an unclosed delimiter\n"
        if @expected;

    my $output = $source;

    for my $edit (reverse @edits) {
        substr(
            $output,
            $edit->{offset},
            $edit->{length},
            $edit->{text},
        );
    }

    return $output;
}

sub _leading_closers {
    my ($tokens, $start) = @_;

    my $count = 0;

    for my $i ($start .. $#$tokens) {
        my $token = $tokens->[$i];

        if ($token->{type} eq 'whitespace') {
            last if $token->{text} =~ /[\r\n]/;
            next;
        }

        last unless $token->{type} eq 'symbol'
            && $token->{text} =~ /\A[)\]}]\z/;

        ++$count;
    }

    return $count;
}

sub _gap {
    my ($source, $atoms, $index) = @_;

    my $previous = $atoms->[$index - 1];
    my $current = $atoms->[$index];
    my $next = $atoms->[$index + 1];

    my $original = substr(
        $source,
        $previous->{end},
        $current->{offset} - $previous->{end},
    );

    if ($current->{type} eq 'comment') {
        return ' '
            unless $original =~ /[\r\n]/;

        return _line_break(
            $original,
            $current->{indent},
        );
    }

    if (
        $previous->{type} eq 'comment'
        || $previous->{ends_line}
        || $current->{starts_line}
    ) {
        return _line_break(
            $original,
            $current->{indent},
        );
    }

    return ' '
        if $current->{type} eq 'body';

    if (_symbol($current, ':')) {
        return ''
            if _symbol($previous, ':')
            || ($next && _symbol($next, ':'));

        return ' ';
    }

    return ''
        if _symbol($previous, ':');

    return ''
        if _symbol($current, ',')
        || _symbol($current, ')')
        || _symbol($current, ';');

    return ''
        if _symbol($previous, '(')
        || _symbol($previous, '$');

    return ' ';
}

sub _line_break {
    my ($original, $indent) = @_;

    my $newlines = () = $original =~ /\n/g;

    $newlines = 1 if $newlines < 1;
    $newlines = 2 if $newlines > 2;

    return ("\n" x $newlines)
        . ('    ' x $indent);
}

sub _symbol {
    my ($token, $text) = @_;

    return $token->{type} eq 'symbol'
        && $token->{text} eq $text;
}

1;
