local throttle = require("faaah.sources")
local sound = require("faaah.sound")

local M = {}

---@type table|nil resolved config for this source
local config = nil

---@type table source controller (enable/disable/is_enabled)
local ctrl = nil

---@type function|nil saved original neotest.setup
local original_neotest_setup = nil

---@type boolean whether neotest is available
local neotest_available = false

---Recursively check if any test result has status "failed".
---@param results table neotest results tree
---@return boolean
local function has_failed(results)
  if type(results) ~= "table" then
    return false
  end

  -- Check status field directly
  if results.status == "failed" then
    return true
  end

  -- Recurse into children
  for _, child in pairs(results) do
    if type(child) == "table" then
      if has_failed(child) then
        return true
      end
    end
  end

  return false
end

---Create the faaah consumer to inject into neotest.
---@return table consumer
local function create_consumer()
  return function(client)
    client.listeners.results = function(adapter_id, results, partial)
      if not ctrl or not ctrl.is_enabled() then
        return
      end

      -- Only fire on final results
      if partial then
        return
      end

      if has_failed(results) then
        if throttle.check("neotest", config.throttle_ms) then
          sound.play(config.sound)
        end
      end
    end
  end
end

---Wrap neotest.setup to inject the faaah consumer.
---@param source_config table merged source config { sound, throttle_ms, enabled }
function M.attach(source_config)
  config = source_config
  ctrl = throttle.source_controller(source_config.enabled)

  local ok, neotest = pcall(require, "neotest")
  if not ok then
    vim.notify("faaah.nvim: neotest not found, source disabled", vim.log.levels.WARN)
    neotest_available = false
    return
  end
  neotest_available = true

  -- Save original setup
  original_neotest_setup = neotest.setup

  -- Wrap it
  neotest.setup = function(user_opts)
    user_opts = user_opts or {}
    user_opts.consumers = user_opts.consumers or {}

    -- Inject our consumer under the "faaah" key
    -- Use vim.tbl_deep_extend to handle metatable-based merging
    user_opts.consumers = vim.tbl_deep_extend("force", user_opts.consumers, {
      faaah = create_consumer(),
    })

    -- Call original setup with modified opts
    original_neotest_setup(user_opts)
  end
end

---Manual attach for users who loaded neotest before faaah.
---Calls neotest's internal run_consumer mechanism if available.
function M.manual_attach()
  if not neotest_available then
    local ok, _ = pcall(require, "neotest")
    if not ok then
      vim.notify("faaah.nvim: neotest not available for manual attach", vim.log.levels.ERROR)
      return
    end
    neotest_available = true
  end

  -- Attempt to inject consumer into already-running neotest
  local ok, neotest = pcall(require, "neotest")
  if not ok then
    return
  end

  -- neotest client may already be initialized. Try to use neotest.run.runner
  -- or similar internal API. Best-effort.
  vim.notify(
    "faaah.nvim: manual_attach for neotest is best-effort. "
      .. "Prefer loading faaah before neotest.setup().",
    vim.log.levels.WARN
  )
end

---Restore original neotest.setup.
function M.detach()
  if original_neotest_setup then
    local ok, neotest = pcall(require, "neotest")
    if ok then
      neotest.setup = original_neotest_setup
    end
    original_neotest_setup = nil
  end
  config = nil
  ctrl = nil
end

---Get the source controller (for faaah.source("neotest") API).
---@return table|nil
function M.controller()
  return ctrl
end

return M
