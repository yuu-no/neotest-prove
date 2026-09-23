# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- neotest adapter for Perl's `prove`: discovers `.t` files and `subtest`
  blocks, runs them through the real `prove` binary, and reports per-file and
  per-subtest results with failure messages and line numbers.
- Support for both Test::More (`# Subtest:` comment) and Test2::V0
  (brace-style) subtest output, including nested subtests and subtests
  skipped in their entirety.
- Discovery of subtests named by a single-quoted string, a double-quoted
  string without interpolation, or an autoquoted bareword.
- Failure diagnostics (`got:` / `expected:`, comparison tables) are folded
  into the error message shown by neotest.
- Failures reported from another file (for example a helper module) keep
  their location in the message instead of being pinned to a wrong line.
- `:checkhealth neotest-prove` verifies `perl`, `prove`, the bundled helper,
  and the tree-sitter parser.
- Configuration is validated: unknown options and wrong value types raise an
  error at setup time.
- Vim help (`:h neotest-prove`).

[Unreleased]: https://github.com/yuu-no/neotest-prove/commits/main
