local M = {}

local defaults = {
  defaults = {
    sound = nil,
    throttle_ms = 2000,
  },
  sources = {
    diagnostics = { enabled = true },
    neotest = { enabled = true },
    notifications = { enabled = true },
  },
  play_cmd = nil,
}

---Validate user config at a high level.
---Only checks types of top-level keys; per-source validation happens during merge.
---@param opts table
---@return string|nil error message, or nil if valid
local function validate(opts)
  if type(opts) ~= "table" then
    return "faaah.setup expects a table"
  end

  if opts.defaults and type(opts.defaults) ~= "table" then
    return "faaah.setup: defaults must be a table"
  end

  if opts.defaults and opts.defaults.throttle_ms ~= nil and type(opts.defaults.throttle_ms) ~= "number" then
    return "faaah.setup: defaults.throttle_ms must be a number"
  end

  if opts.sources and type(opts.sources) ~= "table" then
    return "faaah.setup: sources must be a table"
  end

  if opts.play_cmd ~= nil and type(opts.play_cmd) ~= "string" then
    return "faaah.setup: play_cmd must be a string or nil"
  end

  for name, src_opts in pairs(opts.sources or {}) do
    if type(src_opts) ~= "table" then
      return "faaah.setup: sources." .. name .. " must be a table"
    end
    if src_opts.throttle_ms ~= nil and type(src_opts.throttle_ms) ~= "number" then
      return "faaah.setup: sources." .. name .. ".throttle_ms must be a number"
    end
    if src_opts.enabled ~= nil and type(src_opts.enabled) ~= "boolean" then
      return "faaah.setup: sources." .. name .. ".enabled must be a boolean"
    end
  end

  return nil
end

---Deep-merge source config with defaults.
---For each key in defaults, if source explicitly sets the key (non-nil), use source value.
---If source sets it to nil, inherit from defaults.
---@param source_opts table|nil source-specific options from user
---@param default_opts table global defaults
---@return table merged config for this source
local function merge_source(source_opts, default_opts)
  local merged = vim.deepcopy(default_opts)
  if not source_opts then
    return merged
  end
  for k, v in pairs(source_opts) do
    if v ~= nil then
      merged[k] = v
    end
    -- if v is nil, keep the default value (already in merged)
  end
  return merged
end

---Resolve user opts into a frozen final config.
---Merges each source with defaults, applies top-level overrides.
---@param user_opts? table
---@return table final config
function M.resolve(user_opts)
  local opts = vim.tbl_deep_extend("force", vim.deepcopy(defaults), user_opts or {})

  local err = validate(opts)
  if err then
    vim.notify("faaah.nvim: " .. err, vim.log.levels.ERROR)
    return nil
  end

  -- Merge each source with defaults
  for name, src_opts in pairs(opts.sources) do
    -- Only known sources: diagnostics, neotest, notifications
    -- Unknown sources silently get defaults + whatever user passed
    opts.sources[name] = merge_source(src_opts, opts.defaults)
  end

  -- Use metatable to make config read-only (frozen snapshot)
  local function readonly(t)
    local proxy = {}
    local mt = {
      __index = t,
      __newindex = function(_, key, _)
        error("faaah config is frozen. Re-run setup() to change settings.", 2)
      end,
      -- NOTE: __pairs unavailable in LuaJIT 5.1 (Neovim).
      -- Iterating the read-only proxy with pairs() yields nothing.
      -- Sources should access config fields directly via the proxy.
    }
    setmetatable(proxy, mt)
    return proxy
  end

  opts.defaults = readonly(opts.defaults)
  for name, src_opts in pairs(opts.sources) do
    opts.sources[name] = readonly(src_opts)
  end
  opts = readonly(opts)

  return opts
end

return M
