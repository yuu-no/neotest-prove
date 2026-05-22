-- Minimal init for running the test suite with plenary busted.
-- Test dependencies are bootstrapped into ./.tests/site on first run.

local root = vim.fn.fnamemodify(vim.fn.getcwd(), ":p")
local deps_root = root .. ".tests/site/pack/deps/start/"

local deps = {
  ["plenary.nvim"] = "https://github.com/nvim-lua/plenary.nvim",
  ["nvim-nio"] = "https://github.com/nvim-neotest/nvim-nio",
  ["nvim-treesitter"] = "https://github.com/nvim-treesitter/nvim-treesitter",
  ["neotest"] = "https://github.com/nvim-neotest/neotest",
}

for name, url in pairs(deps) do
  local path = deps_root .. name
  if vim.fn.isdirectory(path) == 0 then
    print("Cloning " .. name .. " ...")
    vim.fn.system({ "git", "clone", "--depth", "1", url, path })
  end
  vim.opt.runtimepath:prepend(path)
end

vim.opt.runtimepath:prepend(root)
vim.opt.swapfile = false

vim.cmd("runtime! plugin/plenary.vim")
