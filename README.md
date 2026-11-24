# Class::Veyra

A pure-Perl compiler for a small class language with explicit interfaces.

Class::Veyra parses and validates Veyra source, then generates ordinary
Perl using Perl's native class feature. Generated programs do not require
Class::Veyra at runtime.

## Quick start

With the distribution installed and `veyra` available on your `PATH`:

```sh
veyra create hello
cd hello
veyra run
```

The untouched starter program prints:

```text
Hello, world!
```

No separate build step or manual project configuration is required.

The usual project commands are:

```sh
veyra check
veyra fmt --check
veyra fmt
veyra build
veyra run
```

Pass application arguments after `--`:

```sh
veyra run -- Alice --verbose
```

The configured Perl runner receives those values in `@ARGV`.

### From a source checkout

Build and test the distribution first:

```sh
perl Makefile.PL
make
make test
```

To exercise the starter workflow without installing the distribution,
run these commands from the checkout root:

```sh
VEYRA_CHECKOUT="$(pwd)"

perl -I"$VEYRA_CHECKOUT/blib/lib" \
    "$VEYRA_CHECKOUT/script/veyra" create hello

cd hello

perl -I"$VEYRA_CHECKOUT/blib/lib" \
    "$VEYRA_CHECKOUT/script/veyra" run
```

This invokes the source-tree CLI explicitly. It does not verify that
an installed `veyra` command is discoverable on `PATH`.

## Status

Early development. The implemented language and tools support:

- Qualified class and interface names.
- Scalar instance fields, including constructor parameters.
- `fun` operations that return exactly one value.
- `act` operations that return no values.
- Required scalar operation parameters.
- Single inheritance and override validation.
- Explicit interfaces with operation-kind and arity checks.
- Multi-source project analysis and compilation.
- File-based imports through explicit source search directories.
- Static checks for supported class references and method calls.
- Static constructor-parameter checks for supported call forms.
- Project creation, checking, building, and execution.
- Forwarding application arguments through `veyra run --`.
- Conservative declaration formatting and formatting checks.
- Low-level command-line compilation without overwriting existing output.

The language is restricted; operation bodies are not an unrestricted
replacement for arbitrary Perl source.

Static call analysis is deliberately conservative. An unresolved call
or argument expression is not necessarily rejected, and successful
analysis is not proof that every runtime call will succeed.

## Requirements

- Perl 5.38 or newer for the compiler and generated programs.
- No non-core Perl dependencies.
- No XS or source filters.

The compiler targets Perl's native class feature, which is experimental
in Perl 5.38.

## Project commands

Project commands find `veyra.json` in the current directory or a parent
directory. Configured paths are resolved relative to that configuration
file, not the directory from which the command was invoked.

### Create a project

```sh
veyra create hello
```

The starter layout is:

```text
hello/
    .gitignore
    veyra.json
    run.pl
    src/
        App/
            Main.veyra
```

Creation refuses an existing destination. It does not create build
output.

### Check a project

```sh
veyra check
```

Checks the entry module and its transitive imports, including validation
of the generated Perl syntax. It does not write the configured build
output or execute the runner.

### Build a project

```sh
veyra build
```

Compiles the entry module and its transitive imports to the configured
output path.

The project builder creates the output directory when needed and
replaces an existing generated output file. Compilation and generated
Perl syntax validation finish before replacement, so those validation
failures leave the previous output unchanged.

This differs from the low-level `veyra-compile` command, which refuses
to overwrite an existing output file.

### Run a project

```sh
veyra run
```

Builds the project, then executes the configured Perl runner from the
project root.

A failed build prevents the runner from starting. The command does not
fall back to executing an older generated bundle.

Application arguments require an explicit separator:

```sh
veyra run -- Alice --verbose
```

Everything after the first separator is forwarded unchanged as runner
arguments. For example:

```sh
veyra run -- --help
```

passes `--help` to the application. In contrast:

```sh
veyra run --help
```

is a CLI usage error.

Both `veyra run` and `veyra run --` run the application without arguments.
The application exit code is returned by the CLI.

