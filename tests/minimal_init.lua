-- Minimal init for running the test suite with plenary busted.
--
-- Test dependencies are bootstrapped into ./.tests/site on first run and held
-- at the revisions pinned below, so that every machine and every CI run tests
-- against the same upstream. Nothing updates them on its own: bump a `rev`
-- deliberately, in its own commit, and say in the message what it buys.

local root = vim.fn.fnamemodify(vim.fn.getcwd(), ":p")
local deps_root = root .. ".tests/site/pack/deps/start/"

local deps = {
  {
    name = "plenary.nvim",
    url = "https://github.com/nvim-lua/plenary.nvim",
    rev = "74b06c6c75e4eeb3108ec01852001636d85a932b",
  },
  {
    name = "nvim-nio",
    url = "https://github.com/nvim-neotest/nvim-nio",
    rev = "21f5324bfac14e22ba26553caf69ec76ae8a7662",
  },
  {
    name = "nvim-treesitter",
    url = "https://github.com/nvim-treesitter/nvim-treesitter",
    rev = "4916d6592ede8c07973490d9322f187e07dfefac",
  },
  {
    name = "neotest",
    url = "https://github.com/nvim-neotest/neotest",
    rev = "ad991822b7076b1d940b33a9d6d0d30416d5df81",
  },
}

--- Run git inside `path`, aborting with its output when it fails. Bootstrap
--- failures have to be loud: a silently missing dependency would surface much
--- later as a confusing `require` error from inside a spec.
---@param path string
---@param args string[]
---@return string output
local function git(path, args)
  local argv = { "git", "-C", path }
  vim.list_extend(argv, args)
  local output = vim.trim(vim.fn.system(argv))
  if vim.v.shell_error ~= 0 then
    error(("git %s failed in %s:\n%s"):format(table.concat(args, " "), path, output))
  end
  return output
end

--- The revision currently checked out, or nil for a repository that has none
--- yet (which is the state `git init` leaves behind).
---@param path string
---@return string|nil
local function head_rev(path)
  local rev = vim.trim(vim.fn.system({ "git", "-C", path, "rev-parse", "HEAD" }))
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return rev
end

for _, dep in ipairs(deps) do
  local path = deps_root .. dep.name
  if vim.fn.isdirectory(path .. "/.git") == 0 then
    vim.fn.mkdir(path, "p")
    -- `git init` and a shallow fetch of the exact revision rather than a
    -- `git clone --depth 1`: a shallow clone only carries the tip of the
    -- default branch, which is not usually the revision pinned above.
    git(path, { "init", "--quiet" })
    git(path, { "remote", "add", "origin", dep.url })
  end
  if head_rev(path) ~= dep.rev then
    print(("Fetching %s %s ..."):format(dep.name, dep.rev:sub(1, 7)))
    git(path, { "fetch", "--depth", "1", "--quiet", "origin", dep.rev })
    git(path, { "checkout", "--quiet", "--force", dep.rev })
  end
  vim.opt.runtimepath:prepend(path)
end

vim.opt.runtimepath:prepend(root)
-- Lets the specs `require("tests.helpers")`; the runtimepath only exposes
-- `lua/` subdirectories to `require`.
package.path = root .. "?.lua;" .. package.path
vim.opt.swapfile = false

vim.cmd("runtime! plugin/plenary.vim")
