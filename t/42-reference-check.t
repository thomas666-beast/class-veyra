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
            source_name => 'User.veyra',
            source      => <<'VEYRA',
class App::Models::User {
    fun say_name {
        return "Alice";
    }
}
VEYRA
        },
        {
            source_name => 'Contract.veyra',
            source      => <<'VEYRA',
interface App::Named {
    fun say_name;
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

my $error = error_from(sub {
    Class::Veyra::Compiler->analyze_sources(project(<<'BODY'));
        my $user = App::Model::User->new();
BODY
});

like(
    $error,
    qr/Unknown class 'App::Model::User'/,
    'rejects a misspelled constructor class',
);

like(
    $error,
    qr/Did you mean 'App::Models::User'\?/,
    'suggests the nearest declared class',
);

like(
    $error,
    qr/\bbody line 2\b/,
    'counts the initial newline when reporting the member body line',
);

is(
    error_from(sub {
        Class::Veyra::Compiler->analyze_sources(project(<<'BODY'));
        my $user = App::Models::User->new();
BODY
    }),
    '',
    'accepts a declared class',
);

is(
    error_from(sub {
        Class::Veyra::Compiler->analyze_sources(project(<<'BODY'));
        # App::Missing::Thing->new();
        my $text = "App::Missing::Thing->new";
BODY
    }),
    '',
    'ignores class-like text in comments and strings',
);

like(
    error_from(sub {
        Class::Veyra::Compiler->analyze_sources(project(<<'BODY'));
        my $named = App::Named->new();
BODY
    }),
    qr/Interface 'App::Named' cannot be used as a class/,
    'rejects instantiating an interface',
);

done_testing;
