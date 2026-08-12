use strict;
use warnings;
use Test::More;
use FindBin ();
use File::Temp ();
use Cwd ();
use File::Spec ();
use JSON::PP ();

my $helper   = "$FindBin::Bin/../neotest-prove-runner.pl";
my $fixtures = "$FindBin::Bin/../../tests/fixtures";

ok -f $helper, 'helper script exists';

# Test2::V0 comes from Test2::Suite, which only became core in perl 5.40 (the
# Test2 modules Test::Simple has bundled since 5.26 do not include it), so the
# Test2 fixtures cannot run everywhere. Probed in a subprocess: loading
# Test2::V0 into this Test::More process would change how it reports.
my $have_test2 = do {
    my $devnull = File::Spec->devnull;
    system("$^X -MTest2::V0 -e1 >$devnull 2>&1") == 0;
};

# Run the helper over the given fixtures and return the decoded JSON results.
sub run_helper {
    my (@test_files) = @_;
    my ( $fh, $json ) = File::Temp::tempfile( UNLINK => 1 );
    close $fh;
    my @cmd = (
        $^X, $helper, '--results', $json, '--',
        'prove', '--merge', '-Q',
        map { Cwd::abs_path("$fixtures/$_") } @test_files,
    );
    # Drain the helper's stdout so it does not corrupt this test's TAP.
    open my $pipe, '-|', @cmd or die "neotest-prove: cannot run helper: $!";
    {
        local $/;
        my $ignore = <$pipe>;
    }
    close $pipe;

    open my $rh, '<', $json or die "neotest-prove: cannot read results: $!";
    local $/;
    my $content = <$rh>;
    close $rh;
    return JSON::PP::decode_json($content);
}

# Find the single file entry whose path ends with the given basename.
sub file_entry {
    my ( $results, $basename ) = @_;
    for my $path ( keys %{ $results->{files} } ) {
        return $results->{files}{$path} if $path =~ /\Q$basename\E$/;
    }
    return undef;
}

subtest 'passing file' => sub {
    my $file = file_entry( run_helper('pass.t'), 'pass.t' );
    is $file->{status}, 'passed', 'pass.t is passed';
    is scalar @{ $file->{errors} }, 0, 'no errors';
};

# One prove run shared by the two failing-file subtests below.
my $fail_results = run_helper( 'fail.t', 'fail_unnamed.t' );

subtest 'failing file records an error with a line number' => sub {
    my $file = file_entry( $fail_results, 'fail.t' );
    is $file->{status}, 'failed', 'fail.t is failed';
    ok scalar @{ $file->{errors} } >= 1, 'has at least one error';
    like $file->{errors}[0]{message}, qr/Failed test/, 'error message mentions the failure';
    ok $file->{errors}[0]{line} > 0, 'error carries a line number';
    like $file->{errors}[0]{message}, qr/got: '2'/,      'message carries the got value';
    like $file->{errors}[0]{message}, qr/expected: '3'/, 'message carries the expected value';
    unlike $file->{errors}[0]{message}, qr/Looks like/, 'harness chatter is not included';
};

subtest 'failing assertion with no description still records a line number' => sub {
    my $file = file_entry( $fail_results, 'fail_unnamed.t' );
    is $file->{status}, 'failed', 'fail_unnamed.t is failed';
    ok scalar @{ $file->{errors} } >= 1, 'has at least one error';
    ok $file->{errors}[0]{line} > 0, 'error carries a line number';
    like $file->{errors}[0]{message}, qr/got: '2'/,      'message carries the got value';
    like $file->{errors}[0]{message}, qr/expected: '3'/, 'message carries the expected value';
};

subtest 'subtest results' => sub {
    my $file = file_entry( run_helper('subtests.t'), 'subtests.t' );
    is $file->{status}, 'failed', 'file with a failing subtest is failed';
    is $file->{subtests}{alpha}{status}, 'passed', 'alpha subtest passed';
    is $file->{subtests}{beta}{status},  'failed', 'beta subtest failed';
    ok scalar @{ $file->{subtests}{beta}{errors} } >= 1, 'beta subtest has an error';
    like $file->{subtests}{beta}{errors}[0]{message}, qr/got: 'x'/,
      'subtest error carries the got value';
    like $file->{subtests}{beta}{errors}[0]{message}, qr/expected: 'y'/,
      'subtest error carries the expected value';
};

