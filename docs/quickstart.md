# Class::Veyra quick start

Class::Veyra compiles a small class language into ordinary Perl
source using Perl's native class feature.

The compiler is written in pure Perl. It uses no source filters,
no XS, and no non-core dependencies.

Generated files do not require Class::Veyra at runtime.

## Requirements

The distribution declares Perl 5.38 as its minimum version.

The development test suite has been reported passing on
Perl 5.40.1, including same-file native inheritance. Compatibility
with every supported Perl release has not been independently
verified.

Native class warnings are suppressed in generated files.

## Build and test

From the distribution root:

```sh
perl Makefile.PL
make
make test
```

Display the build-staged project CLI help:

```sh
perl -Mblib blib/script/veyra --help
```

Display the low-level compiler's help:

```sh
perl -Mblib blib/script/veyra-compile --help
```

## Create and run a project

With the distribution installed:

```sh
veyra create hello
cd hello
veyra run
```

The untouched starter prints:

```text
Hello, world!
```

Creation writes:

```text
hello/
    .gitignore
    veyra.json
    run.pl
    src/
        App/
            Main.veyra
```

An existing destination is refused.

`veyra run` builds the project and then executes its configured
Perl runner from the project root.

A failed build prevents the runner from starting. An older build
is not used as a fallback.

### Use the CLI without installing

From the distribution root, after `make`:

```sh
perl -I blib/lib script/veyra create hello
cd hello
perl -I ../blib/lib ../script/veyra run
```

The remaining examples use the installed `veyra` command.
For an uninstalled checkout, substitute the appropriate
`perl -I ... .../script/veyra` invocation.

## Project configuration

The starter contains this `veyra.json`:

```json
{
  "entry": "App::Main",
  "include_paths": ["src"],
  "output": "build/Main.pm",
  "run": "run.pl"
}
```

- `entry` names the logical entry module.
- `include_paths` lists source search directories, in order.
- `output` names the generated Perl bundle.
- `run` names the ordinary Perl runner.

Relative paths are resolved from the directory containing
`veyra.json`.

Project commands discover the configuration in the current
directory or a parent directory, so they can also be run from
a nested source directory.

Changing `output` does not rewrite `run.pl`. A customized runner
must load the corresponding generated bundle.

## Check and build

Validate the entry module and its transitive imports:

```sh
veyra check
```

Checking does not write build output or execute the runner.

Build without running:

```sh
veyra build
```

The project builder creates the output directory when needed
and replaces an existing generated output file after compilation
and generated Perl syntax validation succeed.

This replacement behavior belongs to the project builder.
The low-level `veyra-compile` command still refuses to overwrite
existing output files.

## Format source

Apply formatting:

```sh
veyra fmt
```

Check formatting without modifying source files:

```sh
veyra fmt --check
```

The formatter visits the entry module and its transitive imports.
It does not format unrelated source files outside that import graph.

It normalizes declaration spacing and structural indentation,
including indentation on existing operation-body lines.

For example:

```text
class App::Main {
    fun message {
        return "Hello, world!";
    }

    act say_name ($name) {
say 'Hello ' . $name;
    }
}
```

becomes:

```text
class App::Main {
    fun message {
        return "Hello, world!";
    }

    act say_name ($name) {
        say 'Hello ' . $name;
    }
}
```

Check mode reports each changed file and shows a unified diff:

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

Lines beginning with `-` show original contents. Lines beginning
with `+` show proposed contents.

Check mode exits with status `1` when changes are needed.
This does not by itself mean formatting failed.

To apply changes and verify the result:

```sh
veyra fmt
veyra fmt --check
```

The second command should print:

```text
All source files are formatted.
```

and return status `0`.

Formatting does not build the project or execute its runner.
Imported source files resolved outside the project root are refused.

## Forward application arguments

Use `--` to separate CLI arguments from application arguments:

```sh
veyra run -- Alice --verbose
```

The arguments are forwarded to the runner's `@ARGV`.
They are not automatically passed to a Veyra operation.

For example:

```sh
veyra run -- --help
```

passes `--help` to the application.

## Compile the standalone example

The original `veyra-compile` interface remains available
independently of the project CLI.

From the distribution root:

```sh
perl -Mblib blib/script/veyra-compile \
    --output person.generated.pm \
    examples/person.veyra
```

Successful compilation is silent.

The output path is required, and its parent directory must
already exist.

The compiler refuses to overwrite an existing output file.
If `person.generated.pm` already exists, use a different output
path.

Compilation validates the source and writes generated Perl.
It does not execute the generated file.

## Run the standalone generated code

From the same directory:

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

The runtime command does not load Class::Veyra.

## Fields

A field belongs to each object instance:

```text
field $name :param;
```

The `:param` attribute makes the field a constructor parameter:

```perl
my $person = Person->new(name => "Alice");
```

Fields are accessed directly inside operations declared in their
class. They are not automatically exposed as public accessors.

