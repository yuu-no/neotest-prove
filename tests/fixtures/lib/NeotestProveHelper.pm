package NeotestProveHelper;

# A test helper that makes its own assertions, so their failures are reported
# at a line in *this* file rather than in the test file that called them.

use strict;
use warnings;
use Test::More;
use Exporter 'import';

our @EXPORT = qw(check_thing);

sub check_thing {
    my ($got) = @_;
    is $got, 'expected', 'helper assertion';
}

1;
