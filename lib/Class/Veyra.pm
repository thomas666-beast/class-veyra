package Class::Veyra;

use v5.38;
use strict;
use warnings;

use feature ();
use warnings ();

our $VERSION = '0.001';

sub import {
    strict->import;
    warnings->import;

    feature->import('class');
    warnings->unimport('experimental::class');

    return;
}

1;

__END__

=head1 NAME

Class::Veyra - Class syntax and explicit interfaces for Perl

=head1 SYNOPSIS

Create and run a project with the installed CLI:

    veyra create hello
    cd hello
    veyra run

The untouched starter prints:

    Hello, world!

Check, format, or build the project:

    veyra check
    veyra fmt --check
    veyra fmt
    veyra build

Forward application arguments to the configured runner:

    veyra run -- Alice --verbose

Show the version:

    veyra --version
    veyra version

Compile a Veyra module project through the API:

    use Class::Veyra::Compiler;

    my $perl = Class::Veyra::Compiler->compile_module(
        'MyApp::Employee',
        include_paths => ['src', 'vendor'],
    );

Analyze without generating Perl:

    my $project = Class::Veyra::Compiler->analyze_module(
        'MyApp::Employee',
        include_paths => ['src', 'vendor'],
    );

The low-level command-line equivalent writes a new output file:

    veyra-compile --module MyApp::Employee -I src \
        --output build/Employee.pm

=head1 DESCRIPTION

Class::Veyra is an early-development, pure-Perl compiler for a small
class language.

The compiler parses and validates Veyra source, then generates ordinary
Perl using Perl's native class feature. Generated programs do not require
Class::Veyra at runtime.

Implemented features include scalar instance fields, constructor
parameters, single inheritance, explicit interfaces, qualified names,
and transitive file-based imports.

The distribution includes project creation, checking, building,
execution, and conservative source formatting.

Veyra distinguishes two operation kinds:

    fun name {
        return $name;
    }

    act rename ($new_name) {
        $name = $new_name;
    }

A C<fun> returns exactly one value. An C<act> returns no values.
Interface checks distinguish operation kinds and required argument
counts. Overrides must preserve the required kind and arity.

=head1 PROJECT COMMANDS

The C<veyra> executable provides the project-level interface.

The C<check>, C<build>, C<run>, and C<fmt> commands discover
C<veyra.json> in the current directory or a parent directory.
Configured paths are resolved relative to that configuration file.

Creation, help, and version reporting do not require a project.

=head2 create

    veyra create hello

Creates a starter project containing C<veyra.json>, C<run.pl>,
C<src/App/Main.veyra>, and C<.gitignore>.

An existing destination is refused. Creation does not generate build
output.

=head2 check

    veyra check

Validates the entry module and its transitive imports, including
generated Perl syntax validation.

It does not write the configured build output or execute the runner.

=head2 build

    veyra build

Compiles the collected project to its configured output path, creating
the output directory when needed.

Unlike C<veyra-compile>, the project builder replaces an existing
generated output file. Compilation and generated Perl syntax validation
finish before replacement, so those validation failures leave the
previous output unchanged.

=head2 run

    veyra run
    veyra run -- Alice --verbose

Builds the project, then executes its configured Perl runner from the
project root.

A failed build prevents the runner from starting. An older generated
bundle is not used as a fallback.

Arguments after C<--> are forwarded unchanged to the runner's C<@ARGV>.
The runner decides how to use them; they are not automatically passed
to a Veyra operation.

An application option requires the separator:

    veyra run -- --help

C<veyra run --help> is a CLI usage error.

Both of the following run the application without arguments:

    veyra run
    veyra run --

The CLI propagates the runner's exit code. Signal termination is
reported as C<128 + signal number>.

=head2 fmt

    veyra fmt
    veyra fmt --check

Formats the configured entry module and its transitive imports.

The formatter normalizes declaration spacing and structural indentation.
It also adjusts indentation on existing operation-body lines, using
nested braces, parentheses, and brackets to determine indentation.

For example:

    class App::Main {
    act say_name ($name) {
    say 'Hello ' . $name;
    }
    }

becomes:

    class App::Main {
        act say_name ($name) {
            say 'Hello ' . $name;
        }
    }

String contents, including multiline-string whitespace, are preserved.
Comment text and order are preserved, although leading comment
indentation may change. Inline operation bodies remain inline.

Unrelated source files outside the entry import graph are not visited.
An imported source resolved outside the project root is refused.