## Functions

A `fun` is an object operation that explicitly returns one value:

```text
fun greeting ($prefix) {
    return "$prefix, $name";
}
```

The value may be `undef` or a reference.

An explicit empty-list return or an explicit comma-separated
return list is rejected:

```perl
return ();
return (1, 2);
```

Generated function bodies run in scalar context. The compiler's
structural checks do not infer the number of values that every
arbitrary Perl expression might otherwise produce.

## Actions

An `act` is an object operation that returns no values:

```text
act rename ($new_name) {
    $name = $new_name;
}
```

A bare `return;` may end an action early. An explicit
`return ();` is also allowed.

Returning a value is rejected.

An action returns an empty list in list context and `undef` in
scalar context. Its final expression is discarded.

## Arguments

Arguments are required positional scalar parameters:

```text
fun greeting ($prefix) {
    return "$prefix, $name";
}
```

Missing and extra arguments are rejected by the generated method
signature. Passing `undef` still supplies an argument.

An omitted signature and an explicit empty signature both declare
zero arguments at runtime:

```text
fun name {
    return $name;
}

act reset () {
}
```

The static method-call checker currently skips argument-count
enforcement for declarations with an omitted signature.
That limitation does not make their runtime signatures variadic.

Default and optional arguments are not supported.

## Interfaces

An interface declares required operations:

```text
interface Named {
    fun name;
    act rename ($new_name);
}
```

A class explicitly declares implementation:

```text
class Person implements Named {
    # Fields and operations.
}
```

The compiler checks operation names, operation kinds, and
argument counts. It does not check argument or return types.

Interfaces are compile-time contracts. They are not generated
as runtime classes, and implementation does not make
`$object->isa("Named")` true.

## Inheritance

A class may extend one parent:

```text
class Employee extends Person {
    field $title :param;

    fun title {
        return $title;
    }
}
```

Parents are emitted before children, regardless of declaration
order in the source.

Inherited operations may satisfy interfaces. Subclasses inherit
their parent's interface obligations. Overrides must preserve
operation kind and argument count.

Parent fields remain private to the parent class. Child operations
should use inherited operations rather than directly naming
parent fields.

The operation name `new` is reserved by the generator.

## Imports

An import names another Veyra module:

```text
import MyApp::Person;
```

The logical name maps to:

```text
MyApp/Person.veyra
```

beneath a configured source search directory.

Module compilation follows transitive imports. Imports do not
create short-name aliases.

For low-level module compilation, supply explicit search paths:

```sh
veyra-compile --module MyApp::Employee \
    -I src \
    -I vendor \
    --output build/Employee.pm
```

The output directory must already exist, and the output file
must not already exist.

Single-file compilation does not perform filesystem import
resolution.

## Use a Perl module from a class

Add this class as `src/App/User.veyra`:

```text
class App::User {
    use JSON::PP ();

    field $name :param;

    fun as_json {
        return JSON::PP::encode_json({name => $name});
    }
}
```

An entry module can `import App::User;`, create a user with
`App::User->new(name => "Alice")`, and call `$user->as_json()`.
The class loads `JSON::PP` itself, without importing function names.
Its runner does not need a separate JSON declaration.

Keep each class's Perl dependencies local. For non-core modules,
install them in the Perl environment used for both `veyra check`
and `veyra run`. The declaration does not install anything. For a
shared resource such as a DBI connection, open it at startup and
pass the handle to the classes that need it.

## Command-line exit status

### Project CLI

- `0`: successful command, help, or version reporting.
- `1`: project, validation, or filesystem failure.
- `2`: incorrect command usage.

There are two important qualifications:

- `veyra fmt --check` also returns `1` when formatting changes
  are needed.
- `veyra run` propagates the application's exit status. Signal
  termination is reported as `128 + signal number`.

### Low-level compiler

For `veyra-compile`:

- `0`: successful compilation or help.
- `1`: compilation or file-handling error.
- `2`: incorrect command usage.

Existing output files are never overwritten by this command.

## Current limitations and safety

Operation bodies support a restricted subset of Perl syntax.

The syntax guard rejects constructs including quote-like and
regular-expression operators, slash syntax, backticks, heredoc
syntax, nested sub declarations, and eval.

Generated operation bodies use an anonymous-subroutine wrapper
to implement return behavior. Caller inspection and similar
introspection are not promised to behave as if the body were
written directly inside a native method.

Static call checking is conservative. Dynamic or unresolved
argument lists are not assigned guessed argument counts.

Class::Veyra is not a sandbox. Do not compile, syntax-check,
load, or execute untrusted source as though it were isolated.

Formatting validates original and proposed sources and compares
generated non-whitespace token types and contents. This is a
safeguard against unintended edits, not a general proof of
semantic equivalence.

Project formatting stages changed files before replacing them,
but replacement is not a multi-file transaction.

Low-level file compilation is not atomic publication: another
process could observe an output file while it is being written.
