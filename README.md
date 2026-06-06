# faaah.nvim

Play a funny error sound when things go wrong. Diagnostics, test failures, error notifications — each source configurable, each with its own throttle.

## Installation

### lazy.nvim

```lua
{
  "yourname/faaah.nvim",
  config = function()
    require("faaah").setup()
  end,
}
```

### packer.nvim

```lua
use {
  "yourname/faaah.nvim",
  config = function()
    require("faaah").setup()
  end,
}
```

## Quick Start

```lua
require("faaah").setup()
```

With defaults, this:
- Plays the bundled sound on new LSP diagnostic errors
- Plays on neotest test failures (must load faaah *before* `neotest.setup()`)
- Plays on `vim.notify(msg, vim.log.levels.ERROR)` calls
- Throttles to one sound every 2 seconds per source
- Auto-detects audio backend (afplay on macOS, ffplay, or mpv)

## Configuration

```lua
require("faaah").setup({
  defaults = {
    sound = nil,         -- nil = bundled default.mp3; string = path (supports ~/)
    throttle_ms = 2000,  -- cooldown in ms; 0 = no throttle (cacophony)
  },
  sources = {
    diagnostics = {
      enabled = true,
      -- sound, throttle_ms inherit from defaults unless overridden explicitly
    },
    neotest = {
      enabled = true,
      sound = "~/sounds/sad-trombone.mp3", -- override for this source only
      throttle_ms = 5000,                    -- 5s cooldown for tests
    },
    notifications = { enabled = true },
  },
  play_cmd = nil,  -- nil = auto-detect; string = template like "mplayer %s"
})
```

### Config Inheritance

Each source inherits from `defaults` key-by-key:
- If a key is **not set** in the source → inherits the default value.
- If a key is **explicitly set** (even to `nil`) → uses the source value.
- Explicit `nil` means "no override, use default" — same as not setting it.

```lua
defaults = { sound = nil, throttle_ms = 2000 }
sources = {
  diagnostics = { enabled = true },
  -- diagnostics.sound → nil → inherits defaults.sound (nil → uses bundled)
  -- diagnostics.throttle_ms → nil → inherits defaults.throttle_ms (2000)
}
```

## Sources

### diagnostics

Listens to `DiagnosticChanged` autocommand events. Triggers when the count of `vim.diagnostic.severity.ERROR` diagnostics **increases** for a buffer.

- Severity filter: `ERROR` only (hardcoded in v1; configurable in v2).
- Per-buffer error counting: only fires when errors go up, not on every event.
- Re-attach safe: calling `setup()` again detaches the old autocommand cleanly.

**Edge cases:**
- If errors are cleared and then re-appear, the count resets to 0 and then jumps — sound plays.
- Diagnostics from multiple LSP clients on the same buffer are counted together.
- Buffer-local state is discarded when the source is detached.

### neotest

Wraps `neotest.setup()` to inject a consumer named `"faaah"`. Plays when any test result has `status == "failed"` and results are final (`partial == false`).

**Load order:** `faaah.setup()` **MUST** be called **before** `neotest.setup()`. The wrapper is installed during faaah's setup and only applies when the user later calls `neotest.setup()`.

```lua
-- CORRECT
require("faaah").setup()
require("neotest").setup({ ... })

-- WRONG — faaah cannot wrap neotest.setup
require("neotest").setup({ ... })
require("faaah").setup()
```

**Escape hatch:** If you must load neotest first, call after both are loaded:

```lua
require("faaah").setup()
-- then:
require("faaah").sources.neotest.manual_attach() -- best-effort
```

`manual_attach()` is best-effort — it cannot retroactively inject the consumer into an already-initialized neotest client. The load-order requirement is the primary integration path.

**Edge cases:**
- neotest uses metatable-based consumer merging. faaah uses `vim.tbl_deep_extend("force", ...)` to handle this.
- If neotest is not installed, the source warns and disables itself gracefully.
- Test results are trees; faaah recursively walks the tree to find any `"failed"` status.

