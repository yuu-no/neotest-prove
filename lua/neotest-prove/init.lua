local lib = require("neotest.lib")
local logger = require("neotest.logging")
local Tree = require("neotest.types").Tree

local config = require("neotest-prove.config")
local query = require("neotest-prove.query")

local unpack = table.unpack or unpack

-- Directory names always excluded from test discovery.
local EXCLUDED_DIRS = { ".git", "blib", "local", "_build", ".build" }

-- Neovim's builtin `.t` filetype detection falls back to the fictitious
-- "tads" filetype for absolute paths (its `t/`/`xt/` fast-path is a literal
-- string match on the dirname, which never holds for absolute paths), so
-- treesitter discovery would otherwise always fail for this extension.
-- Force it to `perl` in both the main process and, once started, the
-- neotest treesitter subprocess (which loads no user config of its own).
local FT_PATCH = { extension = { t = "perl" } }
local main_patched, child_patched = false, false

local function ensure_perl_filetype()
  if not main_patched then
    main_patched = true
    vim.filetype.add(FT_PATCH)
  end
  if not child_patched and lib.subprocess.enabled() then
    child_patched = pcall(
      lib.subprocess.request,
      "nvim_exec_lua",
      "return vim.filetype.add(...)",
      { FT_PATCH }
    )
  end
end

--- Normalise a configured command into an argument list.
--- A string is split on whitespace; a list is copied as-is.
---@param command string|string[]
---@return string[]
local function normalise_command(command)
  if type(command) == "table" then
    return vim.deepcopy(command)
  end
  return vim.split(command, "%s+", { trimempty = true })
end

local _helper_path
--- Resolve the bundled Perl helper script of this plugin.
---@return string
local function plugin_helper_path()
  if _helper_path then
    return _helper_path
  end
  local matches = vim.api.nvim_get_runtime_file("perl/neotest-prove-runner.pl", true)
  for _, path in ipairs(matches) do
    if path:match("neotest%-prove") then
      _helper_path = path
      return _helper_path
    end
  end
  error("neotest-prove: could not locate the bundled Perl helper on runtimepath")
end

--- Build a minimal tree containing only the file position.
--- Used as a fallback when treesitter parsing is unavailable.
---@param file_path string
---@return neotest.Tree
local function file_only_tree(file_path)
  local line_count = 0
  local handle = io.open(file_path, "r")
  if handle then
    for _ in handle:lines() do
      line_count = line_count + 1
    end
    handle:close()
  end
  return Tree.from_list({
    {
      id = file_path,
      type = "file",
      name = vim.fn.fnamemodify(file_path, ":t"),
      path = file_path,
      range = { 0, 0, line_count, 0 },
    },
  }, function(pos)
    return pos.id
  end)
end

--- Collect the distinct `.t` files referenced by a position tree.
---@param tree neotest.Tree
---@return string[]
local function collect_test_files(tree)
  local seen, files = {}, {}
  for _, pos in tree:iter() do
    if pos.type ~= "dir" and pos.path and not seen[pos.path] then
      seen[pos.path] = true
      files[#files + 1] = pos.path
    end
  end
  return files
end

--- Convert helper-reported errors into neotest.Error values.
--- TAP line numbers are 1-indexed; neotest expects 0-indexed.
---@param errors table[]|nil
---@return neotest.Error[]|nil
local function convert_errors(errors)
  if type(errors) ~= "table" or #errors == 0 then
    return nil
  end
  local converted = {}
  for _, err in ipairs(errors) do
    converted[#converted + 1] = {
      message = err.message,
      line = type(err.line) == "number" and math.max(err.line - 1, 0) or nil,
    }
  end
  return converted
end

--- Create a neotest adapter bound to the given configuration.
---@param opts neotest-prove.Config
---@return neotest.Adapter
local function create_adapter(opts)
  ---@type neotest.Adapter
  local adapter = { name = "neotest-prove" }

  adapter.root = lib.files.match_root_pattern(unpack(opts.root_files))

  ---@param file_path string
  ---@return boolean
  function adapter.is_test_file(file_path)
    return type(file_path) == "string" and vim.endswith(file_path, ".t")
  end

  ---@param name string
  ---@return boolean
  function adapter.filter_dir(name, _, _)
    if not opts.include_xt and name == "xt" then
      return false
    end
    if vim.tbl_contains(EXCLUDED_DIRS, name) then
      return false
    end
    if vim.tbl_contains(opts.extra_filter_dirs, name) then
      return false
    end
    return true
  end

  ---@async
  ---@param file_path string
  ---@return neotest.Tree
  function adapter.discover_positions(file_path)
    ensure_perl_filetype()
    -- Subtests are emitted as `test` positions; `nested_tests` keeps subtests
    -- nested inside other subtests.
    local ok, tree =
      pcall(lib.treesitter.parse_positions, file_path, query, { nested_tests = true })
    if ok then
      return tree
    end
    logger.warn(
      ("neotest-prove: falling back to file-level discovery for %s"):format(file_path),
      tree
    )
    return file_only_tree(file_path)
  end

  ---@param args neotest.RunArgs
  ---@return neotest.RunSpec | nil
  function adapter.build_spec(args)
    local tree = args.tree
    if not tree then
      return nil
    end

    local files = collect_test_files(tree)
    if #files == 0 then
      return nil
    end

    local results_path = vim.fn.tempname()
    local root = adapter.root(tree:data().path) or vim.fn.getcwd()

    -- The bundled Perl helper runs `prove`, captures the raw per-file TAP it
    -- dumps, and writes structured results as JSON to `results_path`.
    local command = normalise_command(opts.perl_command)
    table.insert(command, plugin_helper_path())
    vim.list_extend(command, { "--results", results_path, "--" })
    vim.list_extend(command, normalise_command(opts.prove_command))
    table.insert(command, "--merge")
    vim.list_extend(command, opts.prove_args)
    vim.list_extend(command, args.extra_args or {})
    vim.list_extend(command, files)

    return {
      command = command,
      cwd = root,
      context = { results_path = results_path },
    }
  end

  ---@async
  ---@param spec neotest.RunSpec
  ---@param _result neotest.StrategyResult
  ---@param _tree neotest.Tree
  ---@return table<string, neotest.Result>
  function adapter.results(spec, _result, _tree)
    local results_path = spec.context and spec.context.results_path
    if not results_path or vim.fn.filereadable(results_path) == 0 then
      return {}
    end

    local read_ok, content = pcall(lib.files.read, results_path)
    if not read_ok then
      return {}
    end

    local decoded_ok, decoded = pcall(vim.json.decode, content)
    if not decoded_ok or type(decoded) ~= "table" or type(decoded.files) ~= "table" then
      logger.warn("neotest-prove: could not decode results file", results_path)
      return {}
    end

    local results = {}
    for file_path, file_result in pairs(decoded.files) do
      results[file_path] = {
        status = file_result.status,
        errors = convert_errors(file_result.errors),
      }
      if type(file_result.subtests) == "table" then
        for subtest_name, subtest_result in pairs(file_result.subtests) do
          results[file_path .. "::" .. subtest_name] = {
            status = subtest_result.status,
            errors = convert_errors(subtest_result.errors),
          }
        end
      end
    end
    return results
  end

  return adapter
end

local PerlProveAdapter = create_adapter(config.merge(nil))

return setmetatable(PerlProveAdapter, {
  ---@param user_config? neotest-prove.Config
  ---@return neotest.Adapter
  __call = function(_, user_config)
    return create_adapter(config.merge(user_config))
  end,
})
