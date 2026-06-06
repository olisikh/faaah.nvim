# Handoff: faaah.nvim — Build Phase

**Date:** 2026-06-07
**Context:** Neovim plugin that plays a funny error sound (2s MP3 clip) when errors occur — diagnostics, neotest test failures, vim.notify errors. One plugin, require("faaah").setup(), configurable per source, configurable sound, configurable throttle.

## What Was Decided (Grilled Plan)

### Terminology

| Term | Definition |
|------|-----------|
| **Source** | A category of error event: `diagnostics`, `neotest`, `notifications`. |
| **Throttle** | Cooldown (ms) after sound plays; 0 = no cooldown (cacophony). |
| **Diagnostic error** | LSP diagnostic of `vim.diagnostic.severity.ERROR` arriving via `DiagnosticChanged` autocommand. |
| **Test failure** | Neotest result with status `"failed"` via neotest `results` consumer event. |
| **Notification error** | Any `vim.notify(msg, vim.log.levels.ERROR)` caught by wrapping `vim.notify`. |

### File Structure

```
faaah.nvim/
├── lua/faaah/
│   ├── init.lua              -- setup(opts), source(name), play(path)
│   ├── config.lua            -- defaults, validation, per-source merge
│   ├── sound.lua             -- backend auto-detect, spawn async, default path resolve
│   └── sources/
│       ├── init.lua          -- shared throttle logic, source loader
│       ├── diagnostics.lua   -- DiagnosticChanged hook
│       ├── neotest.lua       -- wrap neotest.setup, inject consumer
│       └── notifications.lua -- wrap vim.notify, chain original
└── sounds/
    └── default.mp3           -- bundled 2s mp3 (copy from ~/Downloads/faaah.mp3)
```

### Config Schema

```lua
require("faaah").setup({
  defaults = {
    sound = nil,         -- nil = bundled default.mp3; string = absolute/~/ path
    throttle_ms = 2000,  -- 0 = none (cacophony)
  },
  sources = {
    diagnostics = {
      enabled = true,
      -- sound, throttle inherit from defaults unless overridden explicitly
    },
    neotest = { enabled = true },
    notifications = { enabled = true },
  },
  play_cmd = nil,  -- nil = auto-detect (afplay/ffplay/mpv); string = template like "mplayer %s"
})
```

Merge logic: each source field inherits from `defaults` key-by-key. Explicit `nil` in source = inherit default. Explicit value = override.

### Source Implementations — Detailed

#### 1. `diagnostics` — `DiagnosticChanged` autocommand

- **Hook:** `vim.api.nvim_create_autocmd("DiagnosticChanged", { callback = ... })`
- **Filter:** `ev.data.diagnostics`, keep only `severity == vim.diagnostic.severity.ERROR` (hardcoded for v1; config-exposed in v2).
- **Count check:** Compare `#new_errors` to `#previous_errors` for the buffer. Only trigger if count increased.
- **Trigger:** Play sound if count increased AND throttle allows.
- **State per buffer:** Track error count per `bufnr` in a `table<integer, integer>`.

#### 2. `neotest` — Wrap `neotest.setup`

- **Hook:** Wrap `require("neotest").setup` to inject a `"faaah"` consumer.
- **Consumer:**
  ```lua
  function(client)
    client.listeners.results = function(adapter_id, results, partial)
      -- only fire on final results (partial == false or nil)
      -- check if any result.status == "failed"
      -- if yes AND throttle allows → play sound
    end
  end
  ```
- **Load order:** faaah MUST be set up BEFORE neotest.setup(). Document this in README.
- **Escape hatch:** Expose `require("faaah").sources.neotest.manual_attach()` for users with reversed load order.
- **Edge case:** neotest may use metatable-based consumer merging. Use `vim.tbl_deep_extend` or match neotest's `vim.tbl_extend("error", ...)` patterns.

#### 3. `notifications` — Wrap `vim.notify`

- **Hook:** Save original `vim.notify`, replace with wrapper.
- **Filter:** Only fire on `level == vim.log.levels.ERROR` (integer 1).
- **Chain:** Always call original `vim.notify(msg, level, opts)` — never suppress.
- **Trigger:** Any ERROR-level notify AND throttle allows.
- **Known false positives:** LSP "No code actions available", etc. Throttle mitigates. v2 may add `ignore_patterns`.

### Sound Module — `sound.lua`