### notifications

Wraps `vim.notify` to intercept ERROR-level messages. The original `vim.notify` is **always** called — messages are never suppressed.

**Filter:** Only `level == vim.log.levels.ERROR` (integer 1) triggers the sound.

**Known false positives:**
- LSP "No code actions available" notifications
- Plugin messages that use ERROR level for non-critical info
- Any plugin that calls `vim.notify(msg, vim.log.levels.ERROR)`

Throttle mitigates this. v2 may add `ignore_patterns` for regex filtering.

**Edge cases:**
- If another plugin also wraps `vim.notify`, load order matters. faaah wraps at setup time; later wrappers will wrap faaah's wrapper. The chain always preserves the original.
- Calling `setup()` again restores the original `vim.notify` before re-wrapping.

## Runtime API

### Enable/Disable Sources at Runtime

```lua
local faaah = require("faaah")

-- Per-source toggle (cheap: boolean flag change)
faaah.source("diagnostics"):disable()
faaah.source("diagnostics"):enable()
print(faaah.source("diagnostics"):is_enabled()) -- true/false

faaah.source("notifications"):disable()
faaah.source("neotest"):enable()
```

**Note:** Config (sound path, throttle_ms) is frozen after `setup()`. To change these values, re-run `setup()` with new options.

### Manual Sound Trigger

```lua
-- Play the default (configured) sound
require("faaah").play()

-- Play a specific file
require("faaah").play("~/sounds/ohno.mp3")
```

## Audio Backends

faaah auto-detects the best available backend:

| Backend | Platform | Notes |
|---------|----------|-------|
| `afplay` | macOS | Built-in, no install needed |
| `ffplay` | Any | Part of ffmpeg, needs install |
| `mpv` | Any | Needs mpv install |

Override with `play_cmd`:

```lua
require("faaah").setup({
  play_cmd = "mplayer %s",   -- %s is replaced with the sound file path
  -- or:
  play_cmd = "paplay %s",    -- PipeWire/PulseAudio
})
```

Playback is always **asynchronous and non-blocking**. Overlapping sounds are allowed — that's intentional.

**Windows is unsupported in v1.** Users can provide a `play_cmd` that works on their system.

## Tradeoffs

| Tradeoff | Decision | Why |
|----------|----------|-----|
| Override vs listen for `vim.notify` | Override (wrap + chain) | No listener API exists in Neovim for notify |
| Severity filter for diagnostics | `ERROR` only, hardcoded | Matches "error sound" intuition; WARN/HINT too noisy |
| Neotest integration method | Wrap `neotest.setup` | Cleanest; works with neotest's consumer pattern |
| Load order requirement | faaah before neotest | Documented; `manual_attach()` as escape hatch |
| Sound overlap | Allowed (no kill) | Intentional — cacophony is the point |
| Cross-platform audio | Auto-detect + config override | macOS/Linux; user supplies `play_cmd` if needed |
| False positives in notifications | Accept, mitigate with throttle | `vim.notify` is broad; cannot filter by origin in v1 |
| Config mutability | Frozen after `setup()` | Simpler reasoning; re-run `setup()` to change settings |

## Troubleshooting

**No sound plays:**
- Check that at least one audio backend is available: `:echo executable("afplay")` or `:echo executable("ffplay")`
- Check that the source is enabled: `:lua print(require("faaah").source("diagnostics"):is_enabled())`
- Check throttle: default is 2000ms — errors within 2 seconds of each other won't both play

**Sound overlaps are annoying:**
Set `throttle_ms` higher per source or globally:

```lua
defaults = { throttle_ms = 10000 },  -- 10 seconds
```

Or set to `0` for maximum cacophony — your choice.

**neotest integration not working:**
Verify load order: `faaah.setup()` before `neotest.setup()`. If that's impossible, call `manual_attach()` after both are loaded.

## License

MIT
