if vim.g.loaded_kilo then
  return
end
vim.g.loaded_kilo = true

local config = require("kilo.config")
local terminal = require("kilo.terminal")

local function register_keymaps()
  local keys = config.get().keys
  if keys == false then
    return
  end

  local toggle = keys.toggle
  if toggle then
    vim.keymap.set("n", toggle, function()
      terminal.toggle()
    end, { desc = "Toggle Kilo", silent = true })
    vim.keymap.set(
      "t",
      toggle,
      "<C-\\><C-N><Cmd>KiloToggle<CR>",
      { desc = "Toggle Kilo", nowait = true, silent = true }
    )
  end

  local range = keys.range
  if range then
    vim.keymap.set("x", range, function()
      terminal.send_selection()
    end, { desc = "Send selection to Kilo", silent = true })
  end

  local line = keys.line
  if line then
    vim.keymap.set("n", line, function()
      terminal.send_line()
    end, { desc = "Send line to Kilo", silent = true })
  end

  local side = keys.side
  if side then
    vim.keymap.set("n", side, function()
      terminal.toggle_side()
    end, { desc = "Toggle Kilo side", silent = true })
    -- Call Lua directly instead of the <C-\><C-N><Cmd>...<CR> string form so toggle_side()
    -- still observes mode "t" and can restore terminal mode after relocating.
    vim.keymap.set("t", side, function()
      terminal.toggle_side()
    end, { desc = "Toggle Kilo side", nowait = true, silent = true })
  end
end

if vim.v.vim_did_enter == 1 then
  register_keymaps()
else
  vim.api.nvim_create_autocmd("VimEnter", {
    callback = register_keymaps,
    once = true,
  })
end

vim.api.nvim_create_user_command("KiloToggle", function()
  terminal.toggle()
end, { force = true })

vim.api.nvim_create_user_command("KiloToggleSide", function()
  terminal.toggle_side()
end, { force = true })

vim.api.nvim_create_user_command("KiloSend", function(args)
  if args.range == 0 then
    terminal.send_line()
  else
    terminal.send_context(args.line1, args.line2)
  end
end, { force = true, range = true })

local group = vim.api.nvim_create_augroup("kilo_terminal", { clear = true })
vim.api.nvim_create_autocmd("TermOpen", {
  group = group,
  callback = function(args)
    if args.buf ~= terminal.current_buf() then
      return
    end
    vim.schedule(function()
      local win = terminal.current_win()
      if win then
        terminal.configure_window(win)
      end
    end)
    vim.keymap.set("n", "<LeftRelease>", "<LeftRelease>i", {
      buffer = args.buf,
      nowait = true,
      remap = false,
    })
  end,
})

vim.api.nvim_create_autocmd("VimResized", {
  group = group,
  callback = function()
    local win = terminal.current_win()
    if win and terminal.visible() then
      terminal.apply_size(win, terminal.current_side())
    end
  end,
})