The runner decides how to use `@ARGV`; arguments are not automatically
passed to a Veyra operation.

### Format a project

```sh
veyra fmt
```

Formats the configured entry module and its transitive imports.

The formatter:

- Normalizes declaration spacing and structural indentation.
- Adjusts indentation on existing operation-body lines.
- Indents nested blocks, parentheses, and brackets.
- Preserves string contents, including multiline-string whitespace.
- Preserves comment text and order while adjusting comment indentation.
- Leaves inline operation bodies inline.
- Does not visit unrelated `.veyra` files outside the entry import graph.
- Refuses imported sources resolved outside the project root.
- Does not generate build output or execute the runner.

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

An unused external include directory is allowed. Importing a source
from outside the project root causes formatting to fail rather than
modifying that dependency.

Outside operation bodies, formatting normalizes structural line breaks
to LF. Within operation bodies, existing line endings are retained
while leading indentation is adjusted.

Before writing, the formatter analyzes both the original and proposed
sources. Their generated Perl must have matching token types and
contents after whitespace tokens are excluded. This comparison includes
string and comment contents; it is a safeguard, not a general proof of
semantic equivalence.

Changed files are staged before replacements begin. Replacements happen
one file at a time, not as a multi-file transaction: a filesystem error
during replacement may leave an earlier file formatted and a later file
unchanged.

The formatter preserves ordinary source permission bits. It does not
promise to preserve every filesystem attribute.

### Check formatting without writing

```sh
veyra fmt --check
```

Reports files that would change and prints a unified diff showing the
original and proposed lines. It does not replace source files.

For example:

```diff
Would format src/App/Main.veyra.
--- a/src/App/Main.veyra
+++ b/src/App/Main.veyra
@@ -1,5 +1,5 @@
 class App::Main {
-act message {
-say "Hello";
-}
+    act message {
+        say "Hello";
+    }
 }
```

Lines beginning with `-` show original contents. Lines beginning with
`+` show proposed contents. The formatter currently produces one hunk
per changed file, with surrounding context.

Exit status is:

- `0`: the collected sources are already formatted.
- `1`: formatting changes are needed, or formatting failed.
- `2`: invalid command-line usage.

Formatting differences and diffs are reported on standard output.
Errors are reported on standard error.

To apply the changes and then verify the result:

```sh
veyra fmt
veyra fmt --check
```

The second command should report:

```text
All source files are formatted.
```

and return status `0`.

### Project command exit codes

For `create`, `check`, `build`, and `fmt`:

- `0`: success.
- `1`: a project, validation, or filesystem error; also formatting
  differences for `fmt --check`.
- `2`: invalid command-line usage.

For `run`, CLI usage errors return `2`, and project or build failures
return `1`. Once the runner executes, its exit status is propagated.
A runner terminated by a signal is reported as `128 + signal number`.

## Project configuration

The generated `veyra.json` contains:

```json
{
  "entry": "App::Main",
  "include_paths": ["src"],
  "output": "build/Main.pm",
  "run": "run.pl"
}
```

The fields are:

- `entry`: the logical class or interface name used as the entry module.
- `include_paths`: a non-empty array of source search directories.
- `output`: the generated Perl bundle path.
- `run`: the Perl runner path, required by `veyra run`.

Search directories are tried in the configured order. Paths may be
relative to the project root or absolute.

The generated `run.pl` is ordinary Perl. If you customize the output
path or application entry behavior, update the runner accordingly.
Building a bundle does not rewrite the runner.

## Example language project

The following example demonstrates interfaces, constructor fields,
imports, and inheritance independently of the generated starter project.

Create these three source files.

### `src/MyApp/Contracts/Named.veyra`

```text
interface MyApp::Contracts::Named {
    fun name;
    act rename ($new_name);
}
```

### `src/MyApp/Person.veyra`

```text
import MyApp::Contracts::Named;

class MyApp::Person implements MyApp::Contracts::Named {
    field $name :param;

    fun name {
        return $name;
    }

    act rename ($new_name) {
        $name = $new_name;
    }

    fun description {
        return "person";
    }
}
```

