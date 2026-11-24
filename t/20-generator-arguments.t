use strict;
use warnings;

use Test::More;

use Class::Veyra::Compiler;

my $source = <<'VEYRA';
class VeyraGeneratedAccount {
    field $name :param;
    field $balance :param;

    fun name {
        return $name;
    }

    fun balance {
        return $balance;
    }

    fun add ($left, $right) {
        return $left + $right;
    }

    fun echo ($value) {
        return $value;
    }

    act rename ($new_name) {
        $name = $new_name;
    }

    act deposit ($amount) {
        $balance += $amount;
    }

    act deposit_twice ($amount) {
        $self->deposit($amount);
        $self->deposit($amount);
    }
}
VEYRA

my $generated =
    Class::Veyra::Compiler->compile($source);

like(
    $generated,
    qr/method add \(\$left, \$right\)/,
    'generates multiple arguments in declaration order',
);

like(
    $generated,
    qr/method rename \(\$new_name\)/,
    'generates an action argument',
);

my $loaded = eval $generated;
my $load_error = $@;

ok(
    $loaded,
    'generated class with arguments compiles and loads',
) or diag $load_error;

unless ($loaded) {
    done_testing;
    exit;
}

my $account = VeyraGeneratedAccount->new(
    name    => 'Alice',
    balance => 100,
);

is(
    $account->add(4, 7),
    11,
    'fun receives multiple arguments',
);

is(
    $account->echo(undef),
    undef,
    'undef is accepted as an argument value',
);

my @sum = $account->add(4, 7);

is_deeply(
    \@sum,
    [11],
    'fun with arguments returns one value in list context',
);

my $rename_result = $account->rename('Bob');

is(
    $account->name,
    'Bob',
    'act argument can update a field',
);

is(
    $rename_result,
    undef,
    'act with arguments returns undef in scalar context',
);

my @deposit_result = $account->deposit(25);

is(
    $account->balance,
    125,
    'act uses a numeric argument',
);

is_deeply(
    \@deposit_result,
    [],
    'act with arguments returns an empty list',
);

$account->deposit_twice(10);

is(
    $account->balance,
    145,
    'act can forward an argument through self',
);

sub call_error {
    my ($callback) = @_;

    my $completed = eval {
        $callback->();
        1;
    };

    my $error = $@;

    return $completed ? '' : $error;
}

isnt(
    call_error(sub { $account->add(1) }),
    '',
    'fun rejects missing arguments',
);

isnt(
    call_error(sub { $account->add(1, 2, 3) }),
    '',
    'fun rejects extra arguments',
);

isnt(
    call_error(sub { $account->rename() }),
    '',
    'act rejects missing arguments',
);

isnt(
    call_error(sub { $account->rename('Carol', 'extra') }),
    '',
    'act rejects extra arguments',
);

is(
    $account->name,
    'Bob',
    'invalid calls do not run the action body',
);

is(
    $account->balance,
    145,
    'argument tests do not change unrelated fields',
);

done_testing;