An unused external include directory is allowed. The restriction applies
to collected source files, not merely to the presence of an external
directory in the configuration.

Outside operation bodies, structural line breaks are normalized to LF.
Within operation bodies, existing line endings remain unchanged while
leading indentation is adjusted.

Before replacement, original and proposed sources are analyzed. Their
generated Perl must have matching token types and contents after
whitespace tokens are excluded. String and comment contents are included
in the comparison.

This token comparison is a safeguard against unintended changes, not a
general proof of semantic equivalence.

Changed files are staged before replacement begins. Replacements occur
individually and are not a multi-file transaction. A filesystem error
during replacement may leave an earlier file formatted and a later file
unchanged.

The formatter preserves ordinary source permission bits. It does not
promise to preserve every filesystem attribute.

C<--check> reports paths needing formatting and prints a unified diff
without replacing files. Removed lines begin with C<->; proposed lines
begin with C<+>.

The current diff implementation produces one hunk per changed file,
with surrounding context.

C<--check> returns status C<1> when changes are needed and C<0> when
sources are already formatted. Errors also return C<1> and are written
to standard error. Formatting differences and diffs are reported on
standard output.

To apply changes and verify the result:

    veyra fmt
    veyra fmt --check

After successful formatting, the second command should print:

    All source files are formatted.

and return C<0>.

Formatting does not build the project or execute its runner.

=head2 version

    veyra version
    veyra --version

Prints the version declared by C<Class::Veyra>:

    veyra 0.001

Neither form requires a project. Extra arguments are rejected as invalid
usage.

=head2 help

    veyra help
    veyra --help
    veyra -h

Prints the project CLI usage information without requiring a project.

=head2 Exit status

Project command usage errors return C<2>. Project, validation, and
filesystem failures return C<1>.

Successful commands return C<0>, except that C<run> propagates the
application status and C<fmt --check> returns C<1> for formatting
differences.

=head1 PROJECT CONFIGURATION

A generated C<veyra.json> contains:

    {
      "entry": "App::Main",
      "include_paths": ["src"],
      "output": "build/Main.pm",
      "run": "run.pl"
    }

C<entry> names the logical entry module.

C<include_paths> is a non-empty array of source search directories,
searched in order.

C<output> names the generated Perl bundle.

C<run> names an ordinary Perl runner and is required by C<veyra run>.

Paths are resolved relative to the project configuration directory
unless absolute.

Changing the configured output path does not rewrite the runner.
A customized runner must load the appropriate generated bundle.

=head1 STATIC CALL CHECKING

The compiler performs conservative checks for supported calls with
statically identifiable targets.

=head2 Method arguments

Method argument-count checking applies to explicit operation signatures
and supported parenthesized calls whose argument count can be
determined.

For example:

    act rename ($new_name) {
        $name = $new_name;
    }

requires one argument in a supported statically countable call.

An explicit empty signature declares zero parameters:

    act reset () {
    }

The checker currently skips argument-count enforcement when the Veyra
declaration omits a signature. This is a checker limitation, not a
promise of unrestricted runtime arity.

Dynamic or uncertain argument-list sizes are left unresolved rather
than assigned guessed counts.

=head2 Constructor parameters

Constructor checking recognizes required named parameter fields:

    field $name :param;

For supported call forms, it rejects unknown parameter names and
missing required parameters, including inherited parameters.

Fields without C<:param> are not constructor parameters. The current
field syntax does not support parameter defaults or aliases.

Parenthesized named argument lists are checked when their shape can be
determined.

A bare constructor followed by a semicolon or the end of an operation
body is checked as a zero-argument call. Dynamic lists and unresolved
unparenthesized argument lists are left unresolved.

Successful static analysis does not prove that every runtime call
will succeed.

=head1 IMPORTS AND MODULE COMPILATION

A Veyra import:

    import MyApp::Person;

maps the logical name to C<MyApp/Person.veyra> beneath an explicitly
configured source search directory.

The requested file must declare C<MyApp::Person> as a class or
interface. Additional declarations are allowed.

Module compilation follows transitive imports and collects each
canonical source path once. Circular imports are allowed, but circular
inheritance is rejected.

Qualified names must be contiguous:

    MyApp::Person

not:

    MyApp :: Person

Imports do not create short-name aliases.

C<analyze_module> and C<compile_module> require an C<include_paths>
array reference containing at least one search directory. Directories
are searched in order; lookup does not use Perl's C<@INC>.

C<compile_module> returns generated Perl as a string. It does not execute
that Perl or write an output file.

