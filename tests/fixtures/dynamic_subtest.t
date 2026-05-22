use strict;
use warnings;
use Test::More;

my $name = 'generated at runtime';
subtest $name => sub {
    ok 1, 'dynamic one';
};

subtest 'static one' => sub {
    ok 1, 'static one test';
};

done_testing;
