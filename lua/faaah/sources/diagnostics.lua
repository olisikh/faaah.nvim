local throttle = require("faaah.sources")
local sound = require("faaah.sound")
local log = require("faaah.log")

local M = {}

---@type table|nil resolved config for this source
local config = nil

---@type table source controller (enable/disable/is_enabled)
local ctrl = nil

---Per-buffer error count state.
---@type table<integer, integer> bufnr -> error count
local buf_error_counts = {}

---Per-buffer initialization state. Prevent firing on first diagnostic load.
---@type table<integer, boolean>
local buf_initialized = {}

---@type integer|nil autocommand group id
local augroup = nil

---Count ERROR severity diagnostics in a list.
---@param diagnostics table[]
---@return integer
local function count_errors(diagnostics)
  local count = 0
  for _, d in ipairs(diagnostics) do
    if d.severity == vim.diagnostic.severity.ERROR then
      count = count + 1
    end
  end
  return count
end

---Start listening to DiagnosticChanged events.
---@param source_config table merged source config { sound, throttle_ms, enabled }
function M.attach(source_config)
  -- Clear previous state in case of re-attach
  M.detach()

  config = source_config
  ctrl = throttle.source_controller(source_config.enabled)

  augroup = vim.api.nvim_create_augroup("faaah_diagnostics", { clear = true })

  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = augroup,
    callback = function(ev)
      -- DEBUG: verify autocmd fires
      local new_count = count_errors(ev.data.diagnostics or {})
      local total = ev.data.diagnostics and #ev.data.diagnostics or 0
      log.debug("buf=" .. ev.buf .. " total=" .. total .. " errors=" .. new_count)

      if not ctrl or not ctrl.is_enabled() then
        log.warn("source disabled or ctrl nil")
        return
      end

      local bufnr = ev.buf

      -- Seed baseline on first event without triggering sound.
      -- Prevents firing on initial buffer load or entering Insert mode.
      if not buf_initialized[bufnr] then
        buf_error_counts[bufnr] = new_count
        buf_initialized[bufnr] = true
        return
      end

      -- Don't play sound while actively editing in Insert mode.
      -- Sound will fire on next DiagnosticChanged after returning to Normal mode.
      if vim.api.nvim_get_mode().mode == "i" then
        return
      end

      local old_count = buf_error_counts[bufnr] or 0

      -- Only trigger if error count increased
      if new_count > old_count then
        log.debug("increase " .. old_count .. "->" .. new_count .. " throttle=" .. config.throttle_ms)
        if throttle.check("diagnostics", config.throttle_ms) then
          log.debug("playing sound: " .. tostring(config.sound or "default"))
          sound.play(config.sound)
        else
          log.debug("throttled")
        end
      end

      buf_error_counts[bufnr] = new_count
    end,
  })
end

---Stop listening and clean up state.
function M.detach()
  if augroup then
    pcall(vim.api.nvim_del_augroup_by_id, augroup)
    augroup = nil
  end
  buf_error_counts = {}
  buf_initialized = {}
  config = nil
  ctrl = nil
end

---Get the source controller (for faaah.source("diagnostics") API).
---@return table|nil
function M.controller()
  return ctrl
end

return M
