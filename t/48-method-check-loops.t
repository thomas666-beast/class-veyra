use strict;
use warnings;

use Test::More;

use Class::Veyra::Compiler;
use Class::Veyra::LoopFacts;

sub check_body {
    my ($body) = @_;

    my $completed = eval {
        Class::Veyra::Compiler->analyze_sources([
            {
                source_name => 'User.veyra',
                source      => <<'VEYRA',
class App::User {
    fun greeting {
        return "Hello";
    }
}
VEYRA
            },
            {
                source_name => 'Main.veyra',
                source      => <<"VEYRA",
class App::Main {
    act message {
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
    check_body(<<'BODY'),
        my $user = App::User->new();

        while (0) {
            $user->unknown_method();
            $user = 42;
        }
BODY
    '',
    'does not rely on an object type changed inside a loop',
);

like(
    check_body(<<'BODY'),
        my $user = App::User->new();

        while (0) {
            $user->unknown_method();
        }
BODY
    qr/Unknown method 'unknown_method' on 'App::User'/,
    'still checks an object not written inside the loop',
);

like(
    check_body(<<'BODY'),
        my $user = App::User->new();

        for my $index (1, 2) {
            $user->unknown_method();
        }
BODY
    qr/Unknown method 'unknown_method' on 'App::User'/,
    'a separate iteration variable does not disable object checking',
);

is(
    check_body(<<'BODY'),
        my $user = App::User->new();

        for $user (1, 2) {
            $user->unknown_method();
        }
BODY
    '',
    'recognizes assignment through a foreach iteration variable',
);

like(
    check_body(<<'BODY'),
        while (0) {
            App::User->unknown_method();
        }
BODY
    qr/Unknown method 'unknown_method' on 'App::User'/,
    'continues checking explicit class calls inside loops',
);

like(
    check_body(<<'BODY'),
        my $user = App::User->new();

        # while (1) { $user = 42; }
        my $example = 'for $user (1, 2)';

        $user->unknown_method();
BODY
    qr/Unknown method 'unknown_method' on 'App::User'/,
    'ignores loop-like text in comments and strings',
);

my $facts =
    Class::Veyra::LoopFacts->written_variables(<<'BODY');
while (0) {
    ++$count;
    $total += 1;
    $value = 42;
}
BODY

ok(
    $facts->{count},
    'recognizes prefix increment',
);

ok(
    $facts->{total},
    'recognizes compound assignment',
);

ok(
    $facts->{value},
    'recognizes ordinary assignment',
);

$facts = Class::Veyra::LoopFacts->written_variables(<<'BODY');
while (0) {
    print "body";
}
continue {
    $user = 42;
}
BODY

ok(
    $facts->{user},
    'includes assignments in a continue block',
);

$facts = Class::Veyra::LoopFacts->written_variables(<<'BODY');
$user = 42 while 0;
BODY

ok(
    $facts->{user},
    'uses conservative handling for postfix loops',
);

done_testing;
