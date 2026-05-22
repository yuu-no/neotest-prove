use strict;
use warnings;
use Test::More;

subtest 'outer' => sub {
    ok 1, 'outer one';

    subtest 'inner' => sub {
        ok 1, 'inner one';
    };
};

done_testing;
