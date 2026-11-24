package Class::Veyra::SourceDiff;

use v5.38;
use strict;
use warnings;

sub unified {
    my ($class, $name, $original, $formatted) = @_;

    return '' if $original eq $formatted;

    my @old = length $original
        ? split /(?<=\n)/, $original
        : ();

    my @new = length $formatted
        ? split /(?<=\n)/, $formatted
        : ();

    my $prefix = 0;

    while (
        $prefix < @old
        && $prefix < @new
        && $old[$prefix] eq $new[$prefix]
    ) {
        ++$prefix;
    }

    my $suffix = 0;

    while (
        $suffix < @old - $prefix
        && $suffix < @new - $prefix
        && $old[$#old - $suffix] eq $new[$#new - $suffix]
    ) {
        ++$suffix;
    }

    my $context = 3;

    my $start = $prefix > $context
        ? $prefix - $context
        : 0;

    my $old_change_end = @old - $suffix;
    my $new_change_end = @new - $suffix;

    my $trailing = $suffix < $context
        ? $suffix
        : $context;

    my $old_end = $old_change_end + $trailing;
    my $new_end = $new_change_end + $trailing;

    my $old_count = $old_end - $start;
    my $new_count = $new_end - $start;

    my $old_start = $old_count ? $start + 1 : $start;
    my $new_start = $new_count ? $start + 1 : $start;

    my $label = $name;
    $label =~ s/[\r\n\t]/ /g;

    my $output =
        "--- a/$label\n"
        . "+++ b/$label\n"
        . "@@ -$old_start,$old_count "
        . "+$new_start,$new_count @@\n";

    for (my $i = $start; $i < $prefix; ++$i) {
        $output .= _line(' ', $old[$i]);
    }

    for (my $i = $prefix; $i < $old_change_end; ++$i) {
        $output .= _line('-', $old[$i]);
    }

    for (my $i = $prefix; $i < $new_change_end; ++$i) {
        $output .= _line('+', $new[$i]);
    }

    for (my $i = 0; $i < $trailing; ++$i) {
        $output .= _line(
            ' ',
            $old[$old_change_end + $i],
        );
    }

    return $output;
}

sub _line {
    my ($prefix, $text) = @_;

    return $prefix . $text
        if $text =~ /\n\z/;

    return $prefix . $text
        . "\n\\ No newline at end of file\n";
}

1;
