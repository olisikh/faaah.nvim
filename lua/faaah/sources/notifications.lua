local throttle = require("faaah.sources")
local sound = require("faaah.sound")

local M = {}

---@type table|nil resolved config for this source
local config = nil

---@type table source controller (enable/disable/is_enabled)
local ctrl = nil

---@type function|nil saved original vim.notify
local original_notify = nil

---Wrapper around vim.notify that intercepts ERROR-level messages.
---Calls the original vim.notify unconditionally (chain, never suppress).
---@param msg string
---@param level integer
---@param opts? table
local function notify_wrapper(msg, level, opts)
  -- Always chain to original — never suppress
  if original_notify then
    original_notify(msg, level, opts)
  end

  -- Check if we should fire
  if not ctrl or not ctrl.is_enabled() then
    return
  end

  if level == vim.log.levels.ERROR then
    if throttle.check("notifications", config.throttle_ms) then
      sound.play(config.sound)
    end
  end
end

---Attach by wrapping vim.notify.
---@param source_config table merged source config { sound, throttle_ms, enabled }
function M.attach(source_config)
  config = source_config
  ctrl = throttle.source_controller(source_config.enabled)

  -- Save original and replace
  original_notify = vim.notify
  vim.notify = notify_wrapper
end

---Restore original vim.notify.
function M.detach()
  if original_notify then
    vim.notify = original_notify
    original_notify = nil
  end
  config = nil
  ctrl = nil
end

---Get the source controller (for faaah.source("notifications") API).
---@return table|nil
function M.controller()
  return ctrl
end

return M
