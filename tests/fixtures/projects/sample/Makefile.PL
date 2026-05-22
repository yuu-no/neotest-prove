use ExtUtils::MakeMaker;

WriteMakefile(
    NAME      => 'Sample',
    VERSION   => '0.001',
    TEST_REQUIRES => { 'Test::More' => 0 },
);
