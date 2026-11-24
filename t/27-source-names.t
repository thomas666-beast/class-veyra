use strict;
use warnings;

use Test::More;

use Class::Veyra::Parser;
use Class::Veyra::Compiler;

sub error_from {
    my ($callback) = @_;

    my $completed = eval {
        $callback->();
        1;
    };

    my $error = $@;

    return $completed ? '' : $error;
}

my $source = <<'VEYRA';
interface SourceNamed {
    fun name;
}

class SourcePerson implements SourceNamed {
    fun name {
        return "Alice";
    }
}
VEYRA

my $anonymous =
    Class::Veyra::Parser->parse($source);

is(
    $anonymous->{source_name},
    '<string>',
    'document defaults to an anonymous source name',
);

is(
    $anonymous->{classes}[0]{source_name},
    '<string>',
    'class defaults to an anonymous source name',
);

is(
    $anonymous->{interfaces}[0]{source_name},
    '<string>',
    'interface defaults to an anonymous source name',
);

my $source_name = 'src/source-person.veyra';

my $named = Class::Veyra::Parser->parse(
    $source,
    $source_name,
);

is(
    $named->{source_name},
    $source_name,
    'parser preserves document source name',
);

is(
    $named->{classes}[0]{source_name},
    $source_name,
    'parser preserves class source name',
);

is(
    $named->{interfaces}[0]{source_name},
    $source_name,
    'parser preserves interface source name',
);

is(
    $named->{declarations}[0]{source_name},
    $source_name,
    'ordered declarations retain source metadata',
);

is(
    $named->{classes}[0]{offset},
    index($source, 'class SourcePerson'),
    'class offset remains relative to the original source',
);

is(
    $named->{interfaces}[0]{offset},
    index($source, 'interface SourceNamed'),
    'interface offset remains relative to the original source',
);

my $analyzed = Class::Veyra::Compiler->analyze(
    $source,
    $source_name,
);

is(
    $analyzed->{source_name},
    $source_name,
    'compiler analyze forwards the source name',
);

is(
    $analyzed->{classes}[0]{source_name},
    $source_name,
    'validation preserves declaration source metadata',
);

is(
    Class::Veyra::Compiler->compile($source, $source_name),
    Class::Veyra::Compiler->compile($source),
    'source metadata does not change generated Perl',
);

like(
    error_from(sub {
        Class::Veyra::Parser->parse($source, '');
    }),
    qr/source name must be a non-empty string/,
    'rejects an empty source name',
);

like(
    error_from(sub {
        Class::Veyra::Parser->parse($source, []);
    }),
    qr/source name must be a non-empty string/,
    'rejects a reference as source name',
);

my $empty = Class::Veyra::Parser->parse(
    '',
    'empty.veyra',
);

is(
    $empty->{source_name},
    'empty.veyra',
    'empty documents also preserve their source name',
);

done_testing;
