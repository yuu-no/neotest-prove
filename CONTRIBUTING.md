# Contributing

Thanks for taking the time to contribute. This document explains how the
project is laid out, how to run its tests, and the constraints a change has
to respect.

## Layout

| Path | What it is |
| --- | --- |
| `lua/neotest-prove/init.lua` | The neotest adapter: discovery, `build_spec`, `results`. |
| `lua/neotest-prove/query.lua` | Tree-sitter (perl) query that finds `subtest` calls. |
| `lua/neotest-prove/config.lua` | Defaults, validation, and option merging. |
| `lua/neotest-prove/health.lua` | `:checkhealth neotest-prove`. |
| `perl/neotest-prove-runner.pl` | Bundled helper that runs `prove` and turns its TAP into JSON. |
| `perl/t/` | Tests for the helper (run with `prove`). |
| `tests/` | Lua test suite (plenary busted) and its fixtures. |
| `doc/neotest-prove.txt` | Vim help. Keep it in sync with `README.md`. |

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
file); the Lua side converts it to 0-indexed. If you change the shape, update
`encode_*` in the helper and `adapter.results` in `init.lua` together.

## Running the tests

```bash
# Lua test suite. Bootstraps neotest, nvim-nio, plenary and nvim-treesitter
# into .tests/ on first run.
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
  5.10.1. No CPAN dependencies; that is why JSON is hand-encoded.
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
