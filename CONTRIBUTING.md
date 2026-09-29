# Contributing

Thanks for taking the time to contribute. This document explains how the
project is laid out, how to run its tests, and the constraints a change has
to respect.

## Layout

| Path | What it is |
| --- | --- |
| `lua/neotest-prove/init.lua` | The neotest adapter: discovery, `build_spec`, `results`. |
| `lua/neotest-prove/query.lua` | Tree-sitter (perl) query that finds `subtest` calls. |
| `lua/neotest-prove/config.lua` | Option definitions (defaults and accepted types), validation, and merging. |
| `lua/neotest-prove/health.lua` | `:checkhealth neotest-prove`. |
| `lua/neotest-prove/helper.lua` | Locates the bundled Perl helper relative to the plugin. |
| `perl/neotest-prove-runner.pl` | Bundled helper that runs `prove` and turns its TAP into JSON. |
| `perl/t/` | Tests for the helper (run with `prove`). |
| `tests/` | Lua test suite (plenary busted), shared spec helpers (`tests/helpers.lua`), and fixtures. |
| `doc/neotest-prove.txt` | Vim help. Keep it in sync with `README.md`. |
| `flake.nix`, `flake.lock` | Nix devShell pinning the development tools (stylua, luacheck, perl). |

The adapter is split across Lua and Perl. The seam is a JSON document the
helper writes to the path given by `--results`:

```json
{
  "files": {
    "/abs/path/t/foo.t": {
      "status": "passed | failed | skipped",
      "errors": [ { "message": "...", "line": 12 } ],
      "subtests": {
        "outer": { "status": "...", "errors": [] },
        "outer::inner": { "status": "...", "errors": [] }
      }
    }
  }
}
```

Nested subtest keys are `::`-joined; the adapter maps them to neotest
position IDs of the form `<file>::<outer>::<inner>`. Error `line` is
1-indexed in the JSON (or `null` when the failure was reported in another
file); the Lua side converts it to 0-indexed. The helper builds this document
as a plain Perl data structure and hands it to `JSON::PP` in `json_out`, so
changing the shape means changing that structure and `adapter.results` in
`init.lua` together.

## Development tools

`flake.nix` provides a devShell with stylua, luacheck and a perl recent
enough to have Test2::V0 in core. Their versions are pinned by `flake.lock`:

```bash
nix develop            # or `use flake` in an .envrc, with direnv
./scripts/style --check
```

Nix is optional: the scripts only need the tools on `PATH`. Without it,
formatting may differ from CI if your stylua is a different release. Neovim is
not in the shell; the Lua suite runs against whichever `nvim` you have, as CI
runs against the current stable release. Update the pinned tools with
`nix flake update`, as a change of its own.

## Running the tests

```bash
# Lua test suite. Bootstraps neotest, nvim-nio, plenary and nvim-treesitter
# into .tests/, at the revisions pinned in tests/minimal_init.lua.
./scripts/test

# A single spec file.
./scripts/test tests/adapter_spec.lua

# Perl helper tests.
prove -v perl/t
```

Notes:

- The discovery specs need the `perl` tree-sitter parser. They mark
  themselves pending when it is missing; CI installs it.
- The Test2::V0 fixtures need Test2::Suite, which only became core in Perl
  5.40. The helper tests skip them when it is not installed.
- `scripts/test` post-processes plenary's output because plenary does not
  exit non-zero on setup errors. Don't replace it with a bare `nvim` call.
- **Test dependencies are pinned.** The `deps` table in
  `tests/minimal_init.lua` holds a `rev` per dependency, and the bootstrap
  checks out exactly that revision — including over an existing `.tests/`
  whose checkout has drifted. CI uses the same bootstrap rather than cloning
  its own copies, so a green CI run and your working copy mean the same
  thing. Nothing updates the revisions automatically; to move one, edit its
  `rev`, run the suite, and commit that as its own change:

  ```bash
  # Latest upstream revision of a dependency.
  git ls-remote https://github.com/nvim-neotest/neotest HEAD
  ```

  The flip side is that upstream breakage is not noticed until someone bumps
  a revision. That is the intended trade-off: a red CI run should mean this
  repository changed, not that a dependency moved overnight.

## Style

- Lua is formatted with [stylua](https://github.com/JohnnyMorganz/StyLua)
  using the settings in `stylua.toml`. Run `./scripts/style`; CI runs
  `stylua --check lua tests`.
- The Perl helper uses 4-space indentation and the aligned, perltidy-like
  layout of the existing code. Match it; there is no enforced formatter.
- Commit messages follow the
  [Conventional Commits](https://www.conventionalcommits.org/) style seen in
  the history (`feat:`, `fix:`, `test:`, `docs:`, `ci:`).

## Constraints

- **The Perl helper uses core modules only** and must keep working on Perl
  5.14. No CPAN dependencies. The floor is derived, not chosen: `TAP::Parser`
  entered core in 5.10.1 and `JSON::PP` in 5.14, and those are the newest
  modules the helper loads. Don't raise it without a module that needs it.
  CI runs `perl/t` against the floor in a `perl:5.14` container, so a newer
  feature slipping in is caught there.
- **Subtests are matched statically.** The tree-sitter query only emits
  subtests whose name is a literal string or bareword. Don't extend it to
  computed names without a plan for what neotest should do with positions
  that cannot be mapped back to a result.
- **`prove` runs whole files.** Don't add code that pretends a single subtest
  can be run in isolation.
- The helper's `--results <path> -- <prove-cmd> [args...]` argument shape is
  part of the contract with `build_spec`; the `--` separator is required.

## Sending a change

1. Add or update a test that fails before the change and passes after it.
   Helper behaviour goes in `perl/t/runner.t` with a fixture under
   `tests/fixtures/`; adapter behaviour goes in `tests/*_spec.lua`.
2. Run both test suites and `./scripts/style`.
3. Update `README.md`, `doc/neotest-prove.txt`, and `CHANGELOG.md` when
   user-visible behaviour changes.
4. Open a pull request describing what changed and why.