The single-string, supplied-source, and single-file compiler APIs do
not perform filesystem import resolution.

=head1 PERL MODULES IN VEYRA CLASSES

Use C<use Module::Name ();> to declare a Perl dependency inside a
class:

    class App::User {
        use JSON::PP ();

        field $name :param;

        fun as_json {
            return JSON::PP::encode_json({name => $name});
        }
    }

The generator emits the declaration inside the corresponding Perl
class. Empty parentheses are required and suppress the module's
import hook. Use fully qualified function calls or external class
method calls. External signatures are not checked by Veyra.

These declarations are distinct from Veyra C<import>, which resolves
Veyra sources. A Perl module can be declared in more than one class,
but not twice in the same class. Import lists and version constraints
are not supported.

Formatting and Perl generation do not load the declared modules.
C<veyra check> and C<veyra build> load them during the generated Perl
syntax check. Loading the generated bundle also loads them, so they
must be installed in the relevant Perl environments.

=head1 LOW-LEVEL COMPILER CLI

The original C<veyra-compile> executable remains available independently
of the project CLI.

Module compilation:

    veyra-compile --module MyApp::Employee \
        -I src -I vendor \
        --output build/Employee.pm

Single-file compilation:

    veyra-compile --output build/Single.pm Single.veyra

Module mode follows transitive imports. Single-file mode does not
perform filesystem import resolution.

The output directory must already exist. Existing output files are
never overwritten.

The command returns C<0> for success or help, C<1> for compilation or
filesystem failure, and C<2> for invalid usage.

=head1 FORMATTER API

Format a source string without writing files:

    use Class::Veyra::Formatter;

    my $formatted = Class::Veyra::Formatter->format(
        $source,
        'example.veyra',
    );

The source name is optional and defaults to C<< <string> >>.

The formatter parses its input and output. It adjusts declaration
spacing and operation-body indentation while preserving non-whitespace
token types and contents, including strings and comments.

For project-level formatting:

    use Class::Veyra::ProjectFormatter;

    my $project = Class::Veyra::ProjectFormatter->load;

    my $would_change = $project->format(
        check_only => 1,
    );

    my $changed = $project->format;

Both project formatting calls return an array reference containing
sorted project-relative paths. Check mode does not write files.

The API does not automatically print CLI messages or diffs. To inspect
proposed changes, supply an C<on_change> callback:

    my $would_change = $project->format(
        check_only => 1,

        on_change => sub {
            my ($path, $original, $formatted) = @_;

            print "Would format $path\n";
        },
    );

The callback receives the project-relative path, original source, and
formatted source for each changed file. Callbacks run after project
validation and before any source replacements.

=head1 NATIVE-PERL CONVENIENCE IMPORT

This module also retains a convenience import for native Perl code:

    use Class::Veyra;

    class Person {
        field $name :param;

        method name {
            return $name;
        }
    }

    my $person = Person->new(name => 'Alice');

C<use Class::Veyra> enables strictness, warnings, and the native C<class>
feature in the importing lexical scope. It suppresses the
C<experimental::class> warning in that scope.

This import does not enable the Veyra C<fun>, C<act>, C<interface>, or
source-level C<import> syntax in ordinary Perl files. Use
L<Class::Veyra::Compiler> or the command-line compiler for Veyra source.

To load this module without invoking its convenience import:

    use Class::Veyra ();

=head1 REQUIREMENTS

Perl 5.38 or newer for the compiler and generated programs.

Perl's native class feature is experimental in Perl 5.38.

No non-core dependencies, XS, or source filters are required.

=head1 SAFETY

Compiler validation is not a security boundary.

Compiler APIs parse, validate, and generate code without running the
application. Project checking and building additionally syntax-check
generated Perl. C<veyra run> deliberately executes the configured
runner after a successful build.

Generated Perl, syntax checking, C<eval>, and loading a generated
bundle must not be considered safe for untrusted source merely because
compiler validation succeeded.

Formatter path checks and generated-token comparison help prevent
unintended edits. They are not an isolation mechanism for hostile
projects.

=head1 SEE ALSO

L<Class::Veyra::Compiler>, L<Class::Veyra::FileCompiler>,
L<Class::Veyra::Project>, L<Class::Veyra::ProjectCreator>,
L<Class::Veyra::Formatter>, L<Class::Veyra::ProjectFormatter>,
L<Class::Veyra::SourceDiff>

The distribution README contains the getting-started workflow,
configuration reference, a complete multi-file example, and build
instructions.

=cut
