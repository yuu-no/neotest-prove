-- Runs the health check with vim.health's reporters stubbed, so the report
-- can be inspected without depending on how `:checkhealth` renders it (which
-- became asynchronous in recent Neovim versions).
local function capture_report()
  local lines, saved = {}, {}
  for _, name in ipairs({ "start", "ok", "warn", "error", "info" }) do
    saved[name] = vim.health[name]
    vim.health[name] = function(msg)
      lines[#lines + 1] = name .. ": " .. msg
    end
  end
  local check_ok, err = pcall(require("neotest-prove.health").check)
  for name, fn in pairs(saved) do
    vim.health[name] = fn
  end
  assert(check_ok, err)
  return table.concat(lines, "\n")
end

describe("neotest-prove health", function()
  it("reports on the default configuration without neotest.setup", function()
    local report = capture_report()
    assert.is_truthy(report:find("ok: neotest is installed", 1, true))
    assert.is_truthy(report:find("ok: bundled helper found", 1, true))
    assert.is_truthy(report:find("ok: prove_command: `prove` is executable", 1, true))
    assert.is_truthy(report:find("ok: perl version", 1, true))
  end)

  it("reports on the adapters registered with neotest", function()
    require("neotest").setup({
      adapters = {
        require("neotest-prove")({ prove_command = "neotest-prove-no-such-binary" }),
      },
    })
    local report = capture_report()
    assert.is_truthy(
      report:find("error: prove_command: `neotest-prove-no-such-binary` is not executable", 1, true)
    )
  end)
end)
