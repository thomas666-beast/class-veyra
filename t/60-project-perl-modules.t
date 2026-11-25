use strict;
use warnings;

use Test::More;
use Cwd qw(getcwd);
use File::Spec;
use File::Temp qw(tempdir);

use Class::Veyra::Project;
use Class::Veyra::ProjectCreator;

sub write_file {
    my ($path, $content) = @_;
    open my $file, '>:raw', $path or die "Cannot open '$path': $!";
    print {$file} $content or die "Cannot write '$path': $!";
    close $file or die "Cannot close '$path': $!";
}

sub read_file {
    my ($path) = @_;
    open my $file, '<:raw', $path or die "Cannot open '$path': $!";
    local $/;
    return scalar <$file>;
}

sub run_perl {
    open my $child, '-|', $^X, @_ or die "Cannot start Perl: $!";
    my $stdout = do { local $/; <$child> };
    close $child;
    return ($?, $stdout // '');
}

my $distribution = getcwd();
my $include = '-I' . File::Spec->catdir($distribution, 'blib', 'lib');
my $veyra = File::Spec->catfile($distribution, 'script', 'veyra');
my $compiler = File::Spec->catfile($distribution, 'script', 'veyra-compile');
my $temp = tempdir('veyra modules XXXX', TMPDIR => 1, CLEANUP => 1);

END { chdir $distribution if defined $distribution }

chdir $temp or die "Cannot enter temporary directory: $!";
my $root = Class::Veyra::ProjectCreator->create('example');
chdir $root or die "Cannot enter test project: $!";

my $user_path = File::Spec->catfile('src', 'App', 'User.veyra');
my $main_path = File::Spec->catfile('src', 'App', 'Main.veyra');
my $user = <<'VEYRA';
class App::User {
use JSON::PP( );
    field $name :param;
    field $store :param;

    fun as_json {
        return JSON::PP::encode_json({name => $name});
    }

    fun encoder_json {
        my $json = JSON::PP->new();
        return $json->encode({name => $name});
    }

    fun stored_name {
        return $store->lookup($name);
    }
}
VEYRA

write_file($user_path, $user);
write_file($main_path, <<'VEYRA');
import App::User;

class App::Main {
    use JSON::PP ();

    fun message ($store) {
        my $user = App::User->new(name => "Alice", store => $store);
        my $decoded = JSON::PP::decode_json($user->as_json());
        return $decoded->{name} . ": " . $user->encoder_json() . " / " . $user->stored_name();
    }
}
VEYRA

write_file('run.pl', <<'PERL');
use v5.38;
use FindBin qw($Bin);

{
    package Local::Store;
    sub lookup { return 'stored ' . $_[1] }
}

die "The runner unexpectedly preloaded JSON::PP" if $INC{'JSON/PP.pm'};
require "$Bin/build/Main.pm";
die "The Veyra declaration imported a Perl name" if App::User->can('encode_json');
print App::Main->new()->message(bless({}, 'Local::Store')), "\n";
PERL

my ($status, $stdout) = run_perl($include, $veyra, 'check');
is($status, 0, 'project check accepts external modules and Veyra imports');
ok(!-e 'build', 'check does not generate build output');

($status, $stdout) = run_perl($include, $veyra, 'fmt', '--check');
is($status, 1 << 8, 'format check detects the unformatted declaration');
like($stdout, qr/^\+    use JSON::PP \(\);$/m, 'CLI diff shows the formatted declaration');
is(read_file($user_path), $user, 'format check does not change the source');

($status) = run_perl($include, $veyra, 'fmt');
is($status, 0, 'project formatter writes the declaration');
($status) = run_perl($include, $veyra, 'fmt', '--check');
is($status, 0, 'subsequent format check is clean');

($status, $stdout) = run_perl($include, $veyra, 'run');
is($status, 0, 'project runs with its class-local dependencies');
is($stdout, qq{Alice: {"name":"Alice"} / stored Alice\n},
    'qualified functions, external constructors, and injected objects work');

my $bundle = File::Spec->catfile('build', 'Main.pm');
my $good_bundle = read_file($bundle);
my @declarations = $good_bundle =~ /^    use JSON::PP \(\);$/mg;
is(scalar @declarations, 2, 'same dependency is allowed in two classes');

($status) = run_perl(
    $include, $compiler, '--module', 'App::Main', '-I', 'src',
    '--output', 'standalone.pm',
);
is($status, 0, 'low-level CLI generates a bundle with the same dependencies');
is(read_file('standalone.pm'), $good_bundle, 'low-level and project bundles match');

$user =~ s/(use JSON::PP\( \);)/$1\n    use VeyraTest::MissingPerlModule ();/;
write_file($user_path, $user);

($status, $stdout) = run_perl($include, $veyra, 'fmt', '--check');
is($status, 1 << 8, 'format check still finds changes without installed dependencies');
like($stdout, qr/^Would format .*User\.veyra\.$/m,
    'format check reports changes without loading dependencies');
is(read_file($user_path), $user, 'format check with a missing module does not write');

my $project = Class::Veyra::Project->load;
for my $command ('check', 'build') {
    my $ok = eval { $project->$command(); 1 };
    my $error = $@;
    ok(!$ok, "$command fails when a Perl dependency is missing");
    like($error, qr{Can't locate VeyraTest/MissingPerlModule\.pm},
        "$command reports the missing module");
}

is(read_file($bundle), $good_bundle, 'missing dependency leaves the previous bundle untouched');

chdir $distribution or die "Cannot restore working directory: $!";
done_testing;
