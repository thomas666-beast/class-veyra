# Class::Veyra

A small class language that compiles to ordinary Perl using Perl's
native class feature.

Class::Veyra provides explicit interfaces, functions, actions, constructor
parameters, inheritance, and file-based imports.

The compiler is written in pure Perl:

- No source filters.
- No XS.
- No non-core dependencies.
- No Class::Veyra runtime dependency in generated programs.

> Early-development software. The language and compiler interfaces may
> change. Compiler validation is not a security boundary.

## Requirements

Perl 5.38 or newer is required for the compiler and generated programs.

Perl's native class feature is experimental in Perl 5.38. Generated files
suppress the corresponding experimental warning.

The development test suite has been reported passing on Perl 5.40.1.
Compatibility with every supported Perl release has not been independently
verified.

## Build and test

From the distribution root:

```sh
perl Makefile.PL
make
make test
```

Display the build-staged command help:

```sh
perl -Mblib blib/script/veyra --help
perl -Mblib blib/script/veyra-compile --help
```

To install the distribution after testing:

```sh
make install
```

Installation permissions depend on your Perl environment.

## Quick start

With the distribution installed:

```sh
veyra create hello
cd hello
veyra run
```

Output:

```text
Hello, world!
```

The generated project contains:

```text
hello/
├── .gitignore
├── veyra.json
├── run.pl
└── src/
    └── App/
        └── Main.veyra
```

Creation refuses an existing destination and does not generate build
output.

### Run without installing

From the distribution root, after `make`:

```sh
perl -I blib/lib script/veyra create hello
cd hello
perl -I ../blib/lib ../script/veyra run
```

The remaining examples use the installed `veyra` command. For an
uninstalled checkout, substitute the appropriate invocation of
`script/veyra` with the build library on Perl's include path.

## A complete example

This example uses:

- An interface defining a contract.
- A class with a constructor parameter.
- A function that returns a greeting.
- An action that changes object state.
- Imports connecting multiple source files.
- An ordinary Perl runner.

Create the starter project:

```sh
veyra create greetings
cd greetings
```

Replace or add the files below.

### Project layout

```text
greetings/
├── .gitignore
├── veyra.json
├── run.pl
└── src/
    └── App/
        ├── Named.veyra
        ├── Greeter.veyra
        └── Main.veyra
```

### `veyra.json`

```json
{
  "entry": "App::Main",
  "include_paths": ["src"],
  "output": "build/Main.pm",
  "run": "run.pl"
}
```

### `src/App/Named.veyra`

```text
interface App::Named {
    fun name;
    act rename ($new_name);
}
```

The interface requires a zero-argument function named `name` and a
one-argument action named `rename`.

### `src/App/Greeter.veyra`

```text
import App::Named;

class App::Greeter implements App::Named {
    field $name :param;

    fun name {
        return $name;
    }

    fun greeting ($prefix) {
        return "$prefix, $name!";
    }

    act rename ($new_name) {
        $name = $new_name;
    }
}
```

The `:param` field is supplied by the constructor.

The `greeting` function returns one value. The `rename` action changes
the field without returning a value.

### `src/App/Main.veyra`

```text
import App::Greeter;

class App::Main {
    fun message {
        my $greeter = App::Greeter->new(name => "Alice");

        my $first = $greeter->greeting("Hello");

        $greeter->rename("Bob");

        return $first . "\n" . $greeter->greeting("Welcome");
    }
}
```

### `run.pl`

```perl
use v5.38;
use strict;
use warnings;

use FindBin qw($Bin);

require "$Bin/build/Main.pm";

my $app = App::Main->new();

print $app->message(), "\n";
```

The runner is ordinary Perl. It loads the generated bundle, constructs the
application object, and prints its result.

It does not load Class::Veyra.

### Check, format, and run

```sh
veyra check
veyra fmt
veyra fmt --check
veyra run
```

Application output:

```text
Hello, Alice!
Welcome, Bob!
```

The compiler follows imports from `App::Main`, collects the required
sources, and generates the configured Perl bundle.

You can also build and execute separately:

```sh
veyra build
perl run.pl
```

## Project commands

Project commands discover `veyra.json` in the current directory or a
parent directory.

Configured relative paths are resolved from the directory containing
that file.

### Create

```sh
veyra create hello
```

Creates a starter project.

An existing destination is refused.

### Check

```sh
veyra check
```

Validates the configured entry module and its transitive imports,
including generated Perl syntax validation.

Checking does not write the configured build output or execute the
runner.

### Build

