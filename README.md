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
- Notifications source is **disabled by default**, so `vim.notify` is not wrapped unless you enable it
- Throttles to one sound every 2 seconds per source
- Auto-detects audio backend (afplay on macOS, ffplay, or mpv)

## Configuration

```lua
require("faaah").setup({
  defaults = {
    sound = nil,         -- nil = bundled default.mp3; string = file in plugin sounds/ or absolute path
    throttle_ms = 2000,  -- cooldown in ms; 0 = no throttle (cacophony)
  },
  sources = {
    diagnostics = {
      enabled = true,
      -- sound, throttle_ms inherit from defaults unless overridden explicitly
    },
    neotest = {
      enabled = true,
      sound = "sad-meow-song.mp3",         -- resolves to plugin's sounds/sad-meow-song.mp3
      throttle_ms = 5000,                    -- 5s cooldown for tests
    },
    notifications = {
      enabled = true,  -- opt-in (disabled by default)
      ignore_patterns = {
        "Nothing to rename", -- additive: built-in ignores still apply
      },
    },
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

### Sound Path Resolution

- `sound = "sad-meow-song.mp3"` → resolves to this plugin's `sounds/sad-meow-song.mp3`
- `sound = "memes/oof.mp3"` → resolves to this plugin's `sounds/memes/oof.mp3`
- `sound = "~/sounds/custom.mp3"` or `sound = "/tmp/custom.mp3"` → treated as external absolute path

### Default Configuration

Calling `require("faaah").setup()` with no arguments uses these defaults:

```lua
{
  defaults = {
    sound = nil,         -- nil = use bundled sounds/default.mp3
    throttle_ms = 2000,  -- 2 second cooldown between sounds per source
  },
  sources = {
    diagnostics   = { enabled = true },
    neotest       = { enabled = true },
    notifications = { enabled = false },  -- disabled: `vim.notify` stays untouched until enabled
  },
  play_cmd = nil,  -- nil = auto-detect (afplay/ffplay/mpv)
}
```

## Commands

After `setup()`, the `:Faaah` command is available with subcommands:

| Command | Effect |
|---------|--------|
| `:Faaah enable` | Unmute all sources |
| `:Faaah disable` | Mute all sources (remembers per-source state) |
| `:Faaah toggle` | Flip between enabled/disabled |
| `:Faaah play` | Manually play the default sound |

Tab-completion available for subcommands. Map to keys if desired:

```lua
vim.keymap.set("n", "<leader>ft", ":Faaah toggle<CR>", { desc = "Toggle error sounds" })
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

**Default state:** Disabled by default, because `vim.notify` is global and noisy.

**Add extra ignores with `ignore_patterns`:**

```lua
notifications = {
  enabled = true,
  ignore_patterns = {
    "Nothing to rename",
    "my noisy plugin",
  },
}
```

User patterns are **additive** — they join the built-in defaults, never replace them. Omit `ignore_patterns` (or use `{}`) to keep only the built-in ignore list.

Built-in defaults filter these common false positives:

| Category | Patterns |
|----------|----------|
| LSP info | `No code actions available`, `No information available`, `No hover information`, `No signature help available` |
| LSP lookups | `No .- found`, `No .- available`, `Not found` |
| LSP lifecycle | `Client .- quit`, `Client .- stopped`, `Server .- failed`, `method .- not supported` |
| Treesitter | `No parser for`, `treesitter .- error` |
| Completion | `No completion found`, `No snippet found` |
| Noise | blank messages, separators, `cancelled`, `aborted`, `interrupted` |

**Known false positives:**
- LSP "No code actions available" notifications
- Plugin messages that use ERROR level for non-critical info
- Any plugin that calls `vim.notify(msg, vim.log.levels.ERROR)`

Built-in ignores and `ignore_patterns` mitigate this. Matching uses Lua patterns.

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

### Global Mute

Disable or enable all sources at once:

```lua
faaah.disable()   -- mute all, remembers which sources were on
faaah.enable()    -- restore previous per-source state
faaah.is_enabled() -- true when not globally muted
```

Or use commands: `:Faaah disable`, `:Faaah enable`, `:Faaah toggle`.

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
| False positives in notifications | Disabled by default + ignore known noisy messages | `vim.notify` is broad; Lua-pattern ignores are flexible and predictable |
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

**Debug logging:**
All logging goes to file. Enable verbose output to trace autocmd events, throttle decisions, and sound playback:

```lua
require("faaah").log.set_level("debug")
```

Log file: `:echo stdpath("data") .. "/faaah.log"` (usually `~/.local/share/nvim/faaah.log`). Set back to `"info"` when done.

```lua
-- Change log file location
require("faaah").log.set_path("~/faaah-debug.log")

-- Tail the log from another terminal
-- $ tail -f ~/.local/share/nvim/faaah.log
```

## License

MIT
