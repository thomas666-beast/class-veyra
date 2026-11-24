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

    fun result {
        return 42;
    }
}

class App::ConfiguredUser {
    field $name :param;
    field $options :param;
}

class App::NamedUser {
    field $name :param;
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

like(
    check_body(<<'BODY'),
        my $user = App::User->new();
        $user->missing();
BODY
    qr/Unknown method 'missing' on 'App::User'/,
    'still checks a direct constructor result',
);

like(
    check_body(<<'BODY'),
        my $user = App::User->new;
        $user->missing();
BODY
    qr/Unknown method 'missing' on 'App::User'/,
    'supports a direct constructor without parentheses',
);

like(
    check_body(<<'BODY'),
        my $user = App::ConfiguredUser->new(
            name => "Alice",
            options => [1, 2],
        );

        $user->missing();
BODY
    qr/Unknown method 'missing' on 'App::ConfiguredUser'/,
    'recognizes a constructor with nested argument delimiters',
);

is(
    check_body(<<'BODY'),
        my $result = App::User->new()->result();
        $result->unknown_method();
BODY
    '',
    'does not infer the constructor class for a chained result',
);

is(
    check_body(<<'BODY'),
        my $result = App::User->new() || 42;
        $result->unknown_method();
BODY
    '',
    'does not infer one class for a fallback expression',
);

is(
    check_body(<<'BODY'),
        my $result = App::User->new() ? 1 : 2;
        $result->unknown_method();
BODY
    '',
    'does not infer the constructor class for a conditional result',
);

is(
    check_body(<<'BODY'),
        my $user = App::User->new();
        $user = App::User->new()->result();
        $user->unknown_method();
BODY
    '',
    'clears the previous type after assigning a chained result',
);

like(
    check_body(<<'BODY'),
        my $user = 42;
        $user = App::User->new();
        $user->missing();
BODY
    qr/Unknown method 'missing' on 'App::User'/,
    'recognizes a direct constructor during reassignment',
);

like(
    check_body(<<'BODY'),
        my $user = App::NamedUser->new(
            name => "text containing ) and ;",
        ); # A trailing comment is permitted.

        $user->missing();
BODY
    qr/Unknown method 'missing' on 'App::NamedUser'/,
    'ignores string contents when matching constructor parentheses',
);

done_testing;