```sh
veyra build
```

Compiles the collected project to its configured output path.

The builder creates the output directory when needed and can replace an
existing generated output file.

Compilation and generated Perl syntax validation finish before
replacement. Those validation failures leave the previous output
unchanged.

### Run

```sh
veyra run
```

Builds the project, then executes its configured Perl runner from the
project root.

A failed build prevents execution. An older generated bundle is not used
as a fallback.

Forward application arguments after `--`:

```sh
veyra run -- Alice --verbose
```

Arguments are passed to the runner's `@ARGV`, not automatically to a Veyra
operation.

To pass an option to the application:

```sh
veyra run -- --help
```

The runner decides how to interpret those arguments.

### Format

```sh
veyra fmt
```

Formats the entry module and its transitive imports.

The formatter:

- Normalizes declaration spacing and structural indentation.
- Adjusts indentation on existing operation-body lines.
- Uses nested braces, parentheses, and brackets to determine indentation.
- Preserves string contents, including multiline-string whitespace.
- Preserves comment text and order while allowing indentation changes.
- Leaves inline operation bodies inline.
- Does not visit unrelated sources outside the entry import graph.
- Refuses imported sources resolved outside the project root.
- Does not build the project or execute its runner.

For example:

```text
class App::Main {
act say_name ($name) {
say 'Hello ' . $name;
}
}
```

becomes:

```text
class App::Main {
    act say_name ($name) {
        say 'Hello ' . $name;
    }
}
```

An unused external include directory is allowed. The restriction applies
to imported source files, not merely to configured directory names.

Outside operation bodies, structural line breaks are normalized to LF.
Within operation bodies, existing line endings are retained while
leading indentation is adjusted.

### Check formatting

```sh
veyra fmt --check
```

Reports files needing formatting and prints a unified diff without
replacing source files.

For example:

```diff
Would format src/App/Main.veyra.
--- a/src/App/Main.veyra
+++ b/src/App/Main.veyra
@@ -4,6 +4,6 @@
     }
 
     act say_name ($name) {
-say 'Hello ' . $name;
+        say 'Hello ' . $name;
     }
 }
```

Lines beginning with `-` show original contents. Lines beginning with `+`
show proposed contents.

Check mode returns status `1` when changes are needed.

Apply the changes and verify them:

```sh
veyra fmt
veyra fmt --check
```

Once formatting is clean:

```text
All source files are formatted.
```

The check then returns status `0`.

Formatting differences are written to standard output. Errors are written
to standard error.

### Version and help

```sh
veyra --version
veyra version

veyra --help
veyra help
veyra -h
```

These commands do not require a project.

## Project configuration

A typical `veyra.json` is:

```json
{
  "entry": "App::Main",
  "include_paths": ["src"],
  "output": "build/Main.pm",
  "run": "run.pl"
}
```

| Key | Meaning |
| --- | --- |
| `entry` | Logical entry module name. |
| `include_paths` | Non-empty array of source search directories, searched in order. |
| `output` | Generated Perl bundle path. |
| `run` | Ordinary Perl runner used by `veyra run`. |

Relative paths are resolved from the configuration directory.

Changing `output` does not rewrite the runner. If you customize the output
path, update the runner to load the corresponding generated bundle.

## Language overview

### Fields and constructor parameters

```text
class Person {
    field $name :param;

    fun name {
        return $name;
    }
}
```

Construct the object from Perl or a supported Veyra operation body:

```perl
my $person = Person->new(name => "Alice");
```

Fields belong to individual object instances.

A field marked `:param` is a constructor parameter. A field without that
attribute is not a constructor parameter.

Fields are not automatically exposed as public accessors.

### Functions

A `fun` explicitly returns one value:

```text
fun greeting ($prefix) {
    return "$prefix, $name";
}
```

That value may be `undef` or a reference.

Explicit empty-list and comma-separated return lists are rejected:

```perl
return ();
return (1, 2);
```

Generated function bodies run in scalar context. Structural validation
does not infer the behavior of every arbitrary Perl expression.

### Actions

An `act` returns no values:

```text
act rename ($new_name) {
    $name = $new_name;
}
```

A bare `return;` can end an action early. An explicit `return ();` is also
allowed.

Returning a value is rejected.

An action returns an empty list in list context and `undef` in scalar
context. Its final expression is discarded.

### Arguments

Operation signatures declare required positional scalar parameters:

```text
fun greeting ($prefix) {
    return "$prefix, $name";
}
```

Generated method signatures reject missing and extra arguments.
Passing `undef` still supplies an argument.

