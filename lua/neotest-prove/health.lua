-- `:checkhealth neotest-prove`
--
-- Verifies that everything the adapter needs at run time is reachable: the
-- perl and prove commands from the configuration, the bundled helper script,
-- and the tree-sitter perl parser used for subtest discovery.

local config = require("neotest-prove.config")
local helper = require("neotest-prove.helper")

local M = {}

-- vim.health renamed its reporting functions in Neovim 0.10; keep the older
-- names working too. Resolved on each call rather than at load time so the
-- functions can be replaced (e.g. by tests) after this module is required.
---@param name string
---@param legacy string
local function reporter(name, legacy)
  return function(...)
    local fn = vim.health[name] or vim.health[legacy]
    return fn(...)
  end
end
local start = reporter("start", "report_start")
local ok = reporter("ok", "report_ok")
local warn = reporter("warn", "report_warn")
local report_error = reporter("error", "report_error")
local info = reporter("info", "report_info")

-- Oldest Perl the bundled helper is written for: JSON::PP, the newest core
-- module it loads, arrived in 5.14.
local MIN_PERL = "5.014000"

--- Collect the configurations of every neotest-prove adapter registered with
--- neotest. Falls back to the defaults when neotest is not set up (yet).
---@return neotest-prove.Config[]
local function registered_configs()
  local loaded, neotest_config = pcall(require, "neotest.config")
  local configs = {}
  if loaded and type(neotest_config.adapters) == "table" then
    for _, adapter in ipairs(neotest_config.adapters) do
      if type(adapter) == "table" and adapter.name == "neotest-prove" and adapter.config then
        configs[#configs + 1] = adapter.config
      end
    end
  end
  if #configs == 0 then
    configs[1] = config.defaults()
  end
  return configs
end

--- Report whether the first word of a configured command is executable.
---@param label string
---@param command string|string[]
---@return string|nil executable the program name, when it was found
local function check_command(label, command)
  local argv = config.to_argv(command)
  local program = argv[1]
  if not program then
    report_error(("%s is empty"):format(label))
    return nil
  end
  if vim.fn.executable(program) == 1 then
    ok(("%s: `%s` is executable"):format(label, table.concat(argv, " ")))
    return program
  end
  report_error(
    ("%s: `%s` is not executable"):format(label, program),
    { ("Install it or point `%s` at the right program."):format(label) }
  )
  return nil
end

--- Report the version of the configured perl and whether it is new enough.
---@param command string|string[]
local function check_perl_version(command)
  local argv = config.to_argv(command)
  vim.list_extend(argv, { "-e", "print $]" })
  local output = vim.fn.system(argv)
  if vim.v.shell_error ~= 0 then
    warn("could not determine the perl version", { vim.trim(output) })
    return
  end
  local version = vim.trim(output)
  if tonumber(version) and tonumber(version) >= tonumber(MIN_PERL) then
    ok(("perl version %s (>= %s required)"):format(version, MIN_PERL))
  else
    report_error(("perl version %s is older than the required %s"):format(version, MIN_PERL))
  end
end

local function check_helper()
  local path = helper.path()
  if vim.fn.filereadable(path) == 1 then
    ok(("bundled helper found: %s"):format(path))
  else
    report_error(("bundled helper missing: %s"):format(path), {
      "Reinstall the plugin; the `perl/` directory must ship alongside `lua/`.",
    })
  end
end

local function check_parser()
  if pcall(vim.treesitter.get_string_parser, "", "perl") then
    ok("tree-sitter perl parser is installed")
  else
    warn("tree-sitter perl parser is not installed", {
      "Subtests will not be discovered; only whole files will be shown.",
      "Install it with `:TSInstall perl` (nvim-treesitter).",
    })
  end
end

function M.check()
  start("neotest-prove")

  if not pcall(require, "neotest") then
    report_error("neotest is not installed", { "Install nvim-neotest/neotest." })
  else
    ok("neotest is installed")
  end

  check_helper()
  check_parser()

  local configs = registered_configs()
  for index, cfg in ipairs(configs) do
    if #configs > 1 then
      info(("adapter configuration %d of %d"):format(index, #configs))
    end
    check_command("prove_command", cfg.prove_command)
    if check_command("perl_command", cfg.perl_command) then
      check_perl_version(cfg.perl_command)
    end
  end
end

return M
