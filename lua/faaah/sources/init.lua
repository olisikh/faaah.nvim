local M = {}

---Per-source throttle state.
---Keyed by source name (e.g. "diagnostics", "neotest", "notifications").
---@type table<string, number> last play timestamp in ms (vim.loop.now())
local last_play = {}

---Check whether a sound should be allowed to play for the given source.
---@param name string source name
---@param throttle_ms number cooldown in ms; 0 = no throttle
---@return boolean true if play is allowed
function M.check(name, throttle_ms)
  if throttle_ms == 0 then
    return true
  end

  local now = vim.loop.now()
  local last = last_play[name] or 0
  if now - last >= throttle_ms then
    last_play[name] = now
    return true
  end

  return false
end

---Source lifecycle helpers.
---Creates a source object with enable/disable/is_enabled methods.
---@param default_enabled boolean initial enabled state from config
---@return table source controller
function M.source_controller(default_enabled)
  local enabled = default_enabled

  return {
    enable = function()
      enabled = true
    end,
    disable = function()
      enabled = false
    end,
    is_enabled = function()
      return enabled
    end,
  }
end

return M