An omitted signature and an explicit empty signature both declare zero
arguments at runtime.

The static method-call checker currently skips argument-count enforcement
for declarations with omitted signatures. That checker limitation does
not make their runtime signatures variadic.

Default and optional arguments are not supported.

### Interfaces

```text
interface Named {
    fun name;
    act rename ($new_name);
}
```

A class explicitly declares implementation:

```text
class Person implements Named {
    field $name :param;

    fun name {
        return $name;
    }

    act rename ($new_name) {
        $name = $new_name;
    }
}
```

The compiler checks operation names, operation kinds, and argument counts.

It does not check argument or return types.

Interfaces are compile-time contracts, not generated runtime classes.
Implementing `Named` does not make `$object->isa("Named")` true.

### Inheritance

A class may extend one parent:

```text
class Employee extends Person {
    field $title :param;

    fun title {
        return $title;
    }
}
```

Parents are emitted before children, regardless of declaration order.

Inherited operations may satisfy interfaces. Subclasses inherit their
parent's interface obligations, and overrides must preserve operation
kind and argument count.

Parent fields remain private to the parent class. Child operations should
use inherited operations instead of directly naming parent fields.

The operation name `new` is reserved by the generator.

### Imports

```text
import App::Greeter;
```

The logical name maps to:

```text
App/Greeter.veyra
```

beneath a configured source search directory.

The requested file must declare the requested class or interface.
Additional declarations are allowed.

Module compilation follows transitive imports and collects each canonical
source path once.

Circular imports are allowed; circular inheritance is rejected.

Qualified names must be contiguous:

```text
App::Greeter
```

not:

```text
App :: Greeter
```

Imports do not create short-name aliases.

### Use Perl or CPAN modules from a class

Declare each Perl dependency in the class that needs it. This
`src/App/User.veyra` encodes a user without any JSON setup in `run.pl`:

```text
class App::User {
    use JSON::PP ();

    field $name :param;

    fun as_json {
        return JSON::PP::encode_json({name => $name});
    }
}
```

To try it in a starter project, replace `src/App/Main.veyra` with:

```text
import App::User;

class App::Main {
    fun message {
        my $user = App::User->new(name => "Alice");
        return $user->as_json();
    }
}
```

Keep the generated `run.pl` and run `veyra run`. It prints
`{"name":"Alice"}`.

`import App::User;` resolves Veyra source. `use JSON::PP ();` emits a
Perl module declaration that loads the module without importing
functions. Use qualified names such as `JSON::PP::encode_json(...)`
or class calls such as `JSON::PP->new()`. Veyra does not validate
external function or method signatures.

Different classes can declare the same dependency. Perl normally
loads it once per interpreter. Declare it at most once per class;
import lists and version constraints are not supported.

Install non-core dependencies, such as `DBI` and its database driver,
into the Perl environment that builds and runs the project. A module
declaration does not install the module or create a connection.
Create shared connections at startup and pass the handles to the
classes that need them.

`veyra check` and `veyra build` syntax-check generated Perl, which
loads these dependencies and can execute their compile-time code.
`veyra fmt` does not load them, and `veyra-compile` only generates
Perl. A generated bundle still needs its declared Perl modules when
loaded, but it does not need Class::Veyra itself.

## Low-level compiler CLI

The original `veyra-compile` interface remains available independently of
the project CLI.

### Compile one file

From the distribution root:

```sh
perl -Mblib blib/script/veyra-compile \
    --output person.generated.pm \
    examples/person.veyra
```

Successful compilation is silent.

The output path is required, its parent directory must already exist,
and an existing output file is never overwritten.

Compilation does not execute the generated file.

Single-file compilation does not perform filesystem import resolution.

### Compile a module and its imports

With the distribution installed:

```sh
veyra-compile --module MyApp::Employee \
    -I src \
    -I vendor \
    --output build/Employee.pm
```

Module mode follows transitive imports using the supplied search
directories, in order.

The output directory must already exist.

Unlike `veyra build`, `veyra-compile` does not replace an existing output
file.

### Run the standalone example

After compiling `examples/person.veyra`:

```sh
perl -e '
    use strict;
    use warnings;

    require "./person.generated.pm";

    my $person = Person->new(name => "Alice");

    print $person->greeting("Hello"), "\n";

    $person->rename("Bob");

    print $person->name, "\n";
'
```

Expected output:

```text
Hello, Alice
Bob
```

This runtime command does not load Class::Veyra.

## Compiler API

Analyze a module and its transitive imports:

