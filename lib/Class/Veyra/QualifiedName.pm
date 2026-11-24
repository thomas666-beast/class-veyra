package Class::Veyra::QualifiedName;

use v5.38;
use strict;
use warnings;

sub read {
    my ($class, $tokens, $index) = @_;

    die "Qualified name reader requires a token array\n"
        unless ref $tokens eq 'ARRAY';

    $index = 0 unless defined $index;

    while ($index < @$tokens) {
        my $token = $tokens->[$index];

        last unless (
            $token->{type} eq 'whitespace'
            || $token->{type} eq 'comment'
        );

        ++$index;
    }

    my $first = $tokens->[$index];

    die "Expected identifier, found end of source\n"
        unless $first;

    die "Expected identifier at offset $first->{offset}, "
        . "found '$first->{text}'\n"
        unless $first->{type} eq 'identifier';

    my $name = $first->{text};
    my $end = $first->{offset} + length $first->{text};

    ++$index;

    while ($index < @$tokens) {
        my $colon = $tokens->[$index];

        last unless (
            $colon->{type} eq 'symbol'
            && $colon->{text} eq ':'
            && $colon->{offset} == $end
        );

        my $second = $tokens->[$index + 1];

        die "Expected '::' after '$name' "
            . "at offset $colon->{offset}\n"
            unless (
                $second
                && $second->{type} eq 'symbol'
                && $second->{text} eq ':'
                && $second->{offset} == $end + 1
            );

        my $segment = $tokens->[$index + 2];

        die "Expected a name segment after '${name}::' "
            . "at offset " . ($end + 2) . "\n"
            unless (
                $segment
                && $segment->{type} eq 'identifier'
                && $segment->{offset} == $end + 2
            );

        $name .= '::' . $segment->{text};

        $end = $segment->{offset} + length $segment->{text};

        $index += 3;
    }

    return {
        name       => $name,
        offset     => $first->{offset},
        next_index => $index,
    };
}

1;
