use strict;
use warnings;

use Test::More;

use Cwd qw(abs_path getcwd);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);

use Class::Veyra::SourceLoader;

sub write_source {
    my ($root, $parts, $source) = @_;

    my @parts = @$parts;
    my $filename = pop @parts;

    my $directory = File::Spec->catdir(
        $root,
        @parts,
    );

    make_path($directory);

    my $path = File::Spec->catfile(
        $directory,
        $filename,
    );

    open my $handle, '>:raw', $path
        or die "Cannot write test source '$path': $!";

    print {$handle} $source
        or die "Cannot write test source '$path': $!";

    close $handle
        or die "Cannot close test source '$path': $!";

    return abs_path($path);
}

sub error_from {
    my ($code) = @_;

    my $completed = eval {
        $code->();
        1;
    };

    my $error = $@;

    return $completed ? '' : $error;
}

my $root = tempdir(CLEANUP => 1);

my $first = File::Spec->catdir($root, 'first');
my $second = File::Spec->catdir($root, 'second');

make_path($first, $second);

my $first_text =
    "class MyApp::Person {\r\n}\r\n";

my $first_path = write_source(
    $first,
    ['MyApp', 'Person.veyra'],
    $first_text,
);

my $second_path = write_source(
    $second,
    ['MyApp', 'Person.veyra'],
    "class MyApp::Person {}\n",
);

my $contract_path = write_source(
    $second,
    ['MyApp', 'Contracts', 'Named.veyra'],
    "interface MyApp::Contracts::Named { fun name; }\n",
);

my $plain_path = write_source(
    $first,
    ['Plain.veyra'],
    "class Plain {}\n",
);

write_source(
    $first,
    ['Empty.veyra'],
    '',
);

my $loader = Class::Veyra::SourceLoader->new(
    include_paths => [$first, $second],
);

isa_ok(
    $loader,
    'Class::Veyra::SourceLoader',
);

is(
    $loader->resolve('MyApp::Person'),
    $first_path,
    'maps qualified names to nested Veyra source paths',
);

my $loaded = $loader->load('MyApp::Person');

is(
    $loaded->{source_name},
    $first_path,
    'returns the canonical source filename',
);

is(
    $loaded->{source},
    $first_text,
    'preserves source contents including CRLF line endings',
);

is_deeply(
    [sort keys %$loaded],
    [qw(source source_name)],
    'returns the named-source input shape',
);

is(
    $loader->resolve('MyApp::Contracts::Named'),
    $contract_path,
    'continues searching later directories when needed',
);

my $reverse = Class::Veyra::SourceLoader->new(
    include_paths => [$second, $first],
);

is(
    $reverse->resolve('MyApp::Person'),
    $second_path,
    'uses the configured directory order',
);

is(
    $loader->resolve('Plain'),
    $plain_path,
    'supports unqualified source names',
);

is(
    $loader->load('Empty')->{source},
    '',
    'loads an empty source file',
);

like(
    error_from(sub {
        $loader->load('Missing::Person');
    }),
    qr/Cannot find Veyra source 'Missing::Person'/,
    'reports a missing source by logical name',
);

for my $invalid (
    undef,
    '',
    '../Person',
    'MyApp/Person',
    'MyApp::',
    'MyApp:::Person',
    'MyApp::2Person',
    'MyApp :: Person',
    [],
) {
    like(
        error_from(sub {
            $loader->resolve($invalid);
        }),
        qr/Invalid Veyra source name/,
        'rejects an invalid logical source name',
    );
}

like(
    error_from(sub {
        Class::Veyra::SourceLoader->new();
    }),
    qr/non-empty include_paths array/,
    'requires explicit search directories',
);

like(
    error_from(sub {
        Class::Veyra::SourceLoader->new(
            include_paths => [],
        );
    }),
    qr/non-empty include_paths array/,
    'rejects an empty search list',
);

like(
    error_from(sub {
        Class::Veyra::SourceLoader->new(
            include_paths => [
                File::Spec->catdir($root, 'missing'),
            ],
        );
    }),
    qr/is not a directory/,
    'rejects a missing search directory',
);

like(
    error_from(sub {
        Class::Veyra::SourceLoader->new(
            include_paths => [$first],
            unexpected    => 1,
        );
    }),
    qr/Unknown SourceLoader option 'unexpected'/,
    'rejects unknown constructor options',
);

my $original_directory = getcwd();

chdir $root
    or die "Cannot enter temporary directory: $!";

my $relative_loader = Class::Veyra::SourceLoader->new(
    include_paths => ['first'],
);

chdir $original_directory
    or die "Cannot restore working directory: $!";

is(
    $relative_loader->resolve('MyApp::Person'),
    $first_path,
    'anchors relative search directories at construction time',
);

done_testing;