### `src/MyApp/Employee.veyra`

```text
import MyApp::Person;

class MyApp::Employee extends MyApp::Person {
    fun description {
        return "employee";
    }
}
```

`Employee` inherits its constructor field and the `name` and `rename`
operations. Its `description` operation overrides the parent's operation.

Interfaces describe required operations. They do not become runtime
parent classes.

## Static call checking

The compiler checks supported calls when it can identify their targets
and determine the relevant arguments.

### Method arguments

For an explicitly signed operation:

```text
act rename ($new_name) {
    $name = $new_name;
}
```

a supported call with zero or two countable arguments is rejected.

An explicit empty signature declares zero parameters:

```text
act reset () {
}
```

The argument-count checker currently limits itself to explicit
signatures and supported parenthesized calls. It does not impose a count
on an operation whose Veyra declaration omits a signature.

That checker limitation does not define unrestricted runtime arity.
Generated Perl still determines runtime behavior.

Expressions whose argument-list size cannot be established are left
unresolved rather than assigned a guessed count.

### Constructor parameters

A parameter field declares a required named constructor argument:

```text
field $name :param;
```

For supported statically readable calls, the compiler checks:

- Unknown constructor parameter names.
- Missing required parameters.
- Required parameters inherited from parent classes.

Fields without `:param` are not constructor parameters.

The current field syntax does not support parameter defaults or
parameter-name aliases.

Parenthesized named argument lists are checked when their shape can be
determined. A bare constructor followed by a semicolon or the end of an
operation body is also checked as a zero-argument call.

Dynamic lists such as `new(%parameters)` and unresolved unparenthesized
argument lists are not assigned guessed parameter names or counts.

## Low-level command-line compilation

The `veyra-compile` command remains available independently of the
project CLI.

From a built source checkout:

```sh
mkdir -p build
perl -Mblib script/veyra-compile --module MyApp::Employee -I src --output build/Employee.pm
```

After installation, the equivalent command is:

```sh
veyra-compile --module MyApp::Employee -I src --output build/Employee.pm
```

Module mode follows transitive imports and validates the collected
project before generating output.

Repeat `-I` or `--include` to search multiple directories:

```sh
veyra-compile --module MyApp::Employee -I src -I vendor --output build/Employee.pm
```

Directories are searched in the order provided. The output directory
must already exist, and existing output files are never overwritten.

### Single-file mode

The original file-compilation mode remains available:

```sh
veyra-compile --output build/Single.pm Single.veyra
```

Single-file mode does not follow imports. Use module mode for
filesystem import resolution.

Put options before the positional input filename. Module mode takes
no positional input and requires at least one include directory.
Include options are not accepted in single-file mode.

Low-level CLI exit codes:

- `0`: successful compilation or help.
- `1`: compilation or filesystem failure.
- `2`: invalid command-line usage.

## Use the generated classes

Once the example language project is compiled:

```perl
use v5.38;
use strict;
use warnings;

require './build/Employee.pm';

my $employee = MyApp::Employee->new(name => 'Alice');

print $employee->name, "\n";
print $employee->description, "\n";

$employee->rename('Bob');

print $employee->name, "\n";
```

The generated bundle contains the collected classes in parent-first
order. It does not load the original `.veyra` files at runtime.

## Import rules

An import names a declaration and maps that name to a source file:

```text
import MyApp::Person;
```

With `src` as a search directory, this requests:

```text
src/MyApp/Person.veyra
```

The loaded file must declare `MyApp::Person` as a class or interface.
It may contain additional declarations.

Other rules:

- Qualified names must be contiguous: `MyApp::Person`, not
  `MyApp :: Person`.
- Imports are allowed between top-level declarations.
- Each import requires its own semicolon-terminated statement.
- Duplicate imports within one source are rejected.
- Each canonical source path is collected once per collection.
- Circular imports are allowed; circular inheritance is rejected.
- The logical entry module must also declare its requested name.
- Imports do not introduce short-name aliases. Use the declared names
  in `extends` and `implements`.
