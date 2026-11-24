use strict;
use warnings;

use Test::More;
use File::Spec;
use File::Temp qw(tempdir);

use Class::Veyra::Compiler;

sub write_file {
    my ($path, $content) = @_;

    open my $handle, '>:raw', $path
        or die "Cannot create test file '$path': $!";

    print {$handle} $content
        or die "Cannot write test file '$path': $!";

    close $handle
        or die "Cannot close test file '$path': $!";
}

sub read_file {
    my ($path) = @_;

    open my $handle, '<:raw', $path
        or die "Cannot read test file '$path': $!";

    local $/;
    my $content = <$handle>;

    close $handle
        or die "Cannot close test file '$path': $!";

    return defined $content ? $content : '';
}

sub error_from {
    my ($callback) = @_;

    my $completed = eval {
        $callback->();
        1;
    };

    my $error = $@;

    return $completed ? '' : $error;
}

my $directory = tempdir(CLEANUP => 1);

my $input = File::Spec->catfile(
    $directory,
    'example.veyra',
);

my $output = File::Spec->catfile(
    $directory,
    'example.pm',
);

my $source = <<'VEYRA';
class VeyraFileExample {
    field $name :param;

    fun name {
        return $name;
    }
}
VEYRA

write_file($input, $source);

is(
    Class::Veyra::Compiler->compile_file($input, $output),
    $output,
    'compile_file returns the output path',
);

ok(
    -f $output,
    'creates the output file',
);

is(
    read_file($output),
    Class::Veyra::Compiler->compile($source),
    'writes exactly the generated Perl',
);

is(
    read_file($input),
    $source,
    'does not modify the input',
);

ok(
    !VeyraFileExample->can('new'),
    'does not execute generated code',
);

my $original_output = read_file($output);

like(
    error_from(sub {
        Class::Veyra::Compiler->compile_file($input, $output);
    }),
    qr/existing files are not overwritten/,
    'refuses an existing output file',
);

is(
    read_file($output),
    $original_output,
    'preserves an existing output file',
);

like(
    error_from(sub {
        Class::Veyra::Compiler->compile_file($input, $input);
    }),
    qr/existing files are not overwritten/,
    'refuses to overwrite the input with generated code',
);

is(
    read_file($input),
    $source,
    'input remains unchanged after same-path rejection',
);

my $invalid_input = File::Spec->catfile(
    $directory,
    'invalid.veyra',
);

my $invalid_output = File::Spec->catfile(
    $directory,
    'invalid.pm',
);

write_file(
    $invalid_input,
    'class VeyraInvalidFileExample { fun broken {} }',
);

isnt(
    error_from(sub {
        Class::Veyra::Compiler->compile_file(
            $invalid_input,
            $invalid_output,
        );
    }),
    '',
    'reports compilation failure',
);

ok(
    !-e $invalid_output,
    'compilation failure does not create an output file',
);

my $missing_input = File::Spec->catfile(
    $directory,
    'missing.veyra',
);

my $missing_output = File::Spec->catfile(
    $directory,
    'missing.pm',
);

like(
    error_from(sub {
        Class::Veyra::Compiler->compile_file(
            $missing_input,
            $missing_output,
        );
    }),
    qr/Cannot open input/,
    'reports a missing input file',
);

ok(
    !-e $missing_output,
    'missing input does not create an output file',
);

like(
    error_from(sub {
        Class::Veyra::Compiler->compile_file(undef, $output);
    }),
    qr/Input path must be a non-empty string/,
    'validates the input path',
);

like(
    error_from(sub {
        Class::Veyra::Compiler->compile_file($input, '');
    }),
    qr/Output path must be a non-empty string/,
    'validates the output path',
);

done_testing;
