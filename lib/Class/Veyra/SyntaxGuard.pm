package Class::Veyra::SyntaxGuard;

use v5.38;
use strict;
use warnings;

use Class::Veyra::Tokenizer;

my %UNSUPPORTED_WORD = map {
    $_ => 1
} qw(
    q qq qw qx qr
    m s tr y
    sub eval format
    __DATA__ __END__
);

sub validate {
    my ($class, $document) = @_;

    for my $class_node (@{ $document->{classes} }) {
        for my $member (@{ $class_node->{members} }) {
            next unless $member->{kind} eq 'fun'
                || $member->{kind} eq 'act';

            my $completed = eval {
                $class->check_body($member->{body});
                1;
            };

            my $error = $@;

            die "Class '$class_node->{name}', "
                . "$member->{kind} '$member->{name}': $error"
                unless $completed;
        }
    }

    return 1;
}

sub check_body {
    my ($class, $source) = @_;

    my $all = Class::Veyra::Tokenizer->tokenize($source);

    my @tokens = grep {
        $_->{type} ne 'whitespace'
            && $_->{type} ne 'comment'
    } @$all;

    for my $i (0 .. $#tokens) {
        my $token = $tokens[$i];

        next if $token->{type} eq 'string';

        if (
            $token->{type} eq 'identifier'
            && $UNSUPPORTED_WORD{ $token->{text} }
            && !_is_variable_name(\@tokens, $i)
        ) {
            die "Unsupported word '$token->{text}' "
                . "at body offset $token->{offset}\n";
        }

        next unless $token->{type} eq 'symbol';

        my $text = $token->{text};

        if ($text eq '/' || $text eq '`') {
            die "Unsupported symbol '$text' "
                . "at body offset $token->{offset}\n";
        }

        if ($text eq '<' && $i < $#tokens) {
            my $next = $tokens[$i + 1];

            if (
                $next->{type} eq 'symbol'
                && $next->{text} eq '<'
                && $next->{offset} == $token->{offset} + 1
            ) {
                die "Unsupported '<<' "
                    . "at body offset $token->{offset}\n";
            }
        }

        if ($text eq '=') {
            my $prefix = substr(
                $source,
                0,
                $token->{offset},
            );

            if ($prefix eq '' || $prefix =~ /\n\z/) {
                my $next = $tokens[$i + 1];

                if (
                    $next
                    && $next->{type} eq 'identifier'
                    && $next->{offset} == $token->{offset} + 1
                ) {
                    die "Unsupported POD-style directive "
                        . "at body offset $token->{offset}\n";
                }
            }
        }
    }

    return 1;
}

sub _is_variable_name {
    my ($tokens, $index) = @_;

    return 0 if $index == 0;

    my $previous = $tokens->[$index - 1];

    return 0 unless $previous->{type} eq 'symbol';

    return $previous->{text} =~ /\A[\$\@%]\z/ ? 1 : 0;
}

1;
