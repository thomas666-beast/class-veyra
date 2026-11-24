package Class::Veyra::Project;

use v5.38;
use strict;
use warnings;

use Cwd qw(getcwd);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempfile);
use IO::Select;
use IPC::Open3 qw(open3);
use JSON::PP qw(decode_json);
use Symbol qw(gensym);

use Class::Veyra::Compiler;

sub load {
    my ($class) = @_;

    my $directory = getcwd();
    my $config_path;

    while (1) {
        my $candidate = File::Spec->catfile(
            $directory,
            'veyra.json',
        );

        if (-e $candidate || -l $candidate) {
            die "Project configuration '$candidate' is not a file\n"
                unless -f $candidate;

            $config_path = $candidate;
            last;
        }

        my $parent = dirname($directory);

        last if $parent eq $directory;

        $directory = $parent;
    }

    die "Cannot find veyra.json in the current directory or its parents\n"
        unless defined $config_path;

    my $text = _read_file($config_path);

    my $config = eval {
        decode_json($text);
    };

    my $json_error = $@;

    die "Cannot parse '$config_path': $json_error"
        if length $json_error;

    die "Project configuration must be a JSON object\n"
        unless ref $config eq 'HASH';

    my $entry = $config->{entry};

    die "Project configuration requires a valid entry module\n"
        unless (
            defined $entry
            && !ref $entry
            && $entry =~
                /\A[A-Za-z_][A-Za-z0-9_]*(?:::[A-Za-z_][A-Za-z0-9_]*)*\z/
        );

    my $includes = $config->{include_paths};

    die "Project configuration requires a non-empty include_paths array\n"
        unless (
            ref $includes eq 'ARRAY'
            && @$includes
        );

    for my $path (@$includes) {
        die "Each include_paths entry must be a non-empty string\n"
            unless _is_string($path);
    }

    die "Project configuration requires a non-empty output path\n"
        unless _is_string($config->{output});

    if (exists $config->{run}) {
        die "Project configuration run must be a non-empty string\n"
            unless _is_string($config->{run});
    }

    my @include_paths = map {
        File::Spec->rel2abs($_, $directory)
    } @$includes;

    my $output = File::Spec->rel2abs(
        $config->{output},
        $directory,
    );

    die "Project output cannot replace veyra.json\n"
        if $output eq $config_path;

    my $runner;

    if (exists $config->{run}) {
        $runner = File::Spec->rel2abs(
            $config->{run},
            $directory,
        );

        die "Project output cannot replace the configured runner\n"
            if $output eq $runner;
    }

    return bless {
        root          => $directory,
        config_path   => $config_path,
        entry         => $entry,
        include_paths => \@include_paths,
        output        => $output,
        output_label  => $config->{output},
        runner        => $runner,
    }, $class;
}

sub check {
    my ($self) = @_;

    $self->_validated_perl;

    return;
}

sub build {
    my ($self) = @_;

    my $generated = $self->_validated_perl;
    my $output = $self->{output};

    die "Project output '$output' is a symbolic link\n"
        if -l $output;

    die "Project output '$output' is not a regular file\n"
        if -e $output && !-f $output;

    my $directory = dirname($output);

    make_path($directory)
        unless -d $directory;

    my ($handle, $temporary) = tempfile(
        '.veyra-build-XXXXXXXX',
        DIR    => $directory,
        UNLINK => 0,
    );

    my $completed = eval {
        binmode $handle, ':raw'
            or die "Cannot set build output mode: $!\n";

        print {$handle} $generated
            or die "Cannot write build output: $!\n";

        close $handle
            or die "Cannot close build output: $!\n";

        rename $temporary, $output
            or die "Cannot replace project output '$output': $!\n";

        1;
    };

    unless ($completed) {
        my $error = $@;

        close $handle
            if defined fileno $handle;

        unlink $temporary;

        die $error;
    }

    return $output;
}

sub run {
    my ($self, @arguments) = @_;

    my $runner = $self->{runner};

    die "Project configuration requires a run path for 'veyra run'\n"
        unless defined $runner;

    die "Configured runner '$runner' is not a file\n"
        unless -f $runner;

    $self->build;

    my $original_directory = getcwd();

    chdir $self->{root}
        or die "Cannot enter project directory '$self->{root}': $!\n";

    my $status = system { $^X } $^X, $runner, @arguments;
    my $execution_error = "$!";

    chdir $original_directory
        or die "Cannot restore working directory "
            . "'$original_directory': $!\n";

    die "Cannot execute runner '$runner': $execution_error\n"
        if $status == -1;

    return 128 + ($status & 127)
        if $status & 127;

    return $status >> 8;
}

sub entry {
    my ($self) = @_;

    return $self->{entry};
}

sub output_label {
    my ($self) = @_;

    return $self->{output_label};
}

sub _validated_perl {
    my ($self) = @_;

    my $generated =
        Class::Veyra::Compiler->compile_module(
            $self->{entry},
            include_paths => $self->{include_paths},
        );

    _check_perl_syntax($generated);

    return $generated;
}

sub _check_perl_syntax {
    my ($generated) = @_;

    my ($handle, $temporary) = tempfile(
        'veyra-check-XXXXXXXX',
        SUFFIX => '.pm',
        TMPDIR => 1,
        UNLINK => 1,
    );

    my $completed = eval {
        binmode $handle, ':raw'
            or die "Cannot set syntax-check file mode: $!\n";

        print {$handle} $generated
            or die "Cannot write syntax-check file: $!\n";

        close $handle
            or die "Cannot close syntax-check file: $!\n";

        my ($status, $diagnostics) = _capture_command(
            $^X,
            '-c',
            $temporary,
        );

        if ($status != 0) {
            $diagnostics = "Perl exited with status $status\n"
                unless length $diagnostics;

            die "Generated Perl failed validation "
                . "(line numbers refer to generated Perl):\n"
                . $diagnostics;
        }

        1;
    };

    my $error = $@;

    close $handle
        if defined fileno $handle;

    unlink $temporary;

    die $error
        unless $completed;

    return;
}

sub _capture_command {
    my (@command) = @_;

    my $error_handle = gensym;

    my $pid = open3(
        my $input,
        my $output,
        $error_handle,
        @command,
    );

    close $input;

    my $selector = IO::Select->new(
        $output,
        $error_handle,
    );

    my $diagnostics = '';
    my $read_error = '';

    while ($selector->count) {
        for my $handle ($selector->can_read) {
            my $buffer = '';

            my $count = sysread(
                $handle,
                $buffer,
                8192,
            );

            unless (defined $count) {
                next if $!{EINTR};

                $read_error ||= "Cannot read Perl diagnostics: $!\n";

                $selector->remove($handle);
                close $handle;

                next;
            }

            if ($count == 0) {
                $selector->remove($handle);
                close $handle;

                next;
            }

            $diagnostics .= $buffer;
        }
    }

    my $waited;

    do {
        $waited = waitpid $pid, 0;
    } while ($waited == -1 && $!{EINTR});

    die "Cannot wait for Perl syntax check: $!\n"
        if $waited == -1;

    my $status = $?;

    die $read_error
        if length $read_error;

    return ($status, $diagnostics);
}

sub _is_string {
    my ($value) = @_;

    return (
        defined $value
        && !ref $value
        && length $value
        && index($value, "\0") < 0
    );
}

sub _read_file {
    my ($path) = @_;

    open my $handle, '<:raw', $path
        or die "Cannot read project configuration '$path': $!\n";

    local $/;
    my $text = <$handle>;

    close $handle
        or die "Cannot close project configuration '$path': $!\n";

    return defined $text ? $text : '';
}

1;
