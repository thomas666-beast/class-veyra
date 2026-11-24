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
    fun base_name {
        return "base";
    }
}
VEYRA
            },
            {
                source_name => 'Main.veyra',
                source      => <<"VEYRA",
class App::Main extends App::Base {
    fun greeting {
        return "Hello";
    }

    act say_hello {
        print "Hello!\\n";
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
        my $text = $self->greeting();
        print $text;
BODY
    '',
    'accepts a fun called through self',
);

is(
    check_body(<<'BODY'),
        $self->say_hello();
BODY
    '',
    'accepts an act called through self',
);

is(
    check_body(<<'BODY'),
        my $name = $self->base_name();
BODY
    '',
    'accepts an inherited method called through self',
);

my $error = check_body(<<'BODY');
        $self->say_helo();
BODY

like(
    $error,
    qr/Unknown method 'say_helo' on 'App::Main'/,
    'rejects a misspelled method called through self',
);

like(
    $error,
    qr/Did you mean 'say_hello'\?/,
    'suggests the correct method',
);

like(
    $error,
    qr/Class 'App::Main'.*act 'message':/s,
    'identifies the containing class and operation',
);

is(
    check_body(<<'BODY'),
        {
            $self->say_hello();
        }
BODY
    '',
    'keeps self available inside a nested block',
);

is(
    check_body(<<'BODY'),
        my $supported = $self->can('say_hello');
        my $matches = $self->isa('App::Base');
BODY
    '',
    'accepts universal object methods through self',
);

is(
    check_body(<<'BODY'),
        # $self->missing_method();
        my $example = '$self->missing_method()';
BODY
    '',
    'ignores self calls in comments and literal strings',
);

is(
    check_body(<<'BODY'),
        my $unknown = 42;
        $unknown->some_method();
BODY
    '',
    'does not assign the self type to unrelated variables',
);

done_testing;
