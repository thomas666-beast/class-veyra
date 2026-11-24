use strict;
use warnings;

use Test::More;

use Class::Veyra::Compiler;

sub analyze_error {
    my ($sources) = @_;

    my $completed = eval {
        Class::Veyra::Compiler->analyze_sources($sources);
        1;
    };

    my $error = $@;

    return $completed ? '' : $error;
}

my $child_source = <<'VEYRA';
class ProjectEmployee extends ProjectPerson implements ProjectNamed {
}
VEYRA

my $parent_source = <<'VEYRA';
interface ProjectNamed {
    fun name;
}

class ProjectPerson {
    field $name :param;

    fun name {
        return $name;
    }
}
VEYRA

my $sources = [
    {
        source_name => 'src/Employee.veyra',
        source      => $child_source,
    },
    {
        source_name => 'src/Person.veyra',
        source      => $parent_source,
    },
];

my $project =
    Class::Veyra::Compiler->analyze_sources($sources);

is(
    $project->{kind},
    'document',
    'project uses the existing document shape',
);

is(
    scalar @{ $project->{sources} },
    2,
    'retains both source documents',
);

is_deeply(
    [map { $_->{source_name} } @{ $project->{sources} }],
    ['src/Employee.veyra', 'src/Person.veyra'],
    'preserves source input order',
);

is_deeply(
    [map { $_->{name} } @{ $project->{declarations} }],
    ['ProjectEmployee', 'ProjectNamed', 'ProjectPerson'],
    'preserves declaration input order',
);

is(
    $project->{classes}[0]{source_name},
    'src/Employee.veyra',
    'child retains its original source name',
);

is(
    $project->{interfaces}[0]{source_name},
    'src/Person.veyra',
    'interface retains its original source name',
);

is(
    $project->{classes}[1]{offset},
    index($parent_source, 'class ProjectPerson'),
    'offset remains local to its source file',
);

my $generated =
    Class::Veyra::Compiler->compile_sources($sources);

like(
    $generated,
    qr/class ProjectEmployee :isa\(ProjectPerson\)/,
    'compiles cross-file inheritance and interface implementation',
);

my $parent_position =
    index $generated, 'class ProjectPerson {';

my $child_position =
    index $generated, 'class ProjectEmployee :isa(';

ok(
    $parent_position >= 0
        && $child_position > $parent_position,
    'emits parent before child across source boundaries',
);

like(
    analyze_error([
        {
            source_name => 'first.veyra',
            source      => 'class DuplicateProjectName {}',
        },
        {
            source_name => 'second.veyra',
            source      => 'class DuplicateProjectName {}',
        },
    ]),
    qr/Duplicate declaration 'DuplicateProjectName'.*first\.veyra.*second\.veyra/,
    'duplicate declaration error identifies both files',
);

like(
    analyze_error([
        {
            source_name => 'interface.veyra',
            source      => 'interface SharedProjectName {}',
        },
        {
            source_name => 'class.veyra',
            source      => 'class SharedProjectName {}',
        },
    ]),
    qr/Duplicate declaration 'SharedProjectName'/,
    'rejects class and interface name collisions across files',
);

like(
    analyze_error([
        { source_name => 'same.veyra', source => '' },
        { source_name => 'same.veyra', source => '' },
    ]),
    qr/Duplicate source name/,
    'rejects duplicate source names',
);

like(
    analyze_error([{ source => '' }]),
    qr/requires a non-empty source_name/,
    'requires explicit source names',
);

like(
    analyze_error([
        { source_name => 'bad.veyra', source => undef },
    ]),
    qr/requires a defined source string/,
    'validates source contents',
);

like(
    analyze_error({}),
    qr/sources must be an array reference/,
    'requires an array of sources',
);

like(
    analyze_error(['not a source entry']),
    qr/must be a hash reference/,
    'validates each source entry',
);

isnt(
    analyze_error([
        {
            source_name => 'unknown-parent.veyra',
            source =>
                'class ProjectOrphan extends MissingProjectParent {}',
        },
    ]),
    '',
    'still rejects unknown parents',
);

isnt(
    analyze_error([
        {
            source_name => 'contract.veyra',
            source => 'interface ProjectRequired { fun value; }',
        },
        {
            source_name => 'implementation.veyra',
            source =>
                'class ProjectIncomplete implements ProjectRequired {}',
        },
    ]),
    '',
    'still rejects unsatisfied cross-file interfaces',
);

isnt(
    analyze_error([
        {
            source_name => 'bad-return.veyra',
            source => 'class ProjectBadReturn { fun value {} }',
        },
    ]),
    '',
    'still enforces operation return contracts',
);

my $empty =
    Class::Veyra::Compiler->analyze_sources([]);

is_deeply(
    $empty->{declarations},
    [],
    'accepts an empty source collection',
);

done_testing;
