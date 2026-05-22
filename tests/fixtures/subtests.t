use strict;
use warnings;
use Test::More;

subtest('alpha', sub {
    ok 1, 'alpha one';
    ok 1, 'alpha two';
});

subtest 'beta' => sub {
    ok 1, 'beta one';
    is 'x', 'y', 'beta two fails';
};

done_testing;
