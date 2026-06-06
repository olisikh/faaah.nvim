local throttle = require("faaah.sources")
local sound = require("faaah.sound")

local M = {}

---@type table|nil resolved config for this source
local config = nil

---@type table source controller (enable/disable/is_enabled)
local ctrl = nil

---Per-buffer error count state.
---@type table<integer, integer> bufnr -> error count
local buf_error_counts = {}

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
  config = source_config
  ctrl = throttle.source_controller(source_config.enabled)

  -- Clear previous state in case of re-attach
  M.detach()

  augroup = vim.api.nvim_create_augroup("faaah_diagnostics", { clear = true })

  vim.api.nvim_create_autocmd("DiagnosticChanged", {
    group = augroup,
    callback = function(ev)
      if not ctrl.is_enabled() then
        return
      end

      -- Count current ERROR diagnostics for this buffer
      local new_count = count_errors(ev.data.diagnostics or {})
      local bufnr = ev.buf
      local old_count = buf_error_counts[bufnr] or 0

      -- Only trigger if error count increased
      if new_count > old_count then
        if throttle.check("diagnostics", config.throttle_ms) then
          sound.play(config.sound)
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
  config = nil
  ctrl = nil
end

---Get the source controller (for faaah.source("diagnostics") API).
---@return table|nil
function M.controller()
  return ctrl
end

return M
