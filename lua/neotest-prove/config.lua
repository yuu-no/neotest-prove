local M = {}

---@class neotest-prove.Config
---@field prove_command string|string[] Command used to invoke `prove`. A string is split on whitespace; pass a list for multi-word commands such as `{ "carton", "exec", "prove" }`.
---@field prove_args string[] Extra arguments always passed to `prove`.
---@field perl_command string|string[] Command used to run the bundled Perl helper. Same shape as `prove_command`.
---@field include_xt boolean Whether to include the `xt/` (author test) directory when discovering tests.
---@field root_files string[] Files or directories whose presence marks a project root.
---@field extra_filter_dirs string[] Additional directory names to exclude from test discovery.

---@class neotest-prove.UserConfig
---@field prove_command? string|string[]
---@field prove_args? string[]
---@field perl_command? string|string[]
---@field include_xt? boolean
---@field root_files? string[]
---@field extra_filter_dirs? string[]

---@type neotest-prove.Config
local defaults = {
  prove_command = "prove",
  prove_args = {},
  perl_command = "perl",
  include_xt = false,
  root_files = { "cpanfile", "Makefile.PL", "Build.PL", "dist.ini", ".git" },
  extra_filter_dirs = {},
}

-- Accepted Lua types for each option, used to reject typos and wrong shapes
-- up front rather than failing obscurely when a test is run.
local SCHEMA = {
  prove_command = { "string", "table" },
  prove_args = { "table" },
  perl_command = { "string", "table" },
  include_xt = { "boolean" },
  root_files = { "table" },
  extra_filter_dirs = { "table" },
}

---@param user_config table
local function validate(user_config)
  for key, value in pairs(user_config) do
    local allowed = SCHEMA[key]
    if not allowed then
      error(("neotest-prove: unknown option %q"):format(tostring(key)), 0)
    end
    if not vim.tbl_contains(allowed, type(value)) then
      error(
        ("neotest-prove: option %q must be of type %s, got %s"):format(
          key,
          table.concat(allowed, " or "),
          type(value)
        ),
        0
      )
    end
  end
end

--- Merge user configuration over the defaults.
--- Top-level keys are replaced wholesale (list values are not deep-merged).
--- Raises on unknown option names or values of the wrong type.
---@param user_config? neotest-prove.UserConfig
---@return neotest-prove.Config
function M.merge(user_config)
  if user_config ~= nil then
    if type(user_config) ~= "table" then
      error("neotest-prove: config must be a table", 0)
    end
    validate(user_config)
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
