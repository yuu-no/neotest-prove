-- Location of the bundled Perl helper (`perl/neotest-prove-runner.pl`).
--
-- The helper is located relative to this file rather than searched on the
-- runtimepath, so the plugin keeps working whatever directory name it was
-- installed under. Both the adapter (which runs it) and the health check
-- (which reports on it) resolve the path through here.

local M = {}

-- Relative to the plugin root.
local HELPER_RELATIVE_PATH = "perl/neotest-prove-runner.pl"

local _path

--- Absolute path of the bundled Perl helper. Existence is not checked;
--- callers decide how to report a missing file.
---@return string
function M.path()
  if not _path then
    local source = debug.getinfo(1, "S").source:sub(2)
    local plugin_root = vim.fn.fnamemodify(source, ":p:h:h:h")
    _path = plugin_root .. "/" .. HELPER_RELATIVE_PATH
  end
  return _path
end

return M
