package Class::Veyra::FileCompiler;

use v5.38;
use strict;
use warnings;

use Fcntl qw(O_WRONLY O_CREAT O_EXCL);

use Class::Veyra::Compiler;

sub compile_file {
    my ($class, $input_path, $output_path) = @_;

    _validate_path($input_path, 'Input');
    _validate_path($output_path, 'Output');

    open my $input, '<:raw', $input_path
        or die "Cannot open input '$input_path': $!\n";

    my $source = '';

    while (1) {
        my $read = read $input, my $chunk, 65536;

        unless (defined $read) {
            my $error = "$!";
            close $input;
            die "Cannot read input '$input_path': $error\n";
        }

        last if $read == 0;

        $source .= $chunk;
    }

    close $input
        or die "Cannot close input '$input_path': $!\n";

    my $generated =
        Class::Veyra::Compiler->compile($source);

    return _write_generated(
        $output_path,
        $generated,
    );
}

sub compile_module_file {
    my ($class, $entry_name, $output_path, %options) = @_;

    _validate_path($output_path, 'Output');

    my $generated =
        Class::Veyra::Compiler->compile_module(
            $entry_name,
            %options,
        );

    return _write_generated(
        $output_path,
        $generated,
    );
}

sub _write_generated {
    my ($output_path, $generated) = @_;

    sysopen my $output,
        $output_path,
        O_WRONLY | O_CREAT | O_EXCL,
        0666
        or die "Cannot create output '$output_path' "
            . "(existing files are not overwritten): $!\n";

    my $completed = eval {
        binmode $output, ':raw'
            or die "Cannot set output mode '$output_path': $!\n";

        print {$output} $generated
            or die "Cannot write output '$output_path': $!\n";

        close $output
            or die "Cannot close output '$output_path': $!\n";

        1;
    };

    unless ($completed) {
        my $error = $@;

        close $output if defined fileno $output;

        unless (unlink $output_path) {
            $error .=
                "Cannot remove incomplete output '$output_path': $!\n";
        }

        die $error;
    }

    return $output_path;
}

sub _validate_path {
    my ($path, $label) = @_;

    die "$label path must be a non-empty string\n"
        if !defined $path
            || ref $path
            || $path eq '';

    die "$label path must not contain a NUL byte\n"
        if index($path, "\0") >= 0;

    return;
}

1;
