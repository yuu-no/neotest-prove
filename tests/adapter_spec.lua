local Tree = require("neotest.types").Tree
local nio = require("nio")

local FIXTURES = vim.fn.getcwd() .. "/tests/fixtures"

--- Run an async function to completion from a synchronous test.
local function sync(fn)
  local done, value, err = false, nil, nil
  nio.run(function()
    local ok, res = pcall(fn)
    if ok then
      value = res
    else
      err = res
    end
    done = true
  end)
  vim.wait(10000, function()
    return done
  end, 20)
  assert(done, "neotest-prove test: async operation timed out")
  if err then
    error(err)
  end
  return value
end

local function has_perl_parser()
  return (pcall(vim.treesitter.get_string_parser, "", "perl"))
end

local function single_tree(pos)
  return Tree.from_list({ pos }, function(p)
    return p.id
  end)
end

local function file_tree(path)
  return single_tree({
    id = path,
    type = "file",
    name = vim.fn.fnamemodify(path, ":t"),
    path = path,
    range = { 0, 0, 1, 0 },
  })
end

describe("neotest-prove adapter", function()
  local adapter = require("neotest-prove")

  describe("entry point", function()
    it("is usable directly as an adapter", function()
      assert.equals("neotest-prove", adapter.name)
      local fns = { "root", "filter_dir", "is_test_file", "discover_positions", "build_spec", "results" }
      for _, fn in ipairs(fns) do
        assert.is_function(adapter[fn], fn .. " should be a function")
      end
    end)

    it("is callable with a config table", function()
      local configured = require("neotest-prove")({ include_xt = true })
      assert.equals("neotest-prove", configured.name)
      assert.is_function(configured.build_spec)
    end)

    it("accepts an empty config", function()
      assert.equals("neotest-prove", require("neotest-prove")({}).name)
    end)
  end)

  describe("is_test_file", function()
    it("accepts .t files", function()
      assert.is_true(adapter.is_test_file("/proj/t/foo.t"))
    end)

    it("rejects non-.t files", function()
      assert.is_false(adapter.is_test_file("/proj/lib/Foo.pm"))
      assert.is_false(adapter.is_test_file("/proj/script.pl"))
      assert.is_false(adapter.is_test_file("/proj/t/README"))
      assert.is_false(adapter.is_test_file("/proj/data.txt"))
    end)
  end)

  describe("filter_dir", function()
    it("allows ordinary directories", function()
      assert.is_true(adapter.filter_dir("t", "t", "/proj"))
      assert.is_true(adapter.filter_dir("lib", "lib", "/proj"))
    end)

    it("excludes xt by default", function()
      assert.is_false(adapter.filter_dir("xt", "xt", "/proj"))
    end)

    it("includes xt when configured", function()
      local configured = require("neotest-prove")({ include_xt = true })
      assert.is_true(configured.filter_dir("xt", "xt", "/proj"))
    end)

    it("excludes build and vcs directories", function()
      for _, name in ipairs({ ".git", "blib", "local", "_build", ".build" }) do
        assert.is_false(adapter.filter_dir(name, name, "/proj"))
      end
    end)
  end)

  describe("root", function()
    it("detects a project root from marker files", function()
      assert.equals(
        FIXTURES .. "/projects/sample",
        adapter.root(FIXTURES .. "/projects/sample/t")
      )
    end)

    it("returns nil when no marker is found", function()
      assert.is_nil(adapter.root("/tmp"))
    end)
  end)

  describe("discover_positions", function()
    local function discover(path)
      return sync(function()
        return adapter.discover_positions(path)
      end)
    end

    local function subtest_names(tree)
      local names = {}
      for _, pos in tree:iter() do
        if pos.type == "test" then
          names[#names + 1] = pos.name
        end
      end
      table.sort(names)
      return names
    end

    it("returns a file-only tree for a plain test file", function()
      if not has_perl_parser() then
        return pending("perl treesitter parser not installed")
      end
      local tree = discover(FIXTURES .. "/pass.t")
      assert.equals("file", tree:data().type)
      assert.same({}, subtest_names(tree))
    end)

    it("discovers top-level subtests", function()
      if not has_perl_parser() then
        return pending("perl treesitter parser not installed")
      end
      assert.same({ "alpha", "beta" }, subtest_names(discover(FIXTURES .. "/subtests.t")))
    end)

    it("discovers nested subtests", function()
      if not has_perl_parser() then
        return pending("perl treesitter parser not installed")
      end
      assert.same({ "inner", "outer" }, subtest_names(discover(FIXTURES .. "/nested_subtest.t")))
    end)

    it("ignores subtests with a dynamic name", function()
      if not has_perl_parser() then
        return pending("perl treesitter parser not installed")
      end
      assert.same({ "static one" }, subtest_names(discover(FIXTURES .. "/dynamic_subtest.t")))
    end)

    it("handles an empty test file", function()
      if not has_perl_parser() then
        return pending("perl treesitter parser not installed")
      end
      local tree = discover(FIXTURES .. "/empty.t")
      assert.equals("file", tree:data().type)
      assert.same({}, subtest_names(tree))
    end)
  end)

  describe("build_spec", function()
    it("returns nil without a tree", function()
      assert.is_nil(adapter.build_spec({}))
    end)

    it("builds a command running the helper and prove for a file", function()
      local path = FIXTURES .. "/pass.t"
      local spec = adapter.build_spec({ tree = file_tree(path) })
      assert.is_table(spec.command)
      assert.is_string(spec.context.results_path)
      local joined = table.concat(spec.command, " ")
      assert.is_truthy(joined:find("neotest%-prove%-runner%.pl"))
      assert.is_truthy(joined:find("%-%-results"))
      assert.is_truthy(joined:find("%-%-merge"))
      assert.is_truthy(joined:find(vim.pesc(path)))
      assert.is_truthy(joined:find(vim.pesc(spec.context.results_path)))
    end)

    it("runs the containing file for a subtest", function()
      local path = FIXTURES .. "/subtests.t"
      local spec = adapter.build_spec({
        tree = single_tree({
          id = path .. "::alpha",
          type = "test",
          name = "alpha",
          path = path,
          range = { 0, 0, 1, 0 },
        }),
      })
      assert.is_truthy(table.concat(spec.command, " "):find(vim.pesc(path)))
    end)

    it("appends prove_args and extra_args", function()
      local configured = require("neotest-prove")({ prove_args = { "-Ilib" } })
      local spec = configured.build_spec({
        tree = file_tree(FIXTURES .. "/pass.t"),
        extra_args = { "--timer" },
      })
      local joined = table.concat(spec.command, " ")
      assert.is_truthy(joined:find("%-Ilib"))
      assert.is_truthy(joined:find("%-%-timer"))
    end)

    it("includes each test file once even when positions share it", function()
      local path = FIXTURES .. "/subtests.t"
      local tree = Tree.from_list({
        { id = path, type = "file", name = "subtests.t", path = path, range = { 0, 0, 1, 0 } },
        {
          {
            id = path .. "::alpha",
            type = "test",
            name = "alpha",
            path = path,
            range = { 0, 0, 1, 0 },
          },
        },
      }, function(p)
        return p.id
      end)
      local spec = adapter.build_spec({ tree = tree })
      local _, count = table.concat(spec.command, " "):gsub(vim.pesc(path), "")
      assert.equals(1, count)
    end)
  end)

  describe("results", function()
    local function write_json(content)
      local path = vim.fn.tempname()
      local fh = assert(io.open(path, "w"))
      fh:write(content)
      fh:close()
      return path
    end

    local function run_results(results_path)
      return sync(function()
        return adapter.results({ context = { results_path = results_path } }, {}, nil)
      end)
    end

    it("maps a passed file", function()
      local path = write_json('{"files":{"/p/t/a.t":{"status":"passed","errors":[],"subtests":{}}}}')
      assert.equals("passed", run_results(path)["/p/t/a.t"].status)
    end)

    it("maps a failed file with errors and zero-indexed lines", function()
      local path = write_json(
        '{"files":{"/p/t/a.t":{"status":"failed",'
          .. '"errors":[{"message":"boom","line":42}],"subtests":{}}}}'
      )
      local results = run_results(path)
      assert.equals("failed", results["/p/t/a.t"].status)
      assert.equals("boom", results["/p/t/a.t"].errors[1].message)
      assert.equals(41, results["/p/t/a.t"].errors[1].line)
    end)

    it("maps subtest results, including nested ones", function()
      local path = write_json(
        '{"files":{"/p/t/a.t":{"status":"failed","errors":[],"subtests":{'
          .. '"alpha":{"status":"passed","errors":[]},'
          .. '"outer::inner":{"status":"failed","errors":[]}}}}}'
      )
      local results = run_results(path)
      assert.equals("passed", results["/p/t/a.t::alpha"].status)
      assert.equals("failed", results["/p/t/a.t::outer::inner"].status)
    end)

    it("returns an empty table when the results file is missing", function()
      assert.same({}, run_results("/no/such/results-file.json"))
    end)

    it("returns an empty table when the results file is corrupt", function()
      assert.same({}, run_results(write_json("{not valid json")))
    end)
  end)
end)
