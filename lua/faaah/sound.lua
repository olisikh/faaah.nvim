local M = {}

local log = require("faaah.log")

---@type string|nil cached backend command (without %s)
local backend = nil

---@type string|nil runtime sound override applied to every play() call
local runtime_sound = nil

---@return string absolute plugin root path
local function plugin_root()
  local source = debug.getinfo(1, "S").source
  local sound_lua_path = source:sub(2) -- strip leading @
  return vim.fn.fnamemodify(sound_lua_path, ":h:h:h")
end

---@param path string
---@return boolean
local function is_external_path(path)
  return path:match("^/") ~= nil or path:match("^~[/\\]") ~= nil
end

---Auto-detect the best available audio backend.
---Order: afplay (macOS), ffplay, mpv
---@return string|nil backend name, or nil if none found
local function detect_backend()
  -- macOS built-in
  if vim.fn.executable("afplay") == 1 then
    return "afplay"
  end
  if vim.fn.executable("ffplay") == 1 then
    return "ffplay"
  end
  if vim.fn.executable("mpv") == 1 then
    return "mpv"
  end
  return nil
end

---Build command args list from a backend name and sound path.
---@param backend_name string
---@param sound_path string
---@return string[] cmd + args
local function build_cmd(backend_name, sound_path)
  if backend_name == "afplay" then
    return { "afplay", sound_path }
  elseif backend_name == "ffplay" then
    return { "ffplay", "-nodisp", "-autoexit", sound_path }
  elseif backend_name == "mpv" then
    return { "mpv", "--no-video", "--really-quiet", sound_path }
  else
    log.error("unknown backend: " .. backend_name)
    return nil
  end
end

---Resolve the sound path to an absolute filesystem path.
---If user provides an absolute or ~/ path, expand it.
---Otherwise, resolve it relative to the plugin's sounds/ directory.
---If nil, resolve the bundled default.mp3 relative to this file.
---@param user_path? string
---@return string|nil absolute path, or nil if not resolvable
local function resolve_sound_path(user_path)
  if user_path then
    if is_external_path(user_path) then
      return vim.fn.expand(user_path)
    end

    local plugin_sound_path = plugin_root() .. "/sounds/" .. user_path
    return vim.fn.fnamemodify(plugin_sound_path, ":p")
  end

  -- Resolve bundled default.mp3
  -- sound.lua lives in lua/faaah/sound.lua
  -- default.mp3 is at sounds/default.mp3 relative to plugin root
  local default_path = vim.fn.fnamemodify(plugin_root() .. "/sounds/default.mp3", ":p")

  if vim.fn.filereadable(default_path) == 1 then
    return default_path
  end

  log.warn("bundled sound not found at " .. default_path)
  return nil
end

---Return the bundled sound filenames available for completion.
---@return string[]
function M.list_sounds()
  local dir = plugin_root() .. "/sounds"
  local ok, entries = pcall(vim.fn.readdir, dir)
  if not ok or not entries then
    return {}
  end

  return vim.tbl_filter(function(name)
    local full = dir .. "/" .. name
    return vim.fn.isdirectory(full) == 0
  end, entries)
end

---Set a runtime sound override.
---Takes precedence over configured and per-source sounds until cleared.
---@param name_or_path string bundled name (e.g. "oof.mp3") or absolute/~/ path
function M.set_runtime_sound(name_or_path)
  runtime_sound = name_or_path
end

---Get the current runtime sound override, if any.
---@return string|nil
function M.get_runtime_sound()
  return runtime_sound
end

---Clear any runtime sound override.
function M.clear_runtime_sound()
  runtime_sound = nil
end

---Play a sound file asynchronously.
---If a runtime override is set, it takes precedence over `path`.
---@param path string absolute path to sound file
---@param play_cmd? string user override for play command template
---@return boolean true if spawned successfully
function M.play(path, play_cmd)
  if not backend then
    backend = detect_backend()
    if not backend then
      log.error("no audio backend found. Install ffplay or mpv.")
      return false
    end
  end

  local active_path = runtime_sound or path
  local resolved = resolve_sound_path(active_path)
  if not resolved then
    log.warn("could not resolve sound path" .. (active_path and (" for: " .. active_path) or ""))
    return false
  end

  local cmd, args
  if play_cmd then
    -- User override: replace %s with resolved path
    local cmd_str = play_cmd:gsub("%%s", resolved)
    -- split on spaces for spawn
    local parts = {}
    for part in cmd_str:gmatch("%S+") do
      parts[#parts + 1] = part
    end
    cmd = parts[1]
    args = {}
    for i = 2, #parts do
      args[i - 1] = parts[i]
    end
  else
    local built = build_cmd(backend, resolved)
    if not built then
      return false
    end
    cmd = built[1]
    args = { select(2, unpack(built)) }
  end

  -- Async spawn, non-blocking
  local handle
  local spawn_err
  handle, spawn_err = vim.loop.spawn(cmd, {
    args = args,
    stdio = { nil, nil, nil },
  }, function(code, signal)
    if code ~= 0 or signal ~= 0 then
      log.warn("audio process exited with code=" .. tostring(code) .. " signal=" .. tostring(signal))
    end
    if handle and not handle:is_closing() then
      handle:close()
    end
  end)

  if not handle then
    log.error("failed to spawn " .. cmd .. ": " .. (spawn_err or "unknown error"))
    return false
  end

  return true
end

---Get the resolved path for the default sound.
---Useful for external use (e.g. play() with no args).
---@return string|nil
function M.default_sound_path()
  return resolve_sound_path(nil)
end

return M
