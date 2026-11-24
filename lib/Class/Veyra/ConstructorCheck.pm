package Class::Veyra::ConstructorCheck;

use v5.38;
use strict;
use warnings;

use Class::Veyra::Tokenizer;
use Class::Veyra::ArgumentCheck;
use Class::Veyra::ReferenceCheck;

sub validate {
    my ($class, $document) = @_;

    my %classes = map {
        $_->{name} => $_
    } @{ $document->{classes} };

    for my $class_node (@{ $document->{classes} }) {
        for my $member (@{ $class_node->{members} }) {
            next unless $member->{kind} eq 'fun'
                || $member->{kind} eq 'act';

            my $completed = eval {
                $class->check_body(
                    $member->{body},
                    \%classes,
                );

                1;
            };

            my $error = $@;

            next if $completed;

            my $where = defined $class_node->{source_name}
                ? " in '$class_node->{source_name}'"
                : '';

            die "Class '$class_node->{name}'$where, "
                . "$member->{kind} '$member->{name}': $error";
        }
    }

    return 1;
}

sub check_body {
    my ($class, $source, $classes) = @_;

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

    while (
        $text =~ /
            (?<![\w:\$\@%&>])
            (?<target>[A-Za-z_]\w*(?:::[A-Za-z_]\w*)*)
            \s*->\s*new\b
        /gx
    ) {
        my $target = $+{target};
        my $start = $-[0];
        my $after_new = $+[0];

        next unless $classes->{$target};

        my $arguments = _constructor_arguments(
            $source,
            $after_new,
        );

        next unless defined $arguments;

        my $provided = _named_parameters($arguments);

        next unless defined $provided;

        my $required = _parameters(
            $classes,
            $target,
        );

        next unless defined $required;

        my $line = 1 + (
            () = substr($source, 0, $start) =~ /\n/g
        );

        for my $name (sort keys %$provided) {
            next if exists $required->{$name};

            my $message =
                "Unknown constructor parameter '$name' "
                . "for '$target' at body line $line.";

            my $suggestion =
                Class::Veyra::ReferenceCheck::_suggest(
                    $name,
                    [keys %$required],
                );

            $message .= " Did you mean '$suggestion'?"
                if defined $suggestion;

            die "$message\n";
        }

        my @missing = grep {
            !exists $provided->{$_}
        } sort keys %$required;

        if (@missing) {
            die "Constructor '$target' is missing required "
                . "parameter(s): "
                . join(', ', @missing)
                . " at body line $line.\n";
        }
    }

    return 1;
}

sub _constructor_arguments {
    my ($source, $after_new) = @_;

    my $arguments =
        Class::Veyra::ArgumentCheck->call_arguments(
            $source,
            $after_new,
        );

    return $arguments if defined $arguments;

    my $tail = substr($source, $after_new);

    my $all = Class::Veyra::Tokenizer->tokenize($tail);

    my @tokens = grep {
        $_->{type} ne 'whitespace'
            && $_->{type} ne 'comment'
    } @$all;

    return [] unless @tokens;

    return [] if $tokens[0]{type} eq 'symbol'
        && $tokens[0]{text} eq ';';

    return;
}

sub _parameters {
    my ($classes, $target) = @_;

    my %parameters;
    my %seen;
    my $current = $target;

    while (defined $current) {
        return if $seen{$current}++;

        my $node = $classes->{$current};

        return unless $node;

        for my $member (@{ $node->{members} }) {
            next unless $member->{kind} eq 'field';
            next unless $member->{parameter};

            $parameters{ $member->{name} } = 1;
        }

        $current = $node->{parent};
    }

    return \%parameters;
}

sub _named_parameters {
    my ($tokens) = @_;

    return {} unless @$tokens;

    my $split = _split_arguments($tokens);

    return unless defined $split;

    my ($parts, $separators) = @$split;

    return if @$parts % 2;

    my %provided;

    for (my $i = 0; $i < @$parts; $i += 2) {
        my $name = _parameter_name(
            $parts->[$i],
            $separators->[$i],
        );

        return unless defined $name;

        my $value_count =
            Class::Veyra::ArgumentCheck->count_values(
                $parts->[$i + 1],
            );

        return unless defined $value_count
            && $value_count == 1;

        $provided{$name} = 1;
    }

    return \%provided;
}

sub _split_arguments {
    my ($tokens) = @_;

    my %closing = (
        '(' => ')',
        '[' => ']',
        '{' => '}',
    );

    my @expected;
    my @parts = ([]);
    my @separators;

    for (my $i = 0; $i < @$tokens; ++$i) {
        my $token = $tokens->[$i];

        if ($token->{type} eq 'symbol') {
            my $symbol = $token->{text};

            if (!@expected) {
                my $separator;

                if ($symbol eq ',') {
                    $separator = ',';
                }
                elsif (
                    $symbol eq '='
                    && $tokens->[$i + 1]
                    && $tokens->[$i + 1]{type} eq 'symbol'
                    && $tokens->[$i + 1]{text} eq '>'
                ) {
                    $separator = '=>';
                    ++$i;
                }

                if (defined $separator) {
                    push @separators, $separator;
                    push @parts, [];

                    next;
                }
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
                    && $symbol eq $expected[-1];

                pop @expected;
            }
        }

        push @{ $parts[-1] }, $token;
    }

    return if @expected;

    if (
        @parts > 1
        && !@{ $parts[-1] }
        && $separators[-1] eq ','
    ) {
        pop @parts;
        pop @separators;
    }

    return if grep { !@$_ } @parts;

    return [\@parts, \@separators];
}

sub _parameter_name {
    my ($tokens, $separator) = @_;

    return unless @$tokens == 1;

    my $token = $tokens->[0];

    if (
        $token->{type} eq 'identifier'
        && defined $separator
        && $separator eq '=>'
    ) {
        return $token->{text};
    }

    return unless $token->{type} eq 'string';

    my $text = $token->{text};

    return $1 if $text =~ /\A'([^'\\]*)'\z/s;

    return $1 if $text =~ /\A"([^"\\\$\@]*)"\z/s;

    return;
}

1;
