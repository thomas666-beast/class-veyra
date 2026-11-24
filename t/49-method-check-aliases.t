use strict;
use warnings;

use Test::More;

use Class::Veyra::Compiler;

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
    fun own_name {
        return "Main";
    }

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
        my $other = $user;
        $other->greeting();
BODY
    '',
    'accepts a valid method through an object copy',
);

my $error = check_body(<<'BODY');
        my $user = App::User->new();
        my $other = $user;
        $other->greetng();
BODY

like(
    $error,
    qr/Unknown method 'greetng' on 'App::User'/,
    'checks a method through an object copy',
);

like(
    $error,
    qr/Did you mean 'greeting'\?/,
    'suggests the method on the copied type',
);

like(
    check_body(<<'BODY'),
        my $user = App::User->new();
        my $other = 42;
        $other = $user;
        $other->missing();
BODY
    qr/Unknown method 'missing' on 'App::User'/,
    'tracks a direct copy during reassignment',
);

like(
    check_body(<<'BODY'),
        my $user = App::User->new();
        my $first = $user;
        my $second = $first;
        $second->missing();
BODY
    qr/Unknown method 'missing' on 'App::User'/,
    'follows multiple direct copies',
);

like(
    check_body(<<'BODY'),
        my $other = $self;
        $other->own_nam();
BODY
    qr/Unknown method 'own_nam' on 'App::Main'/,
    'tracks a direct copy of self',
);

like(
    check_body(<<'BODY'),
        my $user = App::User->new();
        my $other = $user;

        $user = 42;

        $other->missing();
BODY
    qr/Unknown method 'missing' on 'App::User'/,
    'reassigning the source variable does not change the copied type',
);

is(
    check_body(<<'BODY'),
        my $user = App::User->new();
        my $other = $user;

        $other = 42;

        $other->unknown_method();
BODY
    '',
    'clears the copied type after an unrelated assignment',
);

is(
    check_body(<<'BODY'),
        my $source = 42;
        my $other = $source;
        $other->unknown_method();
BODY
    '',
    'does not invent a type for a copy of an unknown value',
);

is(
    check_body(<<'BODY'),
        my $user = App::User->new();

        while (0) {
            my $other = $user;
            $other->unknown_method();
            $user = 42;
        }
BODY
    '',
    'does not infer a copied type from a loop-written variable',
);

is(
    check_body(<<'BODY'),
        my $user = App::User->new();
        my $other = $user;

        {
            my $other = 42;
            $other->unknown_method();
        }

        $other->greeting();
BODY
    '',
    'preserves the outer copied type across a shadowing block',
);

done_testing;
