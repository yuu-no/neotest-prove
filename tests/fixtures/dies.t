use strict;
use warnings;
use Test::More;

ok 1, 'before die';
die "boom\n";

done_testing;
