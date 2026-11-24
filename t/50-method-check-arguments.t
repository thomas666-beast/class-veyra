use strict;
use warnings;

use Test::More;

use Class::Veyra::Compiler;

sub check_body {
    my ($body) = @_;

    my $completed = eval {
        Class::Veyra::Compiler->analyze_sources([
            {
                source_name => 'Base.veyra',
                source      => <<'VEYRA',
class App::Base {
    act inherited ($value) {
    }

    act overridden ($value) {
    }
}
VEYRA
            },
            {
                source_name => 'User.veyra',
                source      => <<'VEYRA',
class App::User extends App::Base {
    act rename ($name) {
    }

    act pair ($first, $second) {
    }

    act zero () {
    }

    act flexible {
    }

    act overridden ($value) {
    }

    fun echo ($value) {
        return $value;
    }
}
VEYRA
            },
            {
                source_name => 'Main.veyra',
                source      => <<"VEYRA",
class App::Main {
    act own_method (\$value) {
    }

    act message {
        my \$user = App::User->new();
$body
    }
}
VEYRA
            },
        ]);

        1;
    };

    return $completed ? '' : $@;
}

is(
    check_body('$user->rename("Alice");'),
    '',
    'accepts the required argument',
);

like(
    check_body('$user->rename();'),
    qr/Method 'App::User::rename' expects 1 argument, got 0/,
    'rejects a missing argument',
);

like(
    check_body('$user->rename("Alice", "Bob");'),
    qr/Method 'App::User::rename' expects 1 argument, got 2/,
    'rejects an extra argument',
);

is(
    check_body('$user->zero();'),
    '',
    'accepts an explicit zero-argument signature',
);

like(
    check_body('$user->zero(42);'),
    qr/Method 'App::User::zero' expects 0 arguments, got 1/,
    'rejects arguments for an explicit empty signature',
);

is(
    check_body('$user->pair("Alice", 42);'),
    '',
    'accepts two straightforward arguments',
);

is(
    check_body('$user->rename("Alice",);'),
    '',
    'does not count a trailing comma as an argument',
);

is(
    check_body('$user->pair(("Alice", 42));'),
    '',
    'counts a parenthesized literal list',
);

is(
    check_body('$user->pair([], {});'),
    '',
    'counts array and hash references as scalar arguments',
);

is(
    check_body('$user->rename("text with ), and commas");'),
    '',
    'does not split string contents into arguments',
);

like(
    check_body('$user->inherited();'),
    qr/Method 'App::User::inherited' expects 1 argument, got 0/,
    'checks the signature of an inherited method',
);

is(
    check_body('$user->overridden("Alice");'),
    '',
    'accepts a valid call to an overridden method',
);

like(
    check_body('$user->overridden("Alice", "Bob");'),
    qr/Method 'App::User::overridden' expects 1 argument, got 2/,
    'rejects extra arguments to an overridden method',
);

like(
    check_body('my $value = $user->echo();'),
    qr/Method 'App::User::echo' expects 1 argument, got 0/,
    'checks fun arguments as well as act arguments',
);

like(
    check_body('$self->own_method();'),
    qr/Method 'App::Main::own_method' expects 1 argument, got 0/,
    'checks calls through self',
);

like(
    check_body(<<'BODY'),
        my $other = $user;
        $other->rename();
BODY
    qr/Method 'App::User::rename' expects 1 argument, got 0/,
    'checks calls through a known object copy',
);

is(
    check_body('$user->flexible("Alice", "Bob");'),
    '',
    'does not impose a count on an operation without a signature',
);

is(
    check_body(<<'BODY'),
        my @arguments = ("Alice");
        $user->rename(@arguments);
BODY
    '',
    'does not guess the size of an expanded array',
);

is(
    check_body('$user->rename(some_function());'),
    '',
    'does not guess how many values an arbitrary function returns',
);

done_testing;
