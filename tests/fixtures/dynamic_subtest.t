use strict;
use warnings;
use Test::More;

my $name = 'generated at runtime';
subtest $name => sub {
    ok 1, 'dynamic one';
};

subtest "interpolated: $name" => sub {
    ok 1, 'interpolated one';
};

subtest 'static one' => sub {
    ok 1, 'static one test';
};

subtest "double quoted" => sub {
    ok 1, 'double quoted test';
};

done_testing;
