use strict;
use warnings;
use Test::More;
use FindBin ();
use File::Temp ();
use Cwd ();
use JSON::PP ();

my $helper   = "$FindBin::Bin/../neotest-prove-runner.pl";
my $fixtures = "$FindBin::Bin/../../tests/fixtures";

ok -f $helper, 'helper script exists';

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

subtest 'failing file records an error with a line number' => sub {
    my $file = file_entry( run_helper('fail.t'), 'fail.t' );
    is $file->{status}, 'failed', 'fail.t is failed';
    ok scalar @{ $file->{errors} } >= 1, 'has at least one error';
    like $file->{errors}[0]{message}, qr/Failed test/, 'error message mentions the failure';
    ok $file->{errors}[0]{line} > 0, 'error carries a line number';
};

subtest 'subtest results' => sub {
    my $file = file_entry( run_helper('subtests.t'), 'subtests.t' );
    is $file->{status}, 'failed', 'file with a failing subtest is failed';
    is $file->{subtests}{alpha}{status}, 'passed', 'alpha subtest passed';
    is $file->{subtests}{beta}{status},  'failed', 'beta subtest failed';
    ok scalar @{ $file->{subtests}{beta}{errors} } >= 1, 'beta subtest has an error';
};

subtest 'nested subtest results' => sub {
    my $file = file_entry( run_helper('nested_subtest.t'), 'nested_subtest.t' );
    is $file->{subtests}{outer}{status}, 'passed', 'outer subtest passed';
    is $file->{subtests}{'outer::inner'}{status}, 'passed', 'nested inner subtest passed';
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
