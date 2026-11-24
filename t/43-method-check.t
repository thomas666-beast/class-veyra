use strict;
use warnings;

use Test::More;

use Class::Veyra::Compiler;

sub error_from {
    my ($code) = @_;

    my $completed = eval {
        $code->();
        1;
    };

    return $completed ? '' : $@;
}

sub project {
    my ($main_body) = @_;

    return [
        {
            source_name => 'Base.veyra',
            source      => <<'VEYRA',
class App::Base {
    fun base_name {
        return "base";
    }
}
VEYRA
        },
        {
            source_name => 'User.veyra',
            source      => <<'VEYRA',
class App::Models::User extends App::Base {
    fun say_name {
        return "Alice";
    }
}
VEYRA
        },
        {
            source_name => 'Main.veyra',
            source      => <<"VEYRA",
class App::Main {
    act message {
$main_body
    }
}
VEYRA
        },
    ];
}

sub check_body {
    my ($body) = @_;

    return error_from(sub {
        Class::Veyra::Compiler->analyze_sources(project($body));
    });
}

is(
    check_body(<<'BODY'),
        my $user = App::Models::User->new();
        $user->say_name();
BODY
    '',
    'accepts a declared method on a known object',
);

my $error = check_body(<<'BODY');
        my $user = App::Models::User->new();
        $user->say_nam();
BODY

like(
    $error,
    qr/Unknown method 'say_nam' on 'App::Models::User'/,
    'rejects a misspelled method',
);

like(
    $error,
    qr/Did you mean 'say_name'\?/,
    'suggests the nearest method',
);

is(
    check_body(<<'BODY'),
        my $user = App::Models::User->new();
        $user->base_name();
BODY
    '',
    'accepts an inherited method',
);

is(
    check_body(<<'BODY'),
        my $user = App::Models::User->new();
        my $same = $user->isa('App::Base');
BODY
    '',
    'accepts universal Perl object methods',
);

like(
    check_body(<<'BODY'),
        App::Models::User->say_nam();
BODY
    qr/Unknown method 'say_nam' on 'App::Models::User'/,
    'checks methods called directly on a class',
);

is(
    check_body(<<'BODY'),
        my $user = App::Models::User->new();
        my $flag = 1;

        if ($flag) {
            $user = $flag;
        }

        $user->anything();
BODY
    '',
    'skips variables whose type became uncertain',
);

is(
    check_body(<<'BODY'),
        my $user = App::Models::User->new();
        # $user->bogus();
        my $text = "$user->bogus";
BODY
    '',
    'ignores method-like text in comments and strings',
);

done_testing;
