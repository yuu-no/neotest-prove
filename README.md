# neotest-prove

[![CI](https://github.com/yuu-no/neotest-prove/actions/workflows/ci.yml/badge.svg)](https://github.com/yuu-no/neotest-prove/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)

A [neotest](https://github.com/nvim-neotest/neotest) adapter for running Perl
tests with [`prove`](https://perldoc.perl.org/prove) (Test::Harness).

It discovers `.t` test files and the `subtest` blocks inside them, runs them
with the real `prove` binary, and reports per-file and per-subtest results —
including failure messages and line numbers — back to neotest. Both
Test::More and Test2::V0 style subtests are understood.

## Requirements

- Neovim with [neotest](https://github.com/nvim-neotest/neotest) and its
  dependencies (`nvim-nio`, `plenary.nvim`). CI runs against Neovim stable.
- `prove` on your `PATH` (ships with Perl's Test::Harness)
- Perl 5.10.1 or newer. No CPAN modules beyond the Perl core are required.
- The `perl` parser for [`nvim-treesitter`](https://github.com/nvim-treesitter/nvim-treesitter)
  (`:TSInstall perl`) — used to discover `subtest` blocks. Without it only
  whole files are shown.
- A POSIX-like OS (Linux, macOS, BSD). Windows is untested.

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "nvim-neotest/neotest",
  dependencies = {
    "nvim-neotest/nvim-nio",
    "nvim-lua/plenary.nvim",
    "nvim-treesitter/nvim-treesitter",
    "yuu-no/neotest-prove",
  },
  config = function()
    require("neotest").setup({
      adapters = {
        require("neotest-prove"),
      },
    })
  end,
}
```

Then run `:checkhealth neotest-prove` to confirm that `perl`, `prove`, and
the tree-sitter parser are all found.

## Configuration

The adapter works with no configuration. To customise it, call it with a
table. The values below are the defaults:

```lua
require("neotest").setup({
  adapters = {
    require("neotest-prove")({
      -- Command used to invoke prove. A string is split on whitespace;
      -- pass a list for multi-word commands, e.g. { "carton", "exec", "prove" }.
      prove_command = "prove",

      -- Extra arguments always passed to prove (e.g. { "-Ilib", "-j4" }).
      prove_args = {},

      -- Command used to run the bundled Perl helper (same shape as prove_command).
      perl_command = "perl",

      -- Include the `xt/` (author test) directory when discovering tests.
      include_xt = false,

      -- Files/directories whose presence marks a project root. prove is run
      -- from the root, so relative paths in prove_args resolve against it.
      root_files = { "cpanfile", "Makefile.PL", "Build.PL", "dist.ini", ".git" },

      -- Additional directory names to exclude from test discovery.
      -- `.git`, `blib`, `local`, `_build` and `.build` are always excluded.
      extra_filter_dirs = {},
    }),
  },
})
```

Top-level keys replace the defaults wholesale (lists are not merged). Unknown
option names, values of the wrong type, lists holding a non-string element,
and an empty `prove_command` or `perl_command` raise an error at setup time.

Run-time arguments passed to `neotest.run.run({ ..., extra_args = { ... } })`
are appended to the `prove` command after `prove_args`.

Full reference: `:h neotest-prove`.

## Usage

Use neotest as normal — see `:h neotest`. For example:

```lua
require("neotest").run.run()                    -- run the nearest test / subtest
require("neotest").run.run(vim.fn.expand("%"))  -- run the current file
require("neotest").run.run("t/")                -- run a directory
require("neotest").summary.toggle()             -- browse tests and results
```

## How it works

`build_spec` constructs a command that runs a small bundled Perl helper
(`perl/neotest-prove-runner.pl`). The helper runs your `prove` command with
`PERL_TEST_HARNESS_DUMP_TAP` set, so Test::Harness writes the raw TAP of each
test file to a temporary directory. `--merge` is always passed so that the
failure diagnostics Test::More prints to stderr end up in that TAP. The helper
then parses the TAP with the core `TAP::Parser` module, matches subtests by
their indentation, and writes structured results as JSON, which the adapter
maps back onto neotest positions.

Because the real `prove` binary is used, your `.proverc` and `prove` plugins
are respected, and `prove_command` can be anything that behaves like `prove`
(`carton exec prove`, a wrapper script, …).

## Limitations

- **Subtest discovery is static.** Only `subtest "name" => sub { ... }`,
  `subtest("name", sub { ... })` and `subtest name => sub { ... }` (a literal
  string or a bareword) are shown as positions. Subtests with a computed or
  interpolated name (`subtest $name => sub { ... }`) are not surfaced
  individually; their results fold into the file result.
- **Subtests cannot be run in isolation.** `prove` runs whole files, so
  running a single subtest runs its file; the per-subtest result is mapped
  back from the file's TAP.
- Not supported: a DAP (debugging) strategy, `Test::Class`-style xUnit tests,
  and live result streaming.

## Troubleshooting

- **No tests are discovered.** Run `:checkhealth neotest-prove`. Test files
  must end in `.t`, and `xt/` is skipped unless `include_xt` is set.
- **Files show up but subtests do not.** The `perl` tree-sitter parser is
  missing (`:TSInstall perl`), or the subtest names are not literal strings.
- **Every test is marked failed with no message.** Open the test output
  (`require("neotest").output.open()`); if `prove` or the helper could not be
  started, its error is there. `prove_command` and `perl_command` must be
  executable from Neovim's environment.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) for how to run the test suites and
what the Perl helper may depend on.

## License

[MIT](./LICENSE)
