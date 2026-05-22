local config = require("neotest-prove.config")

local DEFAULT_ROOT_FILES = { "cpanfile", "Makefile.PL", "Build.PL", "dist.ini", ".git" }

describe("config.merge", function()
  it("returns the defaults when given nil", function()
    local c = config.merge(nil)
    assert.equals("prove", c.prove_command)
    assert.equals("perl", c.perl_command)
    assert.is_false(c.include_xt)
    assert.same(DEFAULT_ROOT_FILES, c.root_files)
    assert.same({}, c.prove_args)
    assert.same({}, c.extra_filter_dirs)
  end)

  it("overrides a scalar option", function()
    local c = config.merge({ prove_command = { "carton", "exec", "prove" } })
    assert.same({ "carton", "exec", "prove" }, c.prove_command)
    assert.equals("perl", c.perl_command)
  end)

  it("overrides include_xt", function()
    assert.is_true(config.merge({ include_xt = true }).include_xt)
  end)

  it("replaces root_files wholesale rather than deep-merging", function()
    assert.same({ ".git" }, config.merge({ root_files = { ".git" } }).root_files)
  end)

  it("preserves unspecified defaults", function()
    local c = config.merge({ prove_args = { "-l" } })
    assert.same({ "-l" }, c.prove_args)
    assert.equals("perl", c.perl_command)
    assert.is_false(c.include_xt)
  end)

  it("raises on a non-table config", function()
    assert.has_error(function()
      config.merge("prove")
    end)
  end)

  it("does not mutate the defaults across calls", function()
    local first = config.merge({ root_files = { "only-this" } })
    assert.same({ "only-this" }, first.root_files)
    assert.same(DEFAULT_ROOT_FILES, config.merge(nil).root_files)
  end)
end)