subtest 'nested subtest results' => sub {
    my $file = file_entry( run_helper('nested_subtest.t'), 'nested_subtest.t' );
    is $file->{subtests}{outer}{status}, 'passed', 'outer subtest passed';
    is $file->{subtests}{'outer::inner'}{status}, 'passed', 'nested inner subtest passed';
};

subtest 'Test2::V0 brace-style subtest results' => sub {
    plan skip_all => 'Test2::V0 is not installed' unless $have_test2;
    my $file = file_entry( run_helper('test2_subtests.t'), 'test2_subtests.t' );
    is $file->{status}, 'failed', 'file with a failing subtest is failed';
    is $file->{subtests}{alpha}{status}, 'passed', 'alpha subtest passed';
    is $file->{subtests}{beta}{status},  'failed', 'beta subtest failed';
    ok scalar @{ $file->{subtests}{beta}{errors} } >= 1, 'beta subtest has an error';
    is $file->{subtests}{outer}{status}, 'passed', 'outer subtest passed';
    is $file->{subtests}{'outer::inner'}{status}, 'passed', 'nested inner subtest passed';
};

subtest 'Test2::V0 skip_all inside a subtest is reported as skipped' => sub {
    plan skip_all => 'Test2::V0 is not installed' unless $have_test2;
    my $file = file_entry( run_helper('test2_subtest_skip.t'), 'test2_subtest_skip.t' );
    is $file->{subtests}{skippy}{status}, 'skipped', 'skippy subtest is skipped';
    is $file->{subtests}{after}{status},  'passed',  'after subtest passed';
};

subtest 'an assertion description ending in a literal brace does not open a phantom subtest' => sub {
    plan skip_all => 'Test2::V0 is not installed' unless $have_test2;
    my $file =
      file_entry( run_helper('test2_subtest_brace_desc.t'), 'test2_subtest_brace_desc.t' );
    is $file->{subtests}{real_subtest}{status}, 'passed',
      'real_subtest is reported under its own name, not prefixed by the assertion';
    is scalar( keys %{ $file->{subtests} } ), 1, 'no phantom subtest was recorded';
};

subtest 'a subtest whose name contains a "#" is recorded under that name' => sub {
    my $file = file_entry( run_helper('hash_subtest.t'), 'hash_subtest.t' );
    is_deeply [ sort keys %{ $file->{subtests} } ], [ 'after', 'has # hash' ],
      'both subtests are recorded, and the "#" one does not swallow the next';
    is $file->{subtests}{'has # hash'}{status}, 'passed', 'the "#" subtest passed';
};

subtest 'a failure reported in another file carries no line number' => sub {
    my $file = file_entry( run_helper('helper_failure.t'), 'helper_failure.t' );
    my $err = $file->{subtests}{'uses helper'}{errors}[0];
    is $err->{line}, undef, 'a failure located in the helper module is not anchored to a line';
    like $err->{message}, qr/NeotestProveHelper\.pm line \d+/,
      'the foreign location is kept in the message';
    like $err->{message}, qr/got: 'nope'/, 'the diagnostic is still folded in';
    ok $file->{errors}[0]{line} > 0,
      'the subtest failure reported in the test file itself keeps its line';
};

subtest 'a test that dies before its plan is failed' => sub {
    my $file = file_entry( run_helper('dies.t'), 'dies.t' );
    is $file->{status}, 'failed', 'dies.t is failed';
};

subtest 'helper emits valid JSON' => sub {
    my $results = run_helper('subtests.t');
    is ref($results),          'HASH', 'top level is an object';
    is ref( $results->{files} ), 'HASH', 'files is an object';
};

done_testing;
