local throttle = require("faaah.sources")
local sound = require("faaah.sound")
local log = require("faaah.log")

local M = {}

---@type table|nil resolved config for this source
local config = nil

---@type table source controller (enable/disable/is_enabled)
local ctrl = nil

---@type function|nil saved original vim.notify
local original_notify = nil

---Default ignore patterns. Many plugins use ERROR level for non-errors.
---These Lua patterns are matched against the notification message.
---@type string[]
local default_ignore_patterns = {
  -- LSP "no X available" noise
  "No code actions available",
  "No information available",
  "No hover information",
  "No signature help available",
  "No documentation available",
  -- LSP "no X found" — references, definitions, etc
  "No .- found",
  "No .- available",
  "Not found",
  -- LSP client lifecycle noise
  "Client .- quit",
  "Client .- stopped",
  "Client .- failed",
  "Server .- failed",
  "Server .- quit",
  "method .- not supported",
  "Request .- failed",
  "LSP[%w]*: .- exit",
  -- Treesitter
  "No parser for",
  "treesitter .- error",
  "Error in decoration provider",
  -- Completion / snippets
  "No completion found",
  "No snippet found",
  "snippet .- not found",
  -- General non-error noise
  "^%s*$",                     -- blank messages
  "^-+$",                       -- separator lines
  "cancelled$",                 -- user cancelled
  "cancelled%.$",
  "aborted$",
  "interrupted$",
}

---Check if a message should be ignored based on patterns.
---@param msg string
---@param patterns string[]
---@return boolean
local function should_ignore(msg, patterns)
  for _, pattern in ipairs(patterns) do
    if msg:find(pattern) then
      return true
    end
  end
  return false
end

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
    -- Merge built-in defaults with user patterns (additive)
    local user_patterns = config.ignore_patterns or {}
    local patterns = {}
    for _, p in ipairs(default_ignore_patterns) do
      patterns[#patterns + 1] = p
    end
    for _, p in ipairs(user_patterns) do
      patterns[#patterns + 1] = p
    end
    if type(msg) == "string" and should_ignore(msg, patterns) then
      return
    end
    log.debug("notification error: " .. tostring(msg):sub(1, 200))
    if throttle.check("notifications", config.throttle_ms) then
      sound.play(config.sound)
    end
  end
end

---Attach by wrapping vim.notify.
---@param source_config table merged source config { sound, throttle_ms, enabled }
function M.attach(source_config)
  M.detach()

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
