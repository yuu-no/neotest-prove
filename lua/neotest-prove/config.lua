local M = {}

---@class neotest-prove.Config
---@field prove_command string|string[] Command used to invoke prove (string is split on whitespace).
---@field prove_args string[] Extra arguments always passed to prove.
---@field perl_command string|string[] Command used to invoke perl (reserved for future use).
---@field include_xt boolean Whether to include the `xt/` directory when discovering tests.
---@field root_files string[] Files/directories whose presence marks a project root.
---@field extra_filter_dirs string[] Additional directory names to exclude from test discovery.

---@type neotest-prove.Config
local defaults = {
  prove_command = "prove",
  prove_args = {},
  perl_command = "perl",
  include_xt = false,
  root_files = { "cpanfile", "Makefile.PL", "Build.PL", "dist.ini", ".git" },
  extra_filter_dirs = {},
}

--- Merge user configuration over the defaults.
--- Top-level keys are replaced wholesale (list values are not deep-merged).
---@param user_config? neotest-prove.Config
---@return neotest-prove.Config
function M.merge(user_config)
  if user_config ~= nil then
    assert(type(user_config) == "table", "neotest-prove: config must be a table")
  end
  return vim.tbl_extend("force", vim.deepcopy(defaults), user_config or {})
end

--- Normalise a configured command into an argument list.
--- A string is split on whitespace; a list is copied as-is.
---@param command string|string[]
---@return string[]
function M.to_argv(command)
  if type(command) == "table" then
    return vim.deepcopy(command)
  end
  return vim.split(command, "%s+", { trimempty = true })
end

return M
