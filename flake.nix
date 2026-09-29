{
  description = "Development tools for neotest-prove";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      forAllSystems = nixpkgs.lib.genAttrs [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
    in
    {
      # Tools only. Neovim and the test dependencies are deliberately left out:
      # CI tests against the Neovim release users run, and tests/minimal_init.lua
      # pins the plugins. The versions here are fixed by flake.lock.
      devShells = forAllSystems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        {
          default = pkgs.mkShellNoCC {
            packages = [
              pkgs.stylua
              pkgs.lua54Packages.luacheck
              # Recent enough that Test2::V0 is core, so the helper's Test2
              # fixtures run instead of skipping.
              pkgs.perl
            ];
          };
        }
      );

      formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.nixfmt);
    };
}
