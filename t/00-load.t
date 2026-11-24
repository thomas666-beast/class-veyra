use strict;
use warnings;

use Test::More tests => 2;

BEGIN {
    use_ok('Class::Veyra');
}

is(
    $Class::Veyra::VERSION,
    '0.001',
    'development version is defined',
);
