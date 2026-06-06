local M = {}

---@type string|nil cached backend command (without %s)
local backend = nil

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
    vim.notify("faaah.nvim: unknown backend: " .. backend_name, vim.log.levels.ERROR)
    return nil
  end
end

---Resolve the sound path to an absolute filesystem path.
---If user provides a path, expand it (handles ~/).
---If nil, resolve the bundled default.mp3 relative to this file.
---@param user_path? string
---@return string|nil absolute path, or nil if not resolvable
local function resolve_sound_path(user_path)
  if user_path then
    return vim.fn.expand(user_path)
  end

  -- Resolve bundled default.mp3
  -- sound.lua lives in lua/faaah/sound.lua
  -- default.mp3 is at sounds/default.mp3 relative to plugin root
  local source = debug.getinfo(1, "S").source
  -- source format: @/path/to/lua/faaah/sound.lua
  local sound_lua_path = source:sub(2) -- strip leading @
  -- Walk up: sound.lua -> faaah -> lua -> plugin_root
  local plugin_root = vim.fn.fnamemodify(sound_lua_path, ":h:h:h:h")
  local default_path = vim.fn.resolve(plugin_root .. "/sounds/default.mp3")

  if vim.fn.filereadable(default_path) == 1 then
    return default_path
  end

  vim.notify("faaah.nvim: bundled sound not found at " .. default_path, vim.log.levels.WARN)
  return nil
end

---Play a sound file asynchronously.
---@param path string absolute path to sound file
---@param play_cmd? string user override for play command template
---@return boolean true if spawned successfully
function M.play(path, play_cmd)
  if not backend then
    backend = detect_backend()
    if not backend then
      vim.notify(
        "faaah.nvim: no audio backend found. Install ffplay or mpv.",
        vim.log.levels.ERROR
      )
      return false
    end
  end

  local resolved = resolve_sound_path(path)
  if not resolved then
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
      vim.notify(
        "faaah.nvim: audio process exited with code=" .. tostring(code) .. " signal=" .. tostring(signal),
        vim.log.levels.WARN
      )
    end
    if handle and not handle:is_closing() then
      handle:close()
    end
  end)

  if not handle then
    vim.notify(
      "faaah.nvim: failed to spawn " .. cmd .. ": " .. (spawn_err or "unknown error"),
      vim.log.levels.ERROR
    )
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
