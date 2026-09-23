-- Shared helpers for the Lua specs. Loaded as `require("tests.helpers")`;
-- tests/minimal_init.lua puts the repository root on `package.path`.

local Tree = require("neotest.types").Tree
local nio = require("nio")

local M = {}

-- The specs are run from the repository root (`./scripts/test` does this).
M.FIXTURES = vim.fn.getcwd() .. "/tests/fixtures"

--- Run an async function to completion from a synchronous test and return
--- its value, re-raising any error it threw.
---@param fn fun(): any
---@param timeout_ms? integer defaults to 30 seconds
---@return any
function M.sync(fn, timeout_ms)
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
  vim.wait(timeout_ms or 30000, function()
    return done
  end, 20)
  assert(done, "neotest-prove test: async operation timed out")
  if err then
    error(err)
  end
  return value
end

--- A file position for `path`, as neotest would build it.
---@param path string
---@return neotest.Position
function M.file_pos(path)
  return {
    id = path,
    type = "file",
    name = vim.fn.fnamemodify(path, ":t"),
    path = path,
    range = { 0, 0, 1, 0 },
  }
end

--- A test position for the subtest `name` inside `path`.
---@param path string
---@param name string
---@return neotest.Position
function M.subtest_pos(path, name)
  return {
    id = path .. "::" .. name,
    type = "test",
    name = name,
    path = path,
    range = { 0, 0, 1, 0 },
  }
end

--- Build a position tree from a nested list, keyed by position id
--- (see `neotest.types.Tree.from_list`).
---@param list table
---@return neotest.Tree
function M.tree_of(list)
  return Tree.from_list(list, function(pos)
    return pos.id
  end)
end

--- A tree holding only the file position for `path`.
---@param path string
---@return neotest.Tree
function M.file_tree(path)
  return M.tree_of({ M.file_pos(path) })
end

---@return boolean
function M.has_perl_parser()
  return (pcall(vim.treesitter.get_string_parser, "", "perl"))
end

--- Like `it`, but marks the test pending when the perl tree-sitter parser is
--- not installed (the discovery tests cannot run without it).
---@param name string
---@param fn function
function M.it_with_parser(name, fn)
  it(name, function()
    if not M.has_perl_parser() then
      return pending("perl treesitter parser not installed")
    end
    return fn()
  end)
end

return M
