use strict;
use warnings;
use Test::More;

subtest outer_bareword => sub {
    subtest 'inner' => sub {
        ok 1, 'inner one';
    };
};

subtest(
    paren_bareword => sub {
        ok 1, 'paren one';
    }
);

done_testing;
