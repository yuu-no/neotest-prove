# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A [neotest](https://github.com/nvim-neotest/neotest) adapter for Perl's `prove` (Test::Harness). It discovers `.t` files and `subtest` blocks via tree-sitter, runs them through a bundled Perl helper that captures raw TAP, and reports per-file / per-subtest results back to neotest.

## Architecture

The adapter is intentionally split across two languages, and the seam between them is the key thing to understand before changing anything:

- **Lua side (`lua/neotest-prove/`)** — implements the neotest adapter interface. `init.lua` builds the run spec; `query.lua` is the tree-sitter (perl) query that finds `subtest` calls with a literal-string or bareword name; `config.lua` holds every option's default and accepted types in one `OPTIONS` table and validates/merges user options over the defaults (unknown keys, wrong types, non-string list elements, and empty command options raise); `health.lua` backs `:checkhealth neotest-prove` and reads each registered adapter's resolved options from `adapter.config`; `helper.lua` resolves the bundled Perl helper's path relative to the plugin, for both `init.lua` and `health.lua`.
- **Perl side (`perl/neotest-prove-runner.pl`)** — invoked by `adapter.build_spec`. It runs the user's real `prove` binary with `PERL_TEST_HARNESS_DUMP_TAP` set so Test::Harness dumps raw per-file TAP into a temp dir. The helper then walks that dir, parses each file with `TAP::Parser`, and writes a JSON blob to `--results <path>`. `adapter.results` decodes that JSON and maps it back onto positions.
- **JSON contract** — `{ "files": { "<abs path>": { "status", "errors", "subtests": { "<name or outer::inner>": { "status", "errors" } } } } }`. Subtest keys for nested subtests are `::`-joined; the adapter maps them to neotest position IDs of the form `<file>::<subtest>`. Error `line` is 1-indexed in the JSON; the Lua side converts to 0-indexed for neotest.
- **Helper JSON is encoded with core `JSON::PP`** (no CPAN), deliberately without `->utf8` so raw TAP bytes that are not valid UTF-8 pass through instead of making the helper die. The document is built as a plain Perl structure and handed to `json_out`; if you change its shape, update that structure AND `adapter.results` together.

### Subtest discovery has a sharp edge

The tree-sitter query in `query.lua` only matches subtests whose first argument is a string literal or an autoquoted bareword (`subtest "name" => sub { ... }`, `subtest("name", sub { ... })`, `subtest name => sub { ... }`). Subtests with a computed name (e.g. `subtest $name => sub { ... }`) are deliberately not emitted as positions — their results fold into the file result. The TAP parser in the helper, however, still records them. Subtests nest by 4-space indentation and open/close in one of two forms depending on the test framework: Test::More opens with a `# Subtest: NAME` comment and closes with a same-indent `ok N - NAME` line; Test2::V0 opens with a same-indent `(not )?ok N - NAME {` line (status already known at open time, since Test2 buffers subtest output) and closes with a same-indent, bare `}` line (no name repeated). Don't try to "fix" the query to match dynamic names without also reconciling what neotest would do with positions it can't map back.

### Subtests cannot be run in isolation

`prove` only runs whole files. Running a single subtest from neotest still runs the whole file; the subtest-level result is purely a mapping from the file's TAP. Don't add code that pretends otherwise.

## Common commands

```bash
# Run the full Lua test suite (bootstraps pinned deps into .tests/).
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
- The Lua test suite needs the `perl` tree-sitter parser for the discovery tests. `it_with_parser()` in `tests/helpers.lua` marks those pending when the parser is missing; CI installs it explicitly.
- Shared spec helpers live in `tests/helpers.lua` (`require("tests.helpers")`; `tests/minimal_init.lua` puts the repo root on `package.path`). Plenary only runs `*_spec.lua`, so it is never executed as a spec.
- `.tests/` and `.tmp/` are gitignored caches; don't commit them.
- Test deps are **pinned** by the `deps` table in `tests/minimal_init.lua` (one `rev` each), and the bootstrap force-checks-out that revision even over an existing `.tests/`. CI has no clone step of its own — it runs the same bootstrap. Bumping a `rev` is a deliberate, standalone change; don't bump one incidentally while fixing something else.

## Conventions

- **stylua** (`stylua.toml`): 2-space indent, 100-col width, `AutoPreferDouble` quotes. CI fails on `stylua --check lua tests`.
- **Perl helper stays on core modules only** (Perl 5.14+). No CPAN deps. The floor is derived from the newest core module it loads (`TAP::Parser` → 5.10.1, `JSON::PP` → 5.14); don't raise it without a module that needs it. CI runs `perl/t` against the floor in a `perl:5.14` container.
- The helper's `--results <path> -- <prove-cmd> [args...]` argument shape is part of the contract with `adapter.build_spec`; the `--` separator is required.
- User-facing docs live in three places that must stay in sync: `README.md`, `doc/neotest-prove.txt` (vimdoc, CI runs `helptags` on it), and `CHANGELOG.md` (Keep a Changelog; add an entry under Unreleased for user-visible changes).
