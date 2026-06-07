local config_mod = require("faaah.config")
local sound = require("faaah.sound")
local log = require("faaah.log")

local M = {}

---@type table|nil frozen config snapshot
local _config = nil

---@type table<string, table> source modules by name
local source_modules = {
	diagnostics = require("faaah.sources.diagnostics"),
	neotest = require("faaah.sources.neotest"),
	notifications = require("faaah.sources.notifications"),
}

---@type table<string, boolean> whether each source is attached
local attached = {}

---Setup faaah with user options.
---Merges user config with defaults, validates, attaches enabled sources.
---Re-running setup() detaches all sources first (safe to call multiple times).
---@param user_opts? table
function M.setup(user_opts)
	-- Detach everything from previous setup call
	for name, mod in pairs(source_modules) do
		if attached[name] then
			mod.detach()
			attached[name] = false
		end
	end

	-- Resolve and validate config
	local cfg = config_mod.resolve(user_opts)
	if not cfg then
		return -- validation error already notified
	end
	_config = cfg

	-- Attach enabled sources
	local enabled_sources = {}
	for name, mod in pairs(source_modules) do
		local src_cfg = cfg.sources[name]
		if src_cfg and src_cfg.enabled then
			mod.attach(src_cfg)
			attached[name] = true
			enabled_sources[#enabled_sources + 1] = name
		end
	end

	log.info("setup complete. Sources: " .. table.concat(enabled_sources, ", "))

	-- Register user commands
	local function faaah_cmd(args)
		local sub = args.args
		if sub == "enable" then
			M.enable()
		elseif sub == "disable" then
			M.disable()
		elseif sub == "toggle" then
			if M.is_enabled() then
				M.disable()
			else
				M.enable()
			end
		elseif sub == "play" then
			M.play()
		else
			log.warn("unknown command: " .. tostring(sub) .. ". Valid: enable, disable, toggle, play")
		end
	end

	vim.api.nvim_create_user_command("Faah", faaah_cmd, {
		nargs = "?",
		complete = function()
			return { "enable", "disable", "toggle", "play" }
		end,
		desc = "faaah.nvim: control error sounds (enable/disable/toggle/play)",
		force = true,
	})
end

---Get the runtime controller for a source (enable/disable/is_enabled).
---@param name string source name: "diagnostics", "neotest", "notifications"
---@return table|nil controller with :enable(), :disable(), :is_enabled()
function M.source(name)
	local mod = source_modules[name]
	if not mod then
		log.error("unknown source: " .. name)
		return nil
	end

	local ctrl = mod.controller()
	if not ctrl then
		log.warn("source '" .. name .. "' not attached. Run setup() first.")
		return nil
	end

	return ctrl
end

---@type table<string, boolean>|nil saved enabled states for global re-enable
local _saved_enabled = nil

---Disable all sources globally (mute).
---Remembers which sources were enabled so enable() can restore.
function M.disable()
  if _saved_enabled then
    return -- already disabled
  end
  _saved_enabled = {}
  for name, mod in pairs(source_modules) do
    local ctrl = mod.controller()
    if ctrl and ctrl.is_enabled() then
      _saved_enabled[name] = true
      ctrl.disable()
    end
  end
  log.info("disabled globally")
end

---Re-enable all sources that were active before disable().
function M.enable()
  if not _saved_enabled then
    return -- not disabled
  end
  for name, _ in pairs(_saved_enabled) do
    local mod = source_modules[name]
    if mod then
      local ctrl = mod.controller()
      if ctrl then
        ctrl.enable()
      end
    end
  end
  _saved_enabled = nil
  log.info("enabled globally")
end

---Check whether the plugin is globally enabled (not muted).
---@return boolean
function M.is_enabled()
  return _saved_enabled == nil
end

---Raw source modules for advanced use (e.g. manual_attach).
---@type table<string, table>
M.sources = source_modules

---Logger module (set_level, set_path).
---@type table
M.log = log

---Play a sound manually.
---Uses the configured play_cmd from setup() if set, otherwise auto-detect.
---@param path? string absolute or ~ path to sound file; nil = use configured default
function M.play(path)
	local resolved_path = path
	if not resolved_path and _config then
		resolved_path = _config.defaults.sound
	end
	if not resolved_path then
		resolved_path = sound.default_sound_path()
		if not resolved_path then
			log.error("no sound path configured and default not found")
			return
		end
	end

	local play_cmd = _config and _config.play_cmd or nil
	sound.play(resolved_path, play_cmd)
end

return M
