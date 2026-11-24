use strict;
use warnings;

use Test::More;

my $program = <<'PERL';
use v5.38;
use strict;
use warnings;
use feature 'class';
no warnings 'experimental::class';

class VeyraNativeInheritanceParent {
    field $name :param;

    method name () {
        return scalar((sub {
            return $name;
        })->());
    }

    method description () {
        return scalar((sub {
            return "parent";
        })->());
    }

    method rename ($new_name) {
        (sub {
            $name = $new_name;
        })->();

        return;
    }
}

class VeyraNativeInheritanceChild
    :isa(VeyraNativeInheritanceParent)
{
    field $label :param;

    method label () {
        return scalar((sub {
            return $label;
        })->());
    }

    method description () {
        return scalar((sub {
            return "child";
        })->());
    }

    method rename_via_self ($new_name) {
        (sub {
            $self->rename($new_name);
        })->();

        return;
    }
}

my $object = VeyraNativeInheritanceChild->new(
    name  => 'Alice',
    label => 'example',
);

die "Child identity failed\n"
    unless $object->isa('VeyraNativeInheritanceChild');

die "Parent identity failed\n"
    unless $object->isa('VeyraNativeInheritanceParent');

die "Inherited constructor parameter or method failed\n"
    unless $object->name eq 'Alice';

die "Child constructor parameter or field failed\n"
    unless $object->label eq 'example';

die "Override dispatch failed\n"
    unless $object->description eq 'child';

my @renamed = $object->rename('Bob');

die "Inherited action failed\n"
    unless $object->name eq 'Bob';

die "Inherited action returned values\n"
    if @renamed;

my $result = $object->rename_via_self('Carol');

die "Inherited action dispatch through self failed\n"
    unless $object->name eq 'Carol';

die "Child action returned a defined value\n"
    if defined $result;

my $parent = VeyraNativeInheritanceParent->new(
    name => 'Parent instance',
);

die "Parent dispatch was changed by child override\n"
    unless $parent->description eq 'parent';

die "Parent instance state is incorrect\n"
    unless $parent->name eq 'Parent instance';

die "Child instance state changed unexpectedly\n"
    unless $object->name eq 'Carol';

print "VEYRA_NATIVE_INHERITANCE_OK\n";
PERL

my $pid = open my $child, '-|', $^X, '-e', $program;

unless (defined $pid) {
    BAIL_OUT("Cannot start inheritance probe: $!");
}

my $output = do {
    local $/;
    <$child>;
};

$output = '' unless defined $output;

my $closed = close $child;
my $status = $?;

my $signal = $status & 127;
my $exit_code = $status >> 8;

is(
    $signal,
    0,
    'native inheritance subprocess does not terminate by signal',
);

is(
    $exit_code,
    0,
    'native inheritance subprocess exits successfully',
);

ok(
    $closed,
    'native inheritance subprocess completes successfully',
);

is(
    $output,
    "VEYRA_NATIVE_INHERITANCE_OK\n",
    'same-source inheritance passes all runtime checks',
);

if (!$closed || $output ne "VEYRA_NATIVE_INHERITANCE_OK\n") {
    diag "Perl executable: $^X";
    diag sprintf 'Perl version: %vd', $^V;
    diag "Child process status: $status";
    diag "Child output: $output";
}

done_testing;
