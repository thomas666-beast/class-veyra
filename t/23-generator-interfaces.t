use strict;
use warnings;

use Test::More;

use Class::Veyra::Compiler;

sub compile_error {
    my ($source) = @_;

    my $completed = eval {
        Class::Veyra::Compiler->compile($source);
        1;
    };

    my $error = $@;

    return $completed ? '' : $error;
}

my $source = <<'VEYRA';
interface VeyraGeneratedNamed {
    fun name;
    act rename ($new_name);
}

class VeyraGeneratedNamedBase {
    field $name :param;

    fun name {
        return $name;
    }

    act rename ($new_name) {
        $name = $new_name;
    }
}

class VeyraGeneratedNamedChild
    extends VeyraGeneratedNamedBase
    implements VeyraGeneratedNamed
{
}

class VeyraGeneratedNamedDirect implements VeyraGeneratedNamed {
    field $name :param;

    fun name {
        return $name;
    }

    act rename ($new_name) {
        $name = $new_name;
    }
}
VEYRA

my $generated =
    Class::Veyra::Compiler->compile($source);

like(
    $generated,
    qr/# interface VeyraGeneratedNamed:/,
    'records the interface as a comment',
);

unlike(
    $generated,
    qr/class VeyraGeneratedNamed \{/,
    'does not generate a class for the interface',
);

my $loaded = eval $generated;
my $load_error = $@;

ok(
    $loaded,
    'generated interface-bearing source compiles and loads',
) or diag $load_error;

unless ($loaded) {
    done_testing;
    exit;
}

my $direct = VeyraGeneratedNamedDirect->new(name => 'Alice');

is(
    $direct->name,
    'Alice',
    'direct implementer works',
);

ok(
    !$direct->isa('VeyraGeneratedNamed'),
    'interface is not a runtime parent class',
);

my $child = VeyraGeneratedNamedChild->new(name => 'Bob');

is(
    $child->name,
    'Bob',
    'inherited operation satisfies the interface',
);

$child->rename('Carol');

is(
    $child->name,
    'Carol',
    'inherited act works on the implementing child',
);

ok(
    !VeyraGeneratedNamed->can('new'),
    'no runtime package is created for the interface',
);

isnt(
    compile_error(
        'interface VeyraBadNamed { fun name; } '
        . 'class VeyraBadMissing implements VeyraBadNamed {}'
    ),
    '',
    'compile still rejects a missing implementation',
);

isnt(
    compile_error(
        'interface VeyraBadNamed { fun name; } '
        . 'class VeyraBadKind implements VeyraBadNamed '
        . '{ act name {} }'
    ),
    '',
    'compile still rejects an operation of the wrong kind',
);

done_testing;
