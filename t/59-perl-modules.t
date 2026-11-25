use strict;
use warnings;

use Test::More;

use Class::Veyra::Compiler;
use Class::Veyra::Formatter;
use Class::Veyra::Parser;

sub error_from {
    my ($code) = @_;
    return eval { $code->(); 1 } ? '' : $@;
}

my $source = <<'VEYRA';
class App::User{
use JSON::PP( );
field $name :param;
use Digest::SHA ();
fun as_json {
return JSON::PP::encode_json({name => $name});
}
}
VEYRA

my $document = Class::Veyra::Parser->parse($source);
my ($user) = @{ $document->{classes} };

is_deeply(
    [map { [$_->{kind}, $_->{name}] } @{ $user->{members} }],
    [['use', 'JSON::PP'], ['field', 'name'],
        ['use', 'Digest::SHA'], ['fun', 'as_json']],
    'parses Perl module declarations in member order',
);

is_deeply($document->{imports}, [], 'Perl modules are not Veyra imports');

my $generated = Class::Veyra::Compiler->compile($source);
like(
    $generated,
    qr/class App::User \{\n    use JSON::PP \(\);\n    field \$name :param;\n    use Digest::SHA \(\);/,
    'generates no-import Perl declarations in class scope',
);
like(
    $generated,
    qr/JSON::PP::encode_json\(\{name => \$name\}\)/,
    'keeps the fully qualified function call',
);

my $formatted = Class::Veyra::Formatter->format($source);
like($formatted, qr/^    use JSON::PP \(\);$/m, 'formats the use member');
is(Class::Veyra::Formatter->format($formatted), $formatted, 'format is stable');

my $commented_use = "class App::User { use # external dependency\nJSON::PP ( # no imports\n); }";
my $formatted_comments = Class::Veyra::Formatter->format($commented_use);
like($formatted_comments, qr/# external dependency/, 'keeps the use comment');
like($formatted_comments, qr/# no imports/, 'keeps the comment inside the empty list');
is(Class::Veyra::Formatter->format($formatted_comments), $formatted_comments,
    'format is stable with comments');

for my $invalid (
    'use JSON::PP;',
    'use JSON::PP ("encode_json");',
    'use JSON::PP qw(encode_json);',
    'use JSON::PP 1.00 ();',
    'use v5.38;',
    'use v5 ();',
    'use JSON :: PP ();',
    'use JSON:: ();',
    'use JSON::PP ()',
) {
    like(
        error_from(sub { Class::Veyra::Parser->parse("class Bad { $invalid }") }),
        qr/Class 'Bad': Expected 'use Module::Name \(\);' at offset/,
        "rejects $invalid",
    );
}

like(
    error_from(sub {
        Class::Veyra::Parser->parse('class Bad { use JSON::PP (); use JSON::PP (); }');
    }),
    qr/Duplicate Perl module declaration 'JSON::PP'/,
    'rejects duplicate declarations in one class',
);

for my $invalid (
    'use JSON::PP (); class App::User {}',
    'interface App::Named { use JSON::PP (); }',
) {
    isnt(
        error_from(sub { Class::Veyra::Parser->parse($invalid) }),
        '', 'rejects a use declaration outside a class',
    );
}

my $missing = 'class App::User { use VeyraTest::MissingPerlModule (); }';
is(error_from(sub { Class::Veyra::Compiler->analyze($missing) }), '',
    'analysis does not load Perl dependencies');
like(Class::Veyra::Compiler->compile($missing), qr/use VeyraTest::MissingPerlModule \(\);/,
    'generating a bundle does not load Perl dependencies');

my $sibling = <<'VEYRA';
class App::Declared {
    use JSON::PP ();
}
class App::Undeclared {
    fun encoder {
        return JSON::PP->new();
    }
}
VEYRA

like(
    error_from(sub {
        Class::Veyra::Compiler->analyze_sources([
            {source_name => 'User.veyra', source => $sibling},
        ]);
    }),
    qr/Class 'App::Undeclared'.*Unknown class 'JSON::PP'/,
    'one class declaration does not relax another class reference checks',
);

done_testing;
