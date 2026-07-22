use strict;
use warnings;
use Test2::V0;

subtest 'skippy' => sub {
    skip_all('not applicable');
    ok 1, 'never runs';
};

subtest 'after' => sub {
    ok 1, 'after one';
};

done_testing;
