# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A [neotest](https://github.com/nvim-neotest/neotest) adapter for Perl's `prove` (Test::Harness). It discovers `.t` files and `subtest` blocks via tree-sitter, runs them through a bundled Perl helper that captures raw TAP, and reports per-file / per-subtest results back to neotest.

## Architecture

The adapter is intentionally split across two languages, and the seam between them is the key thing to understand before changing anything:

- **Lua side (`lua/neotest-prove/`)** — implements the neotest adapter interface. `init.lua` builds the run spec; `query.lua` is the tree-sitter (perl) query that finds `subtest` calls with a literal-string name; `config.lua` merges user options over defaults.
- **Perl side (`perl/neotest-prove-runner.pl`)** — invoked by `adapter.build_spec`. It runs the user's real `prove` binary with `PERL_TEST_HARNESS_DUMP_TAP` set so Test::Harness dumps raw per-file TAP into a temp dir. The helper then walks that dir, parses each file with `TAP::Parser`, and writes a JSON blob to `--results <path>`. `adapter.results` decodes that JSON and maps it back onto positions.
- **JSON contract** — `{ "files": { "<abs path>": { "status", "errors", "subtests": { "<name or outer::inner>": { "status", "errors" } } } } }`. Subtest keys for nested subtests are `::`-joined; the adapter maps them to neotest position IDs of the form `<file>::<subtest>`. Error `line` is 1-indexed in the JSON; the Lua side converts to 0-indexed for neotest.
- **Helper JSON is hand-encoded** so the helper stays on Perl 5.10.1 core only (no CPAN). If you change the helper output shape, update `encode_*` in the helper AND `adapter.results` together.

### Subtest discovery has a sharp edge

The tree-sitter query in `query.lua` only matches subtests whose first argument is a string literal (`subtest "name" => sub { ... }` or `subtest("name", sub { ... })`). Subtests with a computed name (e.g. `subtest $name => sub { ... }`) are deliberately not emitted as positions — their results fold into the file result. The TAP parser in the helper, however, still records them. Subtests nest by 4-space indentation and open/close in one of two forms depending on the test framework: Test::More opens with a `# Subtest: NAME` comment and closes with a same-indent `ok N - NAME` line; Test2::V0 opens with a same-indent `(not )?ok N - NAME {` line (status already known at open time, since Test2 buffers subtest output) and closes with a same-indent, bare `}` line (no name repeated). Don't try to "fix" the query to match dynamic names without also reconciling what neotest would do with positions it can't map back.

### Subtests cannot be run in isolation

`prove` only runs whole files. Running a single subtest from neotest still runs the whole file; the subtest-level result is purely a mapping from the file's TAP. Don't add code that pretends otherwise.

## Common commands

```bash
# Run the full Lua test suite (bootstraps deps into .tests/ on first run).
./scripts/test

# Run a single Lua spec file.
./scripts/test tests/adapter_spec.lua

# Run the Perl helper's own tests.
prove -v perl/t

# Format Lua sources (matches CI's `stylua --check lua tests`).
./scripts/style
```

Notes:

- `scripts/test` post-processes plenary's output because plenary does not exit non-zero on setup errors — don't replace it with a bare `nvim --headless ... PlenaryBustedDirectory` call.
- The Lua test suite needs the `perl` tree-sitter parser for the discovery tests. `has_perl_parser()` in `tests/adapter_spec.lua` skips those when the parser is missing; CI installs it explicitly.
- `.tests/` and `.tmp/` are gitignored caches; don't commit them.

## Conventions

- **stylua** (`stylua.toml`): 2-space indent, 100-col width, `AutoPreferDouble` quotes. CI fails on `stylua --check lua tests`.
- **Perl helper stays on core modules only** (Perl 5.10.1+). No CPAN deps — that's why JSON is hand-rolled in `encode_*` / `json_str`.
- The helper's `--results <path> -- <prove-cmd> [args...]` argument shape is part of the contract with `adapter.build_spec`; the `--` separator is required.
