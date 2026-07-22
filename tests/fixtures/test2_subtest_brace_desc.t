use strict;
use warnings;
use Test2::V0;

ok 1, 'assertion ending in a literal brace {';

subtest 'real_subtest' => sub {
    ok 1, 'inner one';
};

done_testing;