```perl
use Class::Veyra::Compiler;

my $project = Class::Veyra::Compiler->analyze_module(
    'MyApp::Employee',
    include_paths => ['src', 'vendor'],
);
```

Compile to a Perl source string:

```perl
my $perl = Class::Veyra::Compiler->compile_module(
    'MyApp::Employee',
    include_paths => ['src', 'vendor'],
);
```

These module APIs require an `include_paths` array reference containing at
least one search directory.

Source lookup does not use Perl's `@INC`.

`compile_module` returns generated Perl. It does not execute that Perl or
write an output file.

## Formatter API

Format a source string without writing files:

```perl
use Class::Veyra::Formatter;

my $formatted = Class::Veyra::Formatter->format(
    $source,
    'example.veyra',
);
```

The source name is optional and defaults to `<string>`.

For project-level formatting:

```perl
use Class::Veyra::ProjectFormatter;

my $project = Class::Veyra::ProjectFormatter->load;

my $would_change = $project->format(
    check_only => 1,
);

my $changed = $project->format;
```

Both calls return an array reference containing sorted project-relative
paths. Check mode does not replace source files.

The API does not automatically print CLI messages or diffs.

An `on_change` callback can inspect proposed changes:

```perl
my $would_change = $project->format(
    check_only => 1,

    on_change => sub {
        my ($path, $original, $formatted) = @_;

        print "Would format $path\n";
    },
);
```

Callbacks receive the project-relative path, original source, and
formatted source. They run after project validation and before source
replacement.

## Native Perl convenience import

The distribution also provides a convenience import for ordinary Perl:

```perl
use v5.38;
use Class::Veyra;

class Person {
    field $name :param;

    method name {
        return $name;
    }
}

my $person = Person->new(name => "Alice");

print $person->name, "\n";
```

`use Class::Veyra` enables strictness, warnings, and Perl's native class
feature in the importing lexical scope. It suppresses the
`experimental::class` warning in that scope.

It does not enable Veyra's `fun`, `act`, `interface`, or source-level
`import` syntax in ordinary Perl files.

Use the compiler API or CLI to compile Veyra source.

Load the module without its convenience import when needed:

```perl
use Class::Veyra ();
```

## Exit status

### Project CLI

| Status | Meaning |
| --- | --- |
| `0` | Successful command, help, or version reporting. |
| `1` | Project, validation, or filesystem failure. |
| `2` | Invalid command-line usage. |

Exceptions and qualifications:

- `veyra fmt --check` also returns `1` when formatting changes are needed.
- `veyra run` propagates the runner's exit status.
- Runner signal termination is reported as `128 + signal number`.

### Low-level compiler

| Status | Meaning |
| --- | --- |
| `0` | Successful compilation or help. |
| `1` | Compilation or filesystem failure. |
| `2` | Invalid command-line usage. |

## Limitations and safety

### Restricted operation bodies

Operation bodies support a restricted subset of Perl syntax.

The syntax guard rejects constructs including quote-like and
regular-expression operators, slash syntax, backticks, heredoc syntax,
nested sub declarations, and eval.

Generated operation bodies use an anonymous-subroutine wrapper to
implement return behavior. Caller inspection and similar introspection
are not promised to behave as if the body were written directly inside
a native method.

Static call checking is conservative. Dynamic or unresolved argument
lists are not assigned guessed argument counts.

### Not a sandbox

Compiler validation is not a security boundary.

Do not compile, syntax-check, load, or execute untrusted source as though
it were isolated.

Generated Perl and configured runners are executable code.

### Formatter safeguards

Before writing, project formatting analyzes both original and proposed
sources. Their generated Perl must have matching token types and contents
after whitespace tokens are excluded.

String and comment contents are included in that comparison.

This is a safeguard against unintended changes, not a general proof of
semantic equivalence.

Changed files are staged before replacement begins. Replacements happen
one file at a time, not as a multi-file transaction. A filesystem error
during replacement may leave earlier files formatted and later files
unchanged.

Ordinary source permission bits are preserved. Preservation of every
filesystem attribute is not promised.

### Low-level output publication

Low-level file compilation is not atomic publication. Another process
could observe an output file while it is being written.

## Development checks

Run the complete test suite:

```sh
perl Makefile.PL
make
make test
```

Run the project formatter and diff tests specifically:

```sh
prove -blv \
    t/53-formatter.t \
    t/54-project-format.t \
    t/58-source-diff.t
```

Before committing, review changes to source files, generated output, and
documentation separately.
