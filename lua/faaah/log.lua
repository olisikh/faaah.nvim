local M = {}

---@type table<string, integer> log level values
local LEVELS = {
  debug = 0,
  info = 1,
  warn = 2,
  error = 3,
}

---@type integer current log level; messages below this are suppressed
local current_level = LEVELS.info

---@type string|nil path to log file, resolved lazily on first write
local log_path = nil

---Resolve the log file path.
---Uses Neovim's standard data directory.
---@return string
local function get_log_path()
  if not log_path then
    log_path = vim.fn.stdpath("data") .. "/faaah.log"
  end
  return log_path
end

---Override the log file path.
---@param path string
function M.set_path(path)
  log_path = vim.fn.expand(path)
end

---Set the minimum log level. Messages below this are suppressed.
---@param level string "debug", "info", "warn", "error"
function M.set_level(level)
  if LEVELS[level] then
    current_level = LEVELS[level]
  end
end

---Get the current log level name.
---@return string
function M.get_level()
  for name, val in pairs(LEVELS) do
    if val == current_level then
      return name
    end
  end
  return "info"
end

---Format and write a log entry to file.
---@param level_name string
---@param msg string
local function write_entry(level_name, msg)
  local path = get_log_path()
  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local line = string.format("[%s] %-5s %s\n", timestamp, level_name:upper(), msg)

  local fd = vim.loop.fs_open(path, "a", 438) -- 438 = 0666 octal
  if not fd then
    return
  end
  vim.loop.fs_write(fd, line, -1)
  vim.loop.fs_close(fd)
end

---Log a debug message.
---@param msg string
function M.debug(msg)
  if current_level <= LEVELS.debug then
    write_entry("debug", msg)
  end
end

---Log an info message.
---@param msg string
function M.info(msg)
  if current_level <= LEVELS.info then
    write_entry("info", msg)
  end
end

---Log a warning message.
---@param msg string
function M.warn(msg)
  if current_level <= LEVELS.warn then
    write_entry("warn", msg)
  end
end

---Log an error message (always written to file).
---@param msg string
function M.error(msg)
  write_entry("error", msg)
end

return M