- Source lookup uses explicit include directories, not Perl's `@INC`.

A source file is not a filesystem sandbox: configured directories may
contain symlinks. The project formatter additionally checks whether
resolved source paths are inside the project root.

## Compiler API

```perl
use Class::Veyra::Compiler;

my $project = Class::Veyra::Compiler->analyze_module(
    'MyApp::Employee',
    include_paths => ['src', 'vendor'],
);

my $perl = Class::Veyra::Compiler->compile_module(
    'MyApp::Employee',
    include_paths => ['src', 'vendor'],
);
```

`analyze_module` collects imports and returns a validated project AST.

`compile_module` performs the same collection and validation, then
returns generated Perl as a string. It does not execute that Perl or
write an output file.

Other compiler entry points:

- `analyze($source, $source_name)` analyzes one supplied source string.
- `compile($source, $source_name)` compiles one supplied source string.
- `analyze_sources($sources)` analyzes supplied named source strings.
- `compile_sources($sources)` compiles supplied named source strings.
- `compile_file($input_path, $output_path)` compiles one input file
  without overwriting an existing output file.

The source name is optional for the single-string APIs and defaults
to `<string>`.

For the multi-source APIs, supply an array reference:

```perl
my $sources = [
    {
        source_name => 'example.veyra',
        source      => 'class Example {}',
    },
];

my $perl = Class::Veyra::Compiler->compile_sources($sources);
```

The string and supplied-source APIs do not perform filesystem import
resolution. Use the module APIs when imports should discover files.

To write a compiled module project directly to a new file:

```perl
use Class::Veyra::FileCompiler;

Class::Veyra::FileCompiler->compile_module_file(
    'MyApp::Employee',
    'build/Employee.pm',
    include_paths => ['src', 'vendor'],
);
```

## Formatter API

Format a supplied source string without writing files:

```perl
use Class::Veyra::Formatter;

my $formatted = Class::Veyra::Formatter->format(
    $source,
    'example.veyra',
);
```

The optional source name defaults to `<string>`.

The formatter parses both its input and output. It adjusts declaration
spacing and operation-body indentation while preserving non-whitespace
token types and contents, including strings and comments.

For project-level formatting:

```perl
use Class::Veyra::ProjectFormatter;

my $project = Class::Veyra::ProjectFormatter->load;

my $would_change = $project->format(
    check_only => 1,
);

my $changed = $project->format;
```

Both calls return an array reference of project-relative paths in sorted
order. Check mode does not write files.

## Native-Perl convenience import

`use Class::Veyra;` enables strictness, warnings, and Perl's native
class feature in the importing lexical scope. It also suppresses the
`experimental::class` warning in that scope.

It does not teach the Perl parser the Veyra `fun`, `act`, `interface`,
or source-level `import` syntax. Compile Veyra source through
`Class::Veyra::Compiler` or the CLI.

## Safety

Compiler validation is not a security boundary.

The compiler APIs parse, validate, and generate code without running
the application. Project commands additionally syntax-check generated
Perl, and `veyra run` deliberately executes the configured runner after
a successful build.

Do not treat generated Perl, Perl syntax checking, `eval`, or loading a
generated bundle as safe for untrusted source.

The formatter's project-root checks and generated-output comparison
are safeguards against unintended edits, not an isolation mechanism
for hostile projects.

## Build and test

```sh
perl Makefile.PL
make
make test
```

## Installation

After building and testing, install using the destinations configured
for your Perl and MakeMaker setup:

```sh
make install
```

The distribution declares both `veyra` and `veyra-compile` as executable
scripts. The installation's executable directory must be on `PATH`,
and its module directory must be visible to the Perl interpreter used
by those scripts.

Source-tree tests and an installed-command smoke test are separate
checks. To verify an installation, run the quick-start workflow from a
directory outside the source checkout.

## Distribution checks

After adding or removing distribution files, regenerate and review
`MANIFEST`:

```sh
make manifest
```

Check distribution contents and run the tests in a distribution copy:

```sh
make distcheck
make disttest
```
