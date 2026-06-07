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
