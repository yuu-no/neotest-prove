use strict;
use warnings;
use Test2::V0;

subtest 'alpha' => sub {
    ok 1, 'alpha one';
    ok 1, 'alpha two';
};

subtest 'beta' => sub {
    ok 1, 'beta one';
    is 'x', 'y', 'beta two fails';
};

subtest 'outer' => sub {
    ok 1, 'outer one';

    subtest 'inner' => sub {
        ok 1, 'inner one';
    };
};

done_testing;
