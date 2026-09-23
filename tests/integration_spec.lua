local h = require("tests.helpers")

local adapter = require("neotest-prove")
local FIXTURES = h.FIXTURES

--- Build a spec from a tree, run its command, and return mapped results.
local function run_tree(tree, adp)
  adp = adp or adapter
  local spec = adp.build_spec({ tree = tree })
  assert(spec, "build_spec returned nil")
  local completed = vim.system(spec.command, { cwd = spec.cwd, text = true }):wait()
  return h.sync(function()
    return adp.results(spec, { code = completed.code, output = "" }, tree)
  end)
end

local function run_file(path, adp)
  return run_tree(h.file_tree(path), adp)
end

describe("neotest-prove integration", function()
  it("reports a passing file end-to-end", function()
    local path = FIXTURES .. "/pass.t"
    assert.equals("passed", run_file(path)[path].status)
  end)

  it("reports a failing file end-to-end", function()
    local path = FIXTURES .. "/fail.t"
    local results = run_file(path)
    assert.equals("failed", results[path].status)
  end)

  it("reports per-subtest results end-to-end", function()
    local path = FIXTURES .. "/subtests.t"
    local results = run_file(path)
    assert.equals("failed", results[path].status)
    assert.equals("passed", results[path .. "::alpha"].status)
    assert.equals("failed", results[path .. "::beta"].status)
    assert.is_truthy(results[path .. "::beta"].errors)
    assert.is_truthy(results[path .. "::beta"].errors[1].line)
  end)

  it("reports results for every file in a directory run", function()
    local dir = FIXTURES .. "/projects/sample/t"
    local pass = dir .. "/pass.t"
    local fail = dir .. "/fail.t"
    local tree = h.tree_of({
      { id = dir, type = "dir", name = "t", path = dir, range = { 0, 0, 0, 0 } },
      { h.file_pos(pass) },
      { h.file_pos(fail) },
    })
    local results = run_tree(tree)
    assert.equals("passed", results[pass].status)
    assert.equals("failed", results[fail].status)
  end)

  it("degrades gracefully when prove is missing", function()
    local broken = require("neotest-prove")({ prove_command = "neotest-prove-no-such-binary" })
    assert.same({}, run_file(FIXTURES .. "/pass.t", broken))
  end)
end)