- **Backend auto-detect order:**
  1. `afplay` (macOS, `/usr/bin/afplay`)
  2. `ffplay` (check `vim.fn.executable("ffplay")`)
  3. `mpv` (check `vim.fn.executable("mpv")`)
- **User override:** `config.play_cmd` takes a template string like `"mplayer %s"`. `%s` is replaced with resolved path.
- **Default sound path resolution:**
  1. If user provides path in config → `vim.fn.expand(path)` (resolves `~`).
  2. If `nil` → resolve bundled default: use `debug.getinfo(1, "S").source` to find `lua/faaah/sound.lua` on disk, resolve to `../../sounds/default.mp3`.
- **Playback:** `vim.loop.spawn(backend, { args = { sound_path } }, callback)` — always async, non-blocking. No process-kill (overlap allowed). Callback only for error logging.

### Throttle Logic — `sources/init.lua`

Shared helper used by all sources:
```lua
-- per-source throttle state
local last_play_time = {}  -- table<string, number> keyed by source name

function M.throttle(name, ms)
  if ms == 0 then return true end  -- no throttle
  local now = os.time()  -- or vim.loop.now() for ms precision
  if not last_play_time[name] or (now - last_play_time[name]) >= ms / 1000 then
    last_play_time[name] = now
    return true
  end
  return false
end
```

### Runtime API

```lua
local faaah = require("faaah")

-- Per-source lifecycle (cheap: just boolean flag toggle)
faaah.source("diagnostics"):enable()
faaah.source("diagnostics"):disable()
faaah.source("diagnostics"):is_enabled()

-- Manual trigger (for keymaps / debugging)
faaah.play()               -- play default sound
faaah.play("/custom.mp3")  -- play specific file
```

Config is a frozen snapshot after `setup()`. Runtime changes via `enable()`/`disable()`. To change sound or throttle values: re-run `setup()`.

### MP3 Metadata

- Source: `~/Downloads/faaah.mp3`
- Duration: 1.93s
- Bitrate: 192 kbps, Stereo, 44.1 kHz
- Copy to `sounds/default.mp3`

### Key Tradeoffs Captured

| Tradeoff | Decision | Rationale |
|----------|----------|-----------|
| Override vs listen for vim.notify | Override (wrap + chain) | No listener API exists in Neovim for notify |
| Severity filter for diagnostics | ERROR only, hardcoded v1 | Matches "error sound" intuition; WARN/HINT noisy |
| Neotest integration method | Wrap neotest.setup | Cleanest; no force-load; works with neotest's consumer pattern |
| Load order requirement | faaah before neotest | Document only; manual_attach() escape hatch |
| Sound overlap | Allowed (no kill) | "That's the point" — intentional cacophony |
| Cross-platform audio | Auto-detect + config override | macOS/Linux; user supplies command if needed. Windows unsupported v1 |
| False positives in notifications | Accept, mitigate with throttle | vim.notify is broad; cannot filter by origin |

### Build Order (Task List)

1. **Create config.lua** — defaults table, validation function, merge logic (sources ← defaults inheritance).
2. **Create sound.lua** — backend detection, spawn function, default path resolution. Copy `faaah.mp3` to `sounds/default.mp3`.
3. **Create sources/init.lua** — shared throttle checker, source lifecycle base (enable/disable/is_enabled).
4. **Implement sources/diagnostics.lua** — DiagnosticChanged hook with error count tracking.
5. **Implement sources/notifications.lua** — vim.notify wrap with chain.
6. **Implement sources/neotest.lua** — neotest.setup wrap with consumer injection.
7. **Create init.lua** — setup() orchestration, source() accessor, play() manual trigger, module exports.
8. **Write README.md** — full documentation: setup examples, edge cases, load order, tradeoffs, API reference.

### What the User Said (Constraints)

- Single plugin, `require("faaah").setup()` — non-negotiable.
- Bundled default sound, user can override per-source or globally.
- Throttle configurable, including off (cacophony).
- Overlapping sounds allowed.
- Runtime enable/disable per source.
- Auto-detect neotest (pcall require, no lazy-load workaround needed).
- macOS + Linux support (afplay/ffplay/mpv).
- Diagnostics: ERROR severity only, configurable later.
- Notifications: accept false positives, document them.
- "Document edge cases and tradeoffs extensively."

### Suggested Skills for Next Agent

- **diagnose** — if hooks don't fire or sounds don't play during testing.
- **caveman-commit** — for writing concise conventional commits.
- **explain** — if user asks about the architecture or design decisions.
- **autoreview** — run before final commit to check code quality.
