use Module::Build;

Module::Build->new(
    module_name => 'Sample',
    dist_version => '0.001',
)->create_build_script;
