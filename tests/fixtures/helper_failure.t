use strict;
use warnings;
use Test::More;
use FindBin ();
use lib "$FindBin::Bin/lib";
use NeotestProveHelper;

subtest 'uses helper' => sub {
    check_thing('nope');
};

done_testing;
