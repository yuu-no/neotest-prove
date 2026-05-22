# neotest-prove

A [neotest](https://github.com/nvim-neotest/neotest) adapter for running Perl
tests with [`prove`](https://perldoc.perl.org/prove) (Test::Harness).

It discovers `.t` test files and the `subtest` blocks inside them, runs them
with the real `prove` binary, and reports per-file and per-subtest results —
including failure messages and line numbers — back to neotest.

## Requirements

- Neovim with [neotest](https://github.com/nvim-neotest/neotest) and its
  dependencies (`nvim-nio`, `plenary.nvim`)
- The `perl` parser for [`nvim-treesitter`](https://github.com/nvim-treesitter/nvim-treesitter)
  (`:TSInstall perl`) — used to discover `subtest` blocks
- `prove` on your `PATH` (ships with Perl's Test::Harness)
- Perl 5.10.1 or newer

No CPAN modules beyond the Perl core are required.

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

## Configuration

The adapter works with no configuration. To customise it, call it with a table:

```lua
require("neotest").setup({
  adapters = {
    require("neotest-prove")({
      -- Command used to invoke prove. A string is split on whitespace;
      -- pass a list for multi-word commands, e.g. { "carton", "exec", "prove" }.
      prove_command = "prove",

      -- Extra arguments always passed to prove (e.g. { "-Ilib", "-j4" }).
      prove_args = {},

      -- Command used to invoke perl for the bundled helper.
      perl_command = "perl",

      -- Include the `xt/` (author test) directory when discovering tests.
      include_xt = false,

      -- Files/directories whose presence marks a project root.
      root_files = { "cpanfile", "Makefile.PL", "Build.PL", "dist.ini", ".git" },

      -- Additional directory names to exclude from test discovery.
      -- `.git`, `blib`, `local`, `_build` and `.build` are always excluded.
      extra_filter_dirs = {},
    }),
  },
})
```

Run-time arguments passed to `neotest.run.run({ extra_args = { ... } })` are
appended to the `prove` command in addition to `prove_args`.

## Usage

Use neotest as normal — see `:h neotest`. For example:

```lua
require("neotest").run.run()              -- run the nearest test / subtest
require("neotest").run.run(vim.fn.expand("%"))  -- run the current file
require("neotest").summary.toggle()       -- browse tests and results
```

## How it works

`build_spec` constructs a command that runs a small bundled Perl helper
(`perl/neotest-prove-runner.pl`). The helper runs your `prove` command with
`PERL_TEST_HARNESS_DUMP_TAP` set, so Test::Harness writes the raw TAP of each
test file to a temporary directory. The helper then parses that TAP with the
core `TAP::Parser` module and writes structured results as JSON, which the
adapter maps back onto neotest positions.

Because the real `prove` binary is used, your `.proverc` and `prove` plugins
are respected.

## Limitations

- **Subtest discovery is static.** Only `subtest "name" => sub { ... }` and
  `subtest("name", sub { ... })` with a literal string name are shown as
  positions. Subtests with a computed name (`subtest $name => sub { ... }`)
  are not surfaced individually; their results fold into the file result.
- **Subtests cannot be run in isolation.** `prove` runs whole files, so
  running a single subtest runs its file; the per-subtest result is mapped
  back from the file's TAP.
- Not supported in this version: a DAP (debugging) strategy,
  `Test::Class`-style xUnit tests, and live result streaming.

## License

[MIT](./LICENSE)
