package Class::Veyra::MethodCheck;

use v5.38;
use strict;
use warnings;

use Class::Veyra::Tokenizer;
use Class::Veyra::ReferenceCheck;
use Class::Veyra::LoopFacts;
use Class::Veyra::ArgumentCheck;

my %UNIVERSAL_METHOD = map { $_ => 1 } qw(
    new isa can DOES VERSION
);

my $QUALIFIED = qr/[A-Za-z_]\w*(?:::[A-Za-z_]\w*)+/;

sub validate {
    my ($class, $document) = @_;

    my %classes = map { $_->{name} => $_ }
        @{ $document->{classes} };

    for my $class_node (@{ $document->{classes} }) {
        for my $member (@{ $class_node->{members} }) {
            next unless $member->{kind} eq 'fun'
                || $member->{kind} eq 'act';

            my $completed = eval {
                $class->check_body(
                    $member->{body},
                    \%classes,
                    $class_node->{name},
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
    my ($class, $source, $classes, $owner) = @_;

    my $loop_writes =
        Class::Veyra::LoopFacts->written_variables($source);

    my $tokens = Class::Veyra::Tokenizer->tokenize($source);

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
    } @$tokens;

    my %variables;

    if (defined $owner) {
        $variables{self} = {
            class => $owner,
            depth => 0,
        };
    }

    my @scopes = (
        { shadowed => {} },
    );

    while (
        $text =~ /
            \bmy\s+\$(?<alias_decl>\w+)\s*=(?![=~])\s*
                \$(?<alias_decl_source>\w+)\s*(?=;)
          |
            \bmy\s+\$(?<v1>\w+)\s*=(?![=~])\s*
                (?<c1>$QUALIFIED)\s*->\s*new\b
          |
            \bmy\s+\$(?<v2>\w+)
          |
            \$(?<alias_assign>\w+)\s*=(?![=~])\s*
                \$(?<alias_assign_source>\w+)\s*(?=;)
          |
            \$(?<v3>\w+)\s*=(?![=~])\s*
                (?<c3>$QUALIFIED)\s*->\s*new\b
          |
            \$(?<v4>\w+)\s*
                (?:[-+*\/.x|&^%]|\|\||&&|\/\/|\*\*)?=(?![=~])
          |
            \$(?<v5>\w+)\s*->\s*(?<m5>\w+)
          |
            (?<![\w:\$\@%&>])(?<c6>$QUALIFIED)\s*->\s*(?<m6>\w+)
          |
            (?<ob>\{)
          |
            (?<cb>\})
        /gx
    ) {
        my %found = %+;
        my $start = $-[0];
        my $after_match = $+[0];
        my $depth = $#scopes;

        if (defined $found{ob}) {
            push @scopes, {
                shadowed => {},
            };
        }
        elsif (defined $found{cb}) {
            _leave_scope(\%variables, \@scopes);
        }
        elsif (defined $found{alias_decl}) {
            my $type = _copied_type(
                \%variables,
                $loop_writes,
                $found{alias_decl_source},
            );

            _declare(
                \%variables,
                \@scopes,
                $found{alias_decl},
                $type,
            );
        }
        elsif (defined $found{v1}) {
            my $type = _constructor_type(
                $text,
                $after_match,
                $found{c1},
            );

            _declare(
                \%variables,
                \@scopes,
                $found{v1},
                $type,
            );
        }
        elsif (defined $found{v2}) {
            _declare(
                \%variables,
                \@scopes,
                $found{v2},
                undef,
            );
        }
        elsif (defined $found{alias_assign}) {
            my $type = _copied_type(
                \%variables,
                $loop_writes,
                $found{alias_assign_source},
            );

            _assign(
                \%variables,
                $found{alias_assign},
                $type,
                $depth,
            );
        }
        elsif (defined $found{v3}) {
            my $type = _constructor_type(
                $text,
                $after_match,
                $found{c3},
            );

            _assign(
                \%variables,
                $found{v3},
                $type,
                $depth,
            );
        }
        elsif (defined $found{v4}) {
            _assign(
                \%variables,
                $found{v4},
                undef,
                $depth,
            );
        }
        elsif (defined $found{v5}) {
            next if $loop_writes->{ $found{v5} };

            my $entry = $variables{ $found{v5} };

            next unless $entry
                && defined $entry->{class};

            _check_method(
                $classes,
                $entry->{class},
                $found{m5},
                _line($text, $start),
                $source,
                $after_match,
            );
        }
        elsif (defined $found{c6}) {
            next unless $classes->{ $found{c6} };

            _check_method(
                $classes,
                $found{c6},
                $found{m6},
                _line($text, $start),
                $source,
                $after_match,
            );
        }
    }

    return 1;
}

sub _copied_type {
    my ($variables, $loop_writes, $name) = @_;

    return if $loop_writes->{$name};

    my $entry = $variables->{$name};

    return unless $entry;

    return $entry->{class};
}

sub _constructor_type {
    my ($text, $after_new, $class_name) = @_;

    my $tail = substr($text, $after_new);

    my $all = Class::Veyra::Tokenizer->tokenize($tail);

    my @tokens = grep {
        $_->{type} ne 'whitespace'
            && $_->{type} ne 'comment'
    } @$all;

    return unless @tokens;

    return $class_name
        if $tokens[0]{text} eq ';';

    return unless $tokens[0]{text} eq '(';

    my %closing = (
        '(' => ')',
        '[' => ']',
        '{' => '}',
    );

    my @expected;

    for my $i (0 .. $#tokens) {
        my $token = $tokens[$i];

        next unless $token->{type} eq 'symbol';

        my $symbol = $token->{text};

        if (exists $closing{$symbol}) {
            push @expected, $closing{$symbol};
            next;
        }

        next unless $symbol eq ')'
            || $symbol eq ']'
            || $symbol eq '}';

        return unless @expected
            && $symbol eq $expected[-1];

        pop @expected;

        next if @expected;

        my $following = $tokens[$i + 1];

        return (
            $following
            && $following->{text} eq ';'
        ) ? $class_name : undef;
    }

    return;
}

sub _declare {
    my ($variables, $scopes, $name, $class) = @_;

    my $scope = $scopes->[-1];

    unless (exists $scope->{shadowed}{$name}) {
        $scope->{shadowed}{$name} = {
            existed => exists $variables->{$name},
            entry   => $variables->{$name},
        };
    }

    $variables->{$name} = {
        class => $class,
        depth => $#$scopes,
    };

    return;
}

sub _leave_scope {
    my ($variables, $scopes) = @_;

    return if @$scopes == 1;

    my $scope = pop @$scopes;

    for my $name (keys %{ $scope->{shadowed} }) {
        my $saved = $scope->{shadowed}{$name};

        if ($saved->{existed}) {
            $variables->{$name} = $saved->{entry};
        }
        else {
            delete $variables->{$name};
        }
    }

    return;
}

sub _assign {
    my ($variables, $name, $class, $depth) = @_;

    my $entry = $variables->{$name};

    return unless $entry;

    $entry->{class} =
        $entry->{depth} == $depth ? $class : undef;

    return;
}

sub _line {
    my ($text, $start) = @_;

    return 1 + (() = substr($text, 0, $start) =~ /\n/g);
}

sub _check_method {
    my (
        $classes,
        $class_name,
        $method,
        $line,
        $source,
        $after_method,
    ) = @_;

    return if $UNIVERSAL_METHOD{$method};

    my %methods;
    my $complete = 1;
    my %seen;
    my $current = $class_name;

    while (defined $current) {
        last if $seen{$current}++;

        my $node = $classes->{$current};

        unless ($node) {
            $complete = 0;
            last;
        }

        for my $member (@{ $node->{members} }) {
            next unless $member->{kind} eq 'fun'
                || $member->{kind} eq 'act';

            $methods{ $member->{name} } = $member
                unless exists $methods{ $member->{name} };
        }

        my $body = defined $node->{body}
            ? $node->{body}
            : '';

        while ($body =~ /\bfield\s+\$(\w+)([^;=]*)/g) {
            my ($field, $attributes) = ($1, $2);

            next unless $attributes =~
                /:reader\b(?:\s*\(\s*(\w+)\s*\))?/;

            my $reader = defined $1 ? $1 : $field;

            $methods{$reader} = {
                kind          => 'reader',
                name          => $reader,
                has_signature => 0,
                parameters    => [],
            } unless exists $methods{$reader};
        }

        $current = $node->{parent};
    }

    if (exists $methods{$method}) {
        if (defined $source && defined $after_method) {
            Class::Veyra::ArgumentCheck->validate(
                $methods{$method},
                $source,
                $after_method,
                "$class_name\::$method",
                $line,
            );
        }

        return;
    }

    return unless $complete;

    my $message =
        "Unknown method '$method' on '$class_name' "
        . "at body line $line.";

    my $suggestion =
        Class::Veyra::ReferenceCheck::_suggest(
            $method,
            [keys %methods],
        );

    $message .= " Did you mean '$suggestion'?"
        if defined $suggestion;

    die "$message\n";
}

1;
