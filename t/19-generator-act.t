use strict;
use warnings;

use Test::More;

use Class::Veyra::Compiler;

my $source = <<'VEYRA';
class VeyraGeneratedCounter {
    field $count :param;
    field $skip :param;

    fun count {
        return $count;
    }

    act reset {
        $count = 0;
    }

    act increment {
        $count += 1;
    }

    act increment_via_self {
        $self->increment;
    }

    act increment_unless_skipped {
        return if $skip;
        $count += 1;
    }

    act stop_now {
        return;
        $count = 999;
    }

    act fail {
        die "Action failed\n";
    }
}
VEYRA

my $generated =
    Class::Veyra::Compiler->compile($source);

like(
    $generated,
    qr/method reset \(\)/,
    'generates a native method for act',
);

my $loaded = eval $generated;
my $load_error = $@;

ok(
    $loaded,
    'generated action class compiles and loads',
) or diag $load_error;

unless ($loaded) {
    done_testing;
    exit;
}

my $counter = VeyraGeneratedCounter->new(
    count => 10,
    skip  => 0,
);

my $scalar_result = $counter->increment;

is(
    $counter->count,
    11,
    'act changes an instance field',
);

is(
    $scalar_result,
    undef,
    'act discards its final expression in scalar context',
);

my @list_result = $counter->increment;

is(
    $counter->count,
    12,
    'act runs when called in list context',
);

is_deeply(
    \@list_result,
    [],
    'act returns an empty list rather than one undef',
);

$counter->increment;

is(
    $counter->count,
    13,
    'act runs when called in void context',
);

$counter->increment_via_self;

is(
    $counter->count,
    14,
    'act can call another operation through self',
);

$counter->increment_unless_skipped;

is(
    $counter->count,
    15,
    'conditional early return allows execution when false',
);

my $skipped = VeyraGeneratedCounter->new(
    count => 20,
    skip  => 1,
);

my @skipped_result =
    $skipped->increment_unless_skipped;

is(
    $skipped->count,
    20,
    'conditional early return skips the remaining body',
);

is_deeply(
    \@skipped_result,
    [],
    'early-returning act still returns an empty list',
);

$counter->stop_now;

is(
    $counter->count,
    15,
    'bare return stops the action body',
);

my @reset_result = $counter->reset;

is(
    $counter->count,
    0,
    'reset updates the field',
);

is_deeply(
    \@reset_result,
    [],
    'assignment result does not leak out of act',
);

my $accepted_extra_argument = eval {
    $counter->reset('unexpected');
    1;
};

ok(
    !$accepted_extra_argument,
    'zero-argument act rejects extra arguments',
);

my $completed = eval {
    $counter->fail;
    1;
};

my $error = $@;

ok(
    !$completed,
    'exceptions propagate out of act',
);

like(
    $error,
    qr/Action failed/,
    'exception message is preserved',
);

done_testing;
