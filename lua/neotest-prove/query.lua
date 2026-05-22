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
-- Subtests whose first argument is not a string literal (e.g. a variable)
-- are intentionally not matched and fall back to file-level results.

return [[
;; subtest("name", sub { ... })
(
  (function_call_expression
    function: (function) @_subtest
    arguments: (list_expression
      .
      [
        (string_literal content: (string_content) @test.name)
        (interpolated_string_literal content: (string_content) @test.name)
      ]))
  @test.definition
  (#eq? @_subtest "subtest"))

;; subtest "name" => sub { ... }
(
  (ambiguous_function_call_expression
    function: (function) @_subtest
    arguments: (list_expression
      .
      [
        (string_literal content: (string_content) @test.name)
        (interpolated_string_literal content: (string_content) @test.name)
      ]))
  @test.definition
  (#eq? @_subtest "subtest"))
]]
