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

-- Every option, with its default value and the types it accepts. Validation
-- rejects typos and wrong shapes up front rather than failing obscurely when
-- a test is run.
local OPTIONS = {
  prove_command = { default = "prove", types = { "string", "table" } },
  prove_args = { default = {}, types = { "table" } },
  perl_command = { default = "perl", types = { "string", "table" } },
  include_xt = { default = false, types = { "boolean" } },
  root_files = {
    default = { "cpanfile", "Makefile.PL", "Build.PL", "dist.ini", ".git" },
    types = { "table" },
  },
  extra_filter_dirs = { default = {}, types = { "table" } },
}

---@type neotest-prove.Config
local defaults = {}
for key, option in pairs(OPTIONS) do
  defaults[key] = option.default
end

---@param key string
---@param value any
---@param option { types: string[] }
local function validate_option(key, value, option)
  local types = option.types
  local lua_type = type(value)
  if not vim.tbl_contains(types, lua_type) then
    error(
      ("neotest-prove: option %q must be of type %s, got %s"):format(
        key,
        table.concat(types, " or "),
        lua_type
      ),
      0
    )
  end
end

---@param user_config table
local function validate(user_config)
  for key, value in pairs(user_config) do
    local option = OPTIONS[key]
    if not option then
      error(("neotest-prove: unknown option %q"):format(tostring(key)), 0)
    end
    validate_option(key, value, option)
  end
end

--- Return a copy of the default configuration.
---@return neotest-prove.Config
function M.defaults()
  return vim.deepcopy(defaults)
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
