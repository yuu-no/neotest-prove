-- Tree-sitter query (perl) for discovering `subtest` blocks as neotest
-- positions. Verified against the tree-sitter-perl grammar.
--
-- Subtests are emitted as `test`-type positions (not `namespace`): neotest's
-- position tree prunes namespaces that contain no tests, and a subtest has no
-- child `test` positions of its own. `discover_positions` parses with
-- `nested_tests = true` so a subtest nested inside another is kept.
--
-- Captures:
--   @test.name       the subtest name (string content, without quotes)
--   @test.definition the whole subtest call expression
--
-- Subtests whose name is not a literal string -- a variable, or a
-- double-quoted string containing interpolation (`"encode: $enc"`) -- are
-- intentionally not matched and fall back to file-level results: their
-- runtime names can never be mapped back to a static position, and neotest
-- assigns positions with no result the whole file's status, showing
-- spurious failures on unrelated subtests. Double-quoted strings parse as
-- `interpolated_string_literal` even without interpolation, and interpolation
-- appears as named children *inside* `string_content` -- which the query
-- language cannot forbid (negation exists only for fields); instead any
-- double-quoted name containing `$`, `@`, or `\` (interpolation or escapes
-- -- both change the runtime name) is rejected by text. Single-quoted names
-- keep those characters literally and are always matched.
--
-- A bareword before `=>` (`subtest can_dlv => sub { ... }`) is autoquoted by
-- Perl, so its runtime name is static and it parses as `autoquoted_bareword`.
-- It must be matched: an undiscovered outer subtest does not merely lose its
-- own position, it reparents its children onto the file, so the nested
-- subtests inside it get position IDs like `<file>::valid` while the helper
-- reports `can_dlv::valid` -- nothing matches, and neotest paints every one
-- of them with the file's failed status.
--
-- Each pattern alternates over the paren-call and paren-less call forms;
-- the string-literal and interpolated-string-literal cases stay separate
-- patterns because the `#not-match?` predicate applies per-pattern and must
-- gate only the double-quoted form.

return [[
;; subtest('name', sub { ... })  /  subtest 'name' => sub { ... }
(
  [
    (function_call_expression
      function: (function) @_subtest
      arguments: (list_expression
        .
        (string_literal content: (string_content) @test.name))) @test.definition
    (ambiguous_function_call_expression
      function: (function) @_subtest
      arguments: (list_expression
        .
        (string_literal content: (string_content) @test.name))) @test.definition
  ]
  (#eq? @_subtest "subtest"))

;; subtest("name", sub { ... })  /  subtest "name" => sub { ... }
(
  [
    (function_call_expression
      function: (function) @_subtest
      arguments: (list_expression
        .
        (interpolated_string_literal content: (string_content) @test.name))) @test.definition
    (ambiguous_function_call_expression
      function: (function) @_subtest
      arguments: (list_expression
        .
        (interpolated_string_literal content: (string_content) @test.name))) @test.definition
  ]
  (#eq? @_subtest "subtest")
  (#not-match? @test.name "[$@\\\\]"))

;; subtest(name => sub { ... })  /  subtest name => sub { ... }
(
  [
    (function_call_expression
      function: (function) @_subtest
      arguments: (list_expression
        .
        (autoquoted_bareword) @test.name)) @test.definition
    (ambiguous_function_call_expression
      function: (function) @_subtest
      arguments: (list_expression
        .
        (autoquoted_bareword) @test.name)) @test.definition
  ]
  (#eq? @_subtest "subtest"))
]]
