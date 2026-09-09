# kilo.nvim

Neovim plugin that integrates the [Kilo](https://kilo.ai) TUI into your
editor: a toggleable terminal split plus one-keystroke file mentions that
attach context straight to the prompt.

`kilo.nvim` does few things but it does them well. It only takes care of the
communication between Neovim and Kilo. It doesn't try to reinvent the wheel
by re-implementing Kilo features within Neovim or vice-versa.

## Features

- Toggle a terminal split running `kilo` in your current working directory
- Move the split between the bottom and the right side, and then back
- Send the current line or a visual selection to Kilo as a file mention
- Implements the editor-integration protocol
- Hardened against real-world terminal edge cases
- A real `:checkhealth kilo` provider
- `:KiloToggle`, `:KiloToggleSide` and `:[range]KiloSend` for command-driven
  use

## Requirements

- Neovim 0.11+
- `kilo` on `PATH`
- `openssl` on `PATH` (optional): required for the editor integration
  channel. Without it, mentions fall back to typed text. `:checkhealth kilo`
  reports this.

## Install

### lazy.nvim

```lua
{
  "Kilo-Org/kilo.nvim",
  config = function()
    ---@type kilo.Opts
    vim.g.kilo_opts = {
      -- Your configuration, if any
    }
  end,
}
```

### vim.pack

```lua
vim.pack.add({ src = "https://github.com/Kilo-Org/kilo.nvim" })
```

### Type checking with lazydev.nvim

`---@type kilo.Opts` annotations only resolve if your Lua LSP knows where to
find `kilo.nvim`'s type definitions. If you use
[lazydev.nvim](https://github.com/folke/lazydev.nvim), add a library entry
for it:

```lua
{
  "folke/lazydev.nvim",
  opts = {
    library = {
      { path = "kilo.nvim", words = { "kilo" } },
    },
  },
},
```

Without this, editing `vim.g.kilo_opts` still works at runtime, but
`lua_ls` reports "Undefined type or alias `kilo.Opts`" as a diagnostic.

## Configuration

The snippet below shows the default values.

```lua
---@type kilo.Opts
vim.g.kilo_opts = {
  -- Split height when the split is at the bottom: a ratio of the window
  -- (0 < h <= 1) or a row count (h > 1).
  height = 0.30,
  -- Split width when the split is on the side: a ratio of the window
  -- (0 < w <= 1) or a column count (w > 1).
  width = 0.40,
  -- Side for a new split: "bottom" or "right".
  side = "right",
  -- Keymaps to register. Set to false to register none. Set an individual
  -- key to false to disable only that one.
  keys = {
    toggle = "<leader>k.", -- toggle the Kilo terminal
    range = "<leader>kr", -- send the visual selection
    line = "<leader>kl", -- send the current line
    side = "<leader>ks", -- move the split between the bottom and the right
  },
}
```

Options are read from `vim.g.kilo_opts` at call time. Keymaps are registered
once on `VimEnter`, so the table can be set in either lazy.nvim's `init =` or
`config =` function.

## Usage

| Action | Default keymap | Command |
| --- | --- | --- |
| Toggle the Kilo terminal | `<leader>k.` | `:KiloToggle` |
| Move the split between bottom and right | `<leader>ks` | `:KiloToggleSide` |
| Send the current line | `<leader>kl` | `:KiloSend` |
| Send the visual selection | `<leader>kr` | `:KiloSend` (with a range) |
| Send lines 5-9 | | `:5,9KiloSend` |

Other usage tips, not specific to `kilo.nvim`:

- If mouse support is enabled in your Neovim config, you can use it to
  drag the separator and resize the Kilo split
- You can also click on the Kilo split or any other to focus them
- Use `Ctrl+j` to insert a newline in the prompt box
- Use `Ctrl+c` (once!) to clear the prompt box
- Use `Ctrl+d` within the Kilo split to exit Kilo and close the split

## API

`require("kilo")` exposes:

- `toggle()`: toggle the Kilo terminal split
- `toggle_side()`: move the split between the bottom and the right
- `send_line()`: send the current line to Kilo
- `send_selection()`: send the current visual selection to Kilo

## Editor integration

When the Kilo terminal starts, kilo.nvim listens on a local WebSocket. If
Kilo connects back (over `KILO_EDITOR_SSE_PORT`), file mentions are delivered
over that channel and appear attached to the prompt. If no Kilo is connected,
mentions are typed into the terminal as `@path#L-L`, which Kilo's file
autocomplete parses.

## Health

Run `:checkhealth kilo` to verify the `kilo` binary, `openssl`, the Neovim
version, and the editor-integration state.
