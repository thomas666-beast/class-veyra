use strict;
use warnings;

use Test::More;

use Class::Veyra::Compiler;
use Class::Veyra::ConstructorCheck;

sub check_body {
    my ($body) = @_;

    my $completed = eval {
        Class::Veyra::Compiler->analyze_sources([
            {
                source_name => 'Base.veyra',
                source      => <<'VEYRA',
class App::Base {
    field $tenant :param;
}
VEYRA
            },
            {
                source_name => 'User.veyra',
                source      => <<'VEYRA',
class App::User extends App::Base {
    field $name :param;
    field $internal;
}
VEYRA
            },
            {
                source_name => 'Empty.veyra',
                source      => <<'VEYRA',
class App::Empty {}
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
        my $user = App::User->new(
            tenant => "example",
            name => "Alice",
        );
BODY
    '',
    'accepts declared and inherited constructor parameters',
);

my $error = check_body(<<'BODY');
        my $user = App::User->new(
            tenant => "example",
            nmae => "Alice",
        );
BODY

like(
    $error,
    qr/Unknown constructor parameter 'nmae' for 'App::User'/,
    'rejects a misspelled constructor parameter',
);

like(
    $error,
    qr/Did you mean 'name'\?/,
    'suggests the declared parameter name',
);

like(
    check_body(<<'BODY'),
        my $user = App::User->new();
BODY
    qr/missing required parameter\(s\): name, tenant\b/,
    'reports missing local and inherited parameters',
);

like(
    check_body(<<'BODY'),
        my $user = App::User->new(
            name => "Alice",
        );
BODY
    qr/missing required parameter\(s\): tenant\b/,
    'requires an inherited parameter',
);

like(
    check_body(<<'BODY'),
        my $user = App::User->new(
            tenant => "example",
            name => "Alice",
            internal => 42,
        );
BODY
    qr/Unknown constructor parameter 'internal'/,
    'does not expose a field without the param attribute',
);

is(
    check_body(<<'BODY'),
        my $user = App::User->new(
            'tenant', 'example',
            'name', 'Alice',
        );
BODY
    '',
    'accepts plain quoted parameter names in a comma-separated list',
);

is(
    check_body(<<'BODY'),
        my $user = App::User->new(
            "tenant" => "example",
            "name" => "Alice",
        );
BODY
    '',
    'accepts plain double-quoted parameter names',
);

is(
    check_body(<<'BODY'),
        my $tenant = "example";
        my $name = "Alice";

        my $user = App::User->new(
            tenant => $tenant,
            name => $name,
        );
BODY
    '',
    'accepts scalar variables as parameter values',
);

is(
    check_body(<<'BODY'),
        my $empty = App::Empty->new();
BODY
    '',
    'accepts an empty constructor for a class without parameters',
);

like(
    check_body(<<'BODY'),
        my $empty = App::Empty->new(
            unknown => 42,
        );
BODY
    qr/Unknown constructor parameter 'unknown' for 'App::Empty'/,
    'rejects unknown parameters on a class without param fields',
);

is(
    check_body(<<'BODY'),
        my %parameters;

        my $user = App::User->new(%parameters);
BODY
    '',
    'does not guess parameter names from an expanded hash',
);

is(
    check_body(<<'BODY'),
        my %parameters;

        my $user = App::User->new(
            name => "Alice",
            %parameters,
        );
BODY
    '',
    'does not report missing parameters for a partially dynamic list',
);

is(
    check_body(<<'BODY'),
        # App::User->new(unknown => 42);
        my $example = 'App::User->new(unknown => 42)';
BODY
    '',
    'ignores constructor-like text in comments and strings',
);

like(
    check_body(<<'BODY'),
        my $user = App::User->new;
BODY
    qr/Constructor 'App::User' is missing required parameter\(s\): name, tenant\b/,
    'checks a bare constructor in a declaration',
);

like(
    check_body(<<'BODY'),
        my $user;
        $user = App::User->new;
BODY
    qr/Constructor 'App::User' is missing required parameter\(s\): name, tenant\b/,
    'checks a bare constructor during reassignment',
);

like(
    check_body(<<'BODY'),
        my $base = App::Base->new;
BODY
    qr/Constructor 'App::Base' is missing required parameter\(s\): tenant\b/,
    'checks required parameters on a bare parent-class constructor',
);

is(
    check_body(<<'BODY'),
        my $empty = App::Empty->new;
BODY
    '',
    'accepts a bare constructor without required parameters',
);

like(
    check_body(<<'BODY'),
        my $user = App::User->new # No constructor arguments.
            ;
BODY
    qr/Constructor 'App::User' is missing required parameter\(s\): name, tenant\b/,
    'ignores comments before the terminating semicolon',
);

is(
    check_body(<<'BODY'),
        my $user = App::User->new # Arguments follow the comment.
        (
            tenant => "example",
            name => "Alice",
        );
BODY
    '',
    'preserves parenthesized arguments after a comment',
);

{
    my %classes = (
        'App::Required' => {
            name    => 'App::Required',
            members => [
                {
                    kind      => 'field',
                    name      => 'name',
                    parameter => 1,
                },
            ],
        },
    );

    my $check_fragment = sub {
        my ($source) = @_;

        my $completed = eval {
            Class::Veyra::ConstructorCheck->check_body(
                $source,
                \%classes,
            );

            1;
        };

        return $completed ? '' : $@;
    };

    like(
        $check_fragment->('App::Required->new'),
        qr/Constructor 'App::Required' is missing required parameter\(s\): name\b/,
        'checks a bare constructor at the end of a body',
    );

    like(
        $check_fragment->(
            "App::Required->new # Trailing comment\n"
        ),
        qr/Constructor 'App::Required' is missing required parameter\(s\): name\b/,
        'ignores a trailing comment at the end of a body',
    );

    is(
        $check_fragment->(
            'App::Required->new name => "Alice";'
        ),
        '',
        'does not treat unparenthesized named arguments as zero arguments',
    );

    is(
        $check_fragment->(
            'App::Required->new %parameters;'
        ),
        '',
        'leaves an unparenthesized expanded hash unresolved',
    );

    is(
        $check_fragment->(
            'App::Required->new "name", "Alice";'
        ),
        '',
        'does not mistake a string argument for the end of a call',
    );
}

done_testing;
