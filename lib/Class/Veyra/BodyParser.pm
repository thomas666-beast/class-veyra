package Class::Veyra::BodyParser;

use v5.38;
use strict;
use warnings;

use Class::Veyra::Tokenizer;
use Class::Veyra::FieldParser;
use Class::Veyra::OperationParser;
use Class::Veyra::QualifiedName;

sub parse {
    my ($class, $source) = @_;

    my $tokens = Class::Veyra::Tokenizer->tokenize($source);

    my @members;
    my %fields;
    my %operations;
    my %perl_modules;

    my $i = 0;

    while ($i < @$tokens) {
        my $token = $tokens->[$i];

        if (
            $token->{type} eq 'whitespace'
            || $token->{type} eq 'comment'
        ) {
            ++$i;
            next;
        }

        unless (
            $token->{type} eq 'identifier'
            && $token->{text} =~ /\A(?:use|field|fun|act)\z/
        ) {
            die "Unexpected '$token->{text}' at offset "
                . "$token->{offset}; expected use, field, fun, or act\n";
        }

        if ($token->{text} eq 'use') {
            my ($node, $next) = _parse_use($tokens, $i);

            die "Duplicate Perl module declaration '$node->{name}' "
                . "at offset $node->{offset}\n"
                if $perl_modules{ $node->{name} }++;

            push @members, $node;
            $i = $next;
            next;
        }

        my $end = $#$tokens;

        if ($token->{text} eq 'field') {
            for my $j ($i .. $#$tokens) {
                my $t = $tokens->[$j];

                if ($t->{type} eq 'symbol' && $t->{text} eq ';') {
                    $end = $j;
                    last;
                }
            }
        }
        else {
            my $paren = 0;
            my $depth = 0;

            for my $j ($i .. $#$tokens) {
                my $t = $tokens->[$j];

                next unless $t->{type} eq 'symbol';

                if ($depth == 0) {
                    if ($t->{text} eq '(') {
                        ++$paren;
                    }
                    elsif ($t->{text} eq ')') {
                        --$paren if $paren;
                    }
                    elsif ($paren == 0 && $t->{text} eq ';') {
                        $end = $j;
                        last;
                    }
                    elsif ($paren == 0 && $t->{text} eq '{') {
                        $depth = 1;
                    }
                }
                else {
                    if ($t->{text} eq '{') {
                        ++$depth;
                    }
                    elsif ($t->{text} eq '}') {
                        --$depth;

                        if ($depth == 0) {
                            $end = $j;
                            last;
                        }
                    }
                }
            }
        }

        my $text = join '', map { $_->{text} } @{$tokens}[$i .. $end];

        my $node;

        if ($token->{text} eq 'field') {
            $node = Class::Veyra::FieldParser->parse($text);

            die "Reserved field '\$self' at offset $token->{offset}\n"
                if $node->{name} eq 'self';

            die "Duplicate field '\$$node->{name}' "
                . "at offset $token->{offset}\n"
                if $fields{ $node->{name} }++;
        }
        else {
            $node = Class::Veyra::OperationParser->parse($text);

            die "Duplicate operation '$node->{name}' "
                . "at offset $token->{offset}\n"
                if $operations{ $node->{name} }++;
        }

        $node->{offset} = $token->{offset};

        push @members, $node;

        $i = $end + 1;
    }

    return \@members;
}

sub _parse_use {
    my ($tokens, $index) = @_;

    my $offset = $tokens->[$index]{offset};
    my $expected = "Expected 'use Module::Name ();' at offset $offset";
    my $module = eval {
        Class::Veyra::QualifiedName->read($tokens, $index + 1);
    };

    die "$expected: $@" unless defined $module;
    die "$expected\n" if $module->{name} =~ /\Av[0-9]+\z/;

    $index = $module->{next_index};

    for my $symbol ('(', ')', ';') {
        while (
            $index < @$tokens
            && $tokens->[$index]{type} =~ /\A(?:whitespace|comment)\z/
        ) {
            ++$index;
        }

        my $token = $tokens->[$index];
        die "$expected\n" unless $token
            && $token->{type} eq 'symbol'
            && $token->{text} eq $symbol;

        ++$index;
    }

    return ({
        kind   => 'use',
        name   => $module->{name},
        offset => $offset,
    }, $index);
}

1;
