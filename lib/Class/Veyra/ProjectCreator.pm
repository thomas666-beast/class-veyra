package Class::Veyra::ProjectCreator;

use v5.38;
use strict;
use warnings;

use Fcntl qw(O_WRONLY O_CREAT O_EXCL);
use File::Path qw(make_path);
use File::Spec;

sub create {
    my ($class, $name) = @_;

    die "Project name must start with a letter and contain "
        . "only letters, digits, underscores, or hyphens\n"
        unless (
            defined $name
            && !ref $name
            && $name =~ /\A[A-Za-z][A-Za-z0-9_-]*\z/
        );

    my $root = File::Spec->rel2abs($name);

    die "Project destination '$name' already exists\n"
        if -e $root || -l $root;

    mkdir $root
        or die "Cannot create project directory '$root': $!\n";

    my $completed = eval {
        my $source_directory = File::Spec->catdir(
            $root,
            'src',
            'App',
        );

        make_path($source_directory);

        _write_file(
            File::Spec->catfile($root, 'veyra.json'),
            <<'JSON',
{
  "entry": "App::Main",
  "include_paths": ["src"],
  "output": "build/Main.pm",
  "run": "run.pl"
}
JSON
        );

        _write_file(
            File::Spec->catfile(
                $source_directory,
                'Main.veyra',
            ),
            <<'VEYRA',
class App::Main {
    fun message {
        return "Hello, world!";
    }
}
VEYRA
        );

        _write_file(
            File::Spec->catfile($root, 'run.pl'),
            <<'PERL',
use v5.38;
use strict;
use warnings;

use FindBin qw($Bin);

require "$Bin/build/Main.pm";

my $app = App::Main->new;

print $app->message, "\n";
PERL
        );

        _write_file(
            File::Spec->catfile($root, '.gitignore'),
            "/build/\n",
        );

        1;
    };

    unless ($completed) {
        my $error = $@;

        die "Project creation failed: $error"
            . "The partial project remains at '$root' "
            . "for inspection.\n";
    }

    return $root;
}

sub _write_file {
    my ($path, $contents) = @_;

    sysopen my $handle,
        $path,
        O_WRONLY | O_CREAT | O_EXCL,
        0666
        or die "Cannot create project file '$path': $!\n";

    binmode $handle, ':raw'
        or die "Cannot set project file mode '$path': $!\n";

    print {$handle} $contents
        or die "Cannot write project file '$path': $!\n";

    close $handle
        or die "Cannot close project file '$path': $!\n";

    return;
}

1;
