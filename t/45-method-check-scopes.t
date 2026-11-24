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
                source_name => 'Other.veyra',
                source      => <<'VEYRA',
class App::Other {
    fun description {
        return "Other";
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

        {
            my $user = App::Other->new();
            $user->description();
        }

        $user->greeting();
BODY
    '',
    'restores the outer type after a shadowing block',
);

like(
    check_body(<<'BODY'),
        my $user = App::User->new();

        {
            my $user = App::Other->new();
            $user->greeting();
        }
BODY
    qr/Unknown method 'greeting' on 'App::Other'/,
    'uses the inner type inside the shadowing block',
);

like(
    check_body(<<'BODY'),
        my $user = App::User->new();

        {
            my $user = App::Other->new();
            $user->description();
        }

        $user->description();
BODY
    qr/Unknown method 'description' on 'App::User'/,
    'continues checking the restored outer variable',
);

is(
    check_body(<<'BODY'),
        my $user = App::User->new();

        {
            my $user = 42;
            $user->anything();
        }

        $user->greeting();
BODY
    '',
    'an untyped inner variable does not erase the outer type',
);

is(
    check_body(<<'BODY'),
        my $user = App::User->new();

        {
            my $user = App::Other->new();

            {
                my $user = App::User->new();
                $user->greeting();
            }

            $user->description();
        }

        $user->greeting();
BODY
    '',
    'restores bindings through multiple nested scopes',
);

is(
    check_body(<<'BODY'),
        my $user = App::User->new();

        {
            $user = 42;
        }

        $user->anything();
BODY
    '',
    'does not restore a stale type after assigning to the outer variable',
);

is(
    check_body(<<'BODY'),
        my $user = App::User->new();

        {
            my $user = App::Other->new();
            $user = 42;
        }

        $user->greeting();
BODY
    '',
    'assigning to an inner variable does not invalidate the outer variable',
);

like(
    check_body(<<'BODY'),
        my $user = App::User->new();

        {
            my $user = App::Other->new();
        }

        {
            $user->description();
        }
BODY
    qr/Unknown method 'description' on 'App::User'/,
    'does not leak a shadowed type into a sibling block',
);

done_testing;
