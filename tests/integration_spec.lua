local Tree = require("neotest.types").Tree
local nio = require("nio")

local adapter = require("neotest-prove")
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
  vim.wait(30000, function()
    return done
  end, 25)
  assert(done, "neotest-prove integration test: timed out")
  if err then
    error(err)
  end
  return value
end

local function file_pos(path)
  return {
    id = path,
    type = "file",
    name = vim.fn.fnamemodify(path, ":t"),
    path = path,
    range = { 0, 0, 1, 0 },
  }
end

--- Build a spec from a tree, run its command, and return mapped results.
local function run_tree(tree, adp)
  adp = adp or adapter
  local spec = adp.build_spec({ tree = tree })
  assert(spec, "build_spec returned nil")
  local completed = vim.system(spec.command, { cwd = spec.cwd, text = true }):wait()
  return sync(function()
    return adapter.results(spec, { code = completed.code, output = "" }, tree)
  end)
end

local function run_file(path, adp)
  return run_tree(Tree.from_list({ file_pos(path) }, function(p)
    return p.id
  end), adp)
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
    local tree = Tree.from_list({
      { id = dir, type = "dir", name = "t", path = dir, range = { 0, 0, 0, 0 } },
      { file_pos(pass) },
      { file_pos(fail) },
    }, function(p)
      return p.id
    end)
    local results = run_tree(tree)
    assert.equals("passed", results[pass].status)
    assert.equals("failed", results[fail].status)
  end)

  it("degrades gracefully when prove is missing", function()
    local broken = require("neotest-prove")({ prove_command = "neotest-prove-no-such-binary" })
    assert.same({}, run_file(FIXTURES .. "/pass.t", broken))
  end)
end)
