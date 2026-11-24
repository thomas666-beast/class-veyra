package Class::Veyra::ReferenceCheck;

use v5.38;
use strict;
use warnings;

use Class::Veyra::Tokenizer;

sub validate {
    my ($class, $document) = @_;

    my %classes = map { $_->{name} => 1 }
        @{ $document->{classes} };

    my %interfaces = map { $_->{name} => 1 }
        @{ $document->{interfaces} };

    for my $class_node (@{ $document->{classes} }) {
        for my $member (@{ $class_node->{members} }) {
            next unless $member->{kind} eq 'fun'
                || $member->{kind} eq 'act';

            my $completed = eval {
                $class->check_body(
                    $member->{body},
                    \%classes,
                    \%interfaces,
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
    my ($class, $source, $classes, $interfaces) = @_;

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

    while (
        $text =~ /
            (?<![\w:\$\@%&>])
            ([A-Za-z_]\w*(?:::[A-Za-z_]\w*)+)
            \s*->
        /gx
    ) {
        my $name = $1;
        my $start = $-[1];

        my $line = 1 + (
            () = substr($text, 0, $start) =~ /\n/g
        );

        if ($interfaces->{$name}) {
            die "Interface '$name' cannot be used as a class "
                . "at body line $line\n";
        }

        next if $classes->{$name};

        my $message = "Unknown class '$name' at body line $line.";

        my $suggestion = _suggest($name, [keys %$classes]);

        $message .= " Did you mean '$suggestion'?"
            if defined $suggestion;

        die "$message\n";
    }

    return 1;
}

sub _suggest {
    my ($name, $candidates) = @_;

    my ($best, $best_distance);

    for my $candidate (sort @$candidates) {
        my $distance = _distance($name, $candidate);

        next if $distance > 2;

        if (!defined $best_distance || $distance < $best_distance) {
            $best = $candidate;
            $best_distance = $distance;
        }
    }

    return $best;
}

sub _distance {
    my ($left, $right) = @_;

    my @previous = (0 .. length $right);

    for my $i (1 .. length $left) {
        my @current = ($i);

        for my $j (1 .. length $right) {
            my $cost = substr($left, $i - 1, 1)
                eq substr($right, $j - 1, 1) ? 0 : 1;

            my $best = $previous[$j] + 1;

            $best = $current[$j - 1] + 1
                if $current[$j - 1] + 1 < $best;

            $best = $previous[$j - 1] + $cost
                if $previous[$j - 1] + $cost < $best;

            push @current, $best;
        }

        @previous = @current;
    }

    return $previous[-1];
}

1;
