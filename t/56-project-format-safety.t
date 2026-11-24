use strict;
use warnings;

use Test::More;

use Cwd qw(getcwd);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use JSON::PP qw(decode_json encode_json);

use Class::Veyra::ProjectCreator;
use Class::Veyra::ProjectFormatter;

sub read_file {
    my ($path) = @_;

    open my $handle, '<:raw', $path
        or die "Cannot read test file '$path': $!";

    local $/;
    my $text = <$handle>;

    close $handle
        or die "Cannot close test file '$path': $!";

    return defined $text ? $text : '';
}

sub write_file {
    my ($path, $text) = @_;

    open my $handle, '>:raw', $path
        or die "Cannot write test file '$path': $!";

    print {$handle} $text
        or die "Cannot write test file '$path': $!";

    close $handle
        or die "Cannot close test file '$path': $!";

    return;
}

sub error_from {
    my ($code) = @_;

    my $completed = eval {
        $code->();
        1;
    };

    return $completed ? '' : $@;
}

sub mode_of {
    my ($path) = @_;

    my @status = stat $path;

    die "Cannot inspect test file '$path': $!"
        unless @status;

    return $status[2] & 0777;
}

my $original_directory = getcwd();

my $temporary = tempdir(CLEANUP => 1);

chdir $temporary
    or die "Cannot enter temporary directory: $!";

my $root = Class::Veyra::ProjectCreator->create(
    'format-safety',
);

my $main = File::Spec->catfile(
    $root,
    'src',
    'App',
    'Main.veyra',
);

my $configuration_path = File::Spec->catfile(
    $root,
    'veyra.json',
);

my $build_directory = File::Spec->catdir(
    $root,
    'build',
);

my $external_include = File::Spec->catdir(
    $temporary,
    'external-sources',
);

my $external_directory = File::Spec->catdir(
    $external_include,
    'External',
);

make_path($external_directory);

my $external_source = File::Spec->catfile(
    $external_directory,
    'Thing.veyra',
);

my $external_text = <<'VEYRA';
class External::Thing{}
VEYRA

write_file(
    $external_source,
    $external_text,
);

my $configuration = decode_json(
    read_file($configuration_path),
);

push @{ $configuration->{include_paths} },
    $external_include;

write_file(
    $configuration_path,
    encode_json($configuration) . "\n",
);

my $configuration_before =
    read_file($configuration_path);

my $main_with_external_import = <<'VEYRA';
import External::Thing;class App::Main{act message{print "Hello";}}
VEYRA

write_file(
    $main,
    $main_with_external_import,
);

chdir $root
    or die "Cannot enter project directory: $!";

my $project = Class::Veyra::ProjectFormatter->load;

for my $check_only (1, 0) {
    my $label = $check_only
        ? 'check mode'
        : 'write mode';

    my $error = error_from(sub {
        $project->format(
            check_only => $check_only,
        );
    });

    like(
        $error,
        qr/Refusing to format source outside project root:/,
        "$label rejects a dependency outside the project",
    );

    is(
        read_file($main),
        $main_with_external_import,
        "$label leaves the local source unchanged",
    );

    is(
        read_file($external_source),
        $external_text,
        "$label leaves the external dependency unchanged",
    );

    is(
        read_file($configuration_path),
        $configuration_before,
        "$label leaves project configuration unchanged",
    );
}

ok(
    !-e $build_directory,
    'rejected formatting does not create build output',
);

my $local_source = <<'VEYRA';
class App::Main{act message{print "Hello";}}
VEYRA

my $formatted_local_source = <<'VEYRA';
class App::Main {
    act message {print "Hello";}
}
VEYRA

write_file(
    $main,
    $local_source,
);

SKIP: {
    skip 'POSIX permission bits are not tested on Windows', 4
        if $^O eq 'MSWin32';

    my $changed_mode = chmod 0640, $main;

    skip 'Cannot set the requested source permissions', 4
        unless $changed_mode && mode_of($main) == 0640;

    my $before_mode = mode_of($main);

    my $error = error_from(sub {
        $project->format(
            check_only => 1,
        );
    });

    is(
        $error,
        '',
        'format check accepts local sources with an unused external include path',
    );

    is(
        mode_of($main),
        $before_mode,
        'format check preserves source permissions',
    );

    $error = error_from(sub {
        $project->format;
    });

    is(
        $error,
        '',
        'write mode formats the local source successfully',
    );

    is(
        mode_of($main),
        $before_mode,
        'replacing a formatted source preserves its permission bits',
    );
}

# Run independently of the platform-specific permission assertions.
write_file(
    $main,
    $local_source,
);

my $local_error = error_from(sub {
    $project->format;
});

is(
    $local_error,
    '',
    'an unused external include directory does not prevent formatting',
);

is(
    read_file($main),
    $formatted_local_source,
    'formats a local source when no external dependency is imported',
);

is(
    read_file($external_source),
    $external_text,
    'local formatting leaves unused external sources untouched',
);

is(
    read_file($configuration_path),
    $configuration_before,
    'successful formatting leaves configuration unchanged',
);

my $unknown_option_error = error_from(sub {
    $project->format(
        unsupported => 1,
    );
});

like(
    $unknown_option_error,
    qr/Unknown project formatter option 'unsupported'/,
    'rejects unsupported formatter options',
);

is(
    read_file($main),
    $formatted_local_source,
    'an unsupported option leaves the source unchanged',
);

my @temporary_outputs = glob(
    File::Spec->catfile(
        $root,
        'src',
        'App',
        '.veyra-fmt-*',
    ),
);

is_deeply(
    \@temporary_outputs,
    [],
    'successful and rejected operations leave no staging files',
);

ok(
    !-e $build_directory,
    'formatting never creates build output',
);

chdir $original_directory
    or die "Cannot restore working directory: $!";

done_testing;
