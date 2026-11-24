use strict;
use warnings;

use Test::More;

use Class::Veyra::Parser;
use Class::Veyra::SyntaxGuard;

sub body_error {
    my ($source) = @_;

    my $completed = eval {
        Class::Veyra::SyntaxGuard->check_body($source);
        1;
    };

    my $error = $@;

    return $completed ? '' : $error;
}

my @supported = (
    [
        'return $name;',
        'simple return',
    ],
    [
        '$value = $left + $right;',
        'arithmetic without division',
    ],
    [
        'return { name => $name };',
        'hash reference',
    ],
    [
        'return "q{example} / << ` sub eval";',
        'unsupported-looking text inside a string',
    ],
    [
        "# q{example} / << ` sub eval\nreturn 1;",
        'unsupported-looking text inside a comment',
    ],
    [
        'my $q = 1; my $s = 2; return $q + $s;',
        'simple variables whose names match reserved words',
    ],
);

for my $case (@supported) {
    is(
        body_error($case->[0]),
        '',
        "allows $case->[1]",
    );
}

my @unsupported = (
    ['return q{text};',      qr/Unsupported word 'q'/],
    ['return qq{text};',     qr/Unsupported word 'qq'/],
    ['return qw(a b);',      qr/Unsupported word 'qw'/],
    ['return qx{command};',  qr/Unsupported word 'qx'/],
    ['return qr{text};',     qr/Unsupported word 'qr'/],
    ['$x =~ m{text};',       qr/Unsupported word 'm'/],
    ['$x =~ s{a}{b};',       qr/Unsupported word 's'/],
    ['$x =~ tr{a}{b};',      qr/Unsupported word 'tr'/],
    ['$x =~ y{a}{b};',       qr/Unsupported word 'y'/],
    ['return /text/;',       qr/Unsupported symbol '\/'/],
    ['return $x / 2;',       qr/Unsupported symbol '\/'/],
    ['return `command`;',    qr/Unsupported symbol '`'/],
    ['return <<TEXT;',       qr/Unsupported '<<'/],
    ['return $x << 2;',      qr/Unsupported '<<'/],
    ['my $cb = sub {};',     qr/Unsupported word 'sub'/],
    ['eval "1 + 1";',        qr/Unsupported word 'eval'/],
    ['format REPORT =',     qr/Unsupported word 'format'/],
    ['__DATA__',             qr/Unsupported word '__DATA__'/],
    ['__END__',              qr/Unsupported word '__END__'/],
    ["=pod\ntext\n=cut\n",   qr/Unsupported POD-style directive/],
);

for my $case (@unsupported) {
    like(
        body_error($case->[0]),
        $case->[1],
        "rejects: $case->[0]",
    );
}

my $document = Class::Veyra::Parser->parse(<<'VEYRA');
class Person {
    field $name :param;

    fun name {
        return $name;
    }
}
VEYRA

is(
    Class::Veyra::SyntaxGuard->validate($document),
    1,
    'validates supported operation bodies in a document',
);

my $bad_document = Class::Veyra::Parser->parse(<<'VEYRA');
class Calculator {
    fun half ($value) {
        return $value / 2;
    }
}
VEYRA

my $completed = eval {
    Class::Veyra::SyntaxGuard->validate($bad_document);
    1;
};

my $error = $@;

ok(
    !$completed,
    'document validation rejects an unsupported body',
);

like(
    $error,
    qr/\AClass 'Calculator', fun 'half': Unsupported symbol/,
    'error identifies the class and operation',
);

done_testing;
