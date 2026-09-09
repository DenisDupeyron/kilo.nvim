local config = require("kilo.config")
local editor = require("kilo.editor")
local notify = require("kilo.util").notify

local M = {}

local state = {
  buf = nil,
  cwd = nil,
  job = nil,
  win = nil,
  side = nil,
}

local has_winfixbuf = vim.fn.exists("+winfixbuf") == 1

local function valid_win()
  return state.win and vim.api.nvim_win_is_valid(state.win)
end

local function valid_buf()
  return state.buf and vim.api.nvim_buf_is_valid(state.buf)
end

local function terminal_running()
  return valid_buf() and state.job ~= nil
end

-- The window is only ours while it still displays the terminal buffer. A stray :buffer,
-- :edit, :terminal, quickfix jump, or session restore can repoint it. When that happens the
-- window belongs to the user's file and must never be closed or reused as the Kilo window.
local function terminal_visible()
  if not valid_win() or not valid_buf() then
    return false
  end
  return vim.api.nvim_win_get_buf(state.win) == state.buf
end

local function focus_terminal()
  if terminal_visible() and vim.api.nvim_get_current_win() ~= state.win then
    vim.api.nvim_set_current_win(state.win)
  end
end

---Apply the terminal window options. Safe to call on any valid window.
---@param win integer
function M.configure_window(win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end

  vim.wo[win].foldcolumn = "0"
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].statuscolumn = ""
  if has_winfixbuf then
    -- Refuse buffer swaps in this window: any :buffer/:edit/:terminal aimed here fails with
    -- E1513 instead of silently replacing the running Kilo session.
    vim.wo[win].winfixbuf = true
  end
end

---Resolve the configured split height into a row count.
---@return integer
function M.split_height()
  local height = config.number("height", config.get().height)

  if height > 1 then
    return math.max(1, math.floor(height))
  end

  return math.max(1, math.floor((vim.o.lines - vim.o.cmdheight) * height))
end

---Resolve the configured split width into a column count.
---@return integer
function M.split_width()
  local width = config.number("width", config.get().width)

  if width > 1 then
    return math.max(1, math.floor(width))
  end

  return math.max(1, math.floor(vim.o.columns * width))
end

---Apply the configured height or width to a window, depending on the given side. Used both
---when a split is created and when the outer window is resized, so the two stay consistent.
---@param win integer
---@param side "bottom"|"right"
function M.apply_size(win, side)
  if side == "right" then
    vim.api.nvim_win_set_width(win, M.split_width())
  else
    vim.api.nvim_win_set_height(win, M.split_height())
  end
end

---The side opposite the given one.
---@param side "bottom"|"right"
---@return "bottom"|"right"
local function other_side(side)
  return side == "bottom" and "right" or "bottom"
end

---The side to place the split on: the remembered one while a terminal is alive, otherwise the
---configured default. Stores the result so toggling off and on restores the last side.
---@return "bottom"|"right"
local function resolve_side()
  local side = state.side or config.side(config.get().side)
  state.side = side
  return side
end

local function close_window()
  if terminal_visible() then
    vim.api.nvim_win_close(state.win, false)
  end
  state.win = nil
end

local function start_terminal()
  if vim.fn.executable("kilo") == 0 then
    notify("Cannot start Kilo: executable not found in PATH.", vim.log.levels.ERROR)
    return false
  end

  state.win = vim.api.nvim_get_current_win()
  state.buf = vim.api.nvim_get_current_buf()
  state.cwd = vim.fn.getcwd()
  vim.bo[state.buf].bufhidden = "hide"
  vim.bo[state.buf].buflisted = false

  -- kilo wraps its OSC 52 clipboard-copy escape sequence in a tmux DCS
  -- passthrough envelope whenever $TMUX is set, assuming its PTY consumer is a
  -- tmux client. Here the consumer is a Neovim :terminal buffer, which doesn't
  -- understand that wrapper and leaks fragments of the raw sequence as garbage
  -- text in the prompt. Blanking TMUX/STY for this child process makes it emit
  -- plain OSC 52, which Nvim's terminal handles natively.
  local env = { TMUX = "", STY = "" }
  if editor.start() then
    env.KILO_EDITOR_SSE_PORT = tostring(editor.port())
  end

  local job
  job = vim.fn.termopen({ "kilo" }, {
    cwd = state.cwd,
    env = env,
    on_exit = function()
      if state.job == job then
        state.cwd = nil
        state.job = nil
        state.side = nil
        vim.schedule(function()
          if terminal_visible() then
            close_window()
          end
          if valid_buf() then
            vim.api.nvim_buf_delete(state.buf, { force = true })
          end
          state.buf = nil
        end)
      end
    end,
  })

  if job <= 0 then
    state.buf = nil
    state.cwd = nil
    notify("Cannot start Kilo terminal.", vim.log.levels.ERROR)
    return false
  end

  state.job = job
  M.configure_window(state.win)
  return true
end

local function show_split()
  local side = resolve_side()
  if side == "right" then
    vim.cmd("botright vnew")
  else
    vim.cmd("botright new")
  end
  local new_win = vim.api.nvim_get_current_win()
  local scratch_buf = vim.api.nvim_get_current_buf()

  if terminal_running() then
    vim.api.nvim_win_set_buf(new_win, state.buf)
    state.win = new_win
    -- :new/:vnew created a fresh scratch buffer for the split; now that the window shows the
    -- terminal buffer instead, that scratch buffer is an orphan. Left alone it lingers as an
    -- extra listed "[No Name]" buffer (visible in tabline/bufferline UIs) that piles up with
    -- every toggle.
    if vim.api.nvim_buf_is_valid(scratch_buf) and scratch_buf ~= state.buf then
      vim.api.nvim_buf_delete(scratch_buf, { force = true })
    end
  elseif not start_terminal() then
    if vim.api.nvim_win_is_valid(new_win) then
      vim.api.nvim_win_close(new_win, false)
    end
    state.win = nil
    return
  end

  M.apply_size(state.win, side)
  M.configure_window(state.win)
  focus_terminal()
end

---Toggle the Kilo terminal split.
function M.toggle()
  if terminal_visible() then
    close_window()
  else
    show_split()
  end
end

---Toggle the split between the bottom and the right, restoring the pre-toggle focus and mode.
function M.toggle_side()
  if not terminal_visible() then
    notify("Kilo terminal is not visible.", vim.log.levels.WARN)
    return
  end

  local previous_win = vim.api.nvim_get_current_win()
  local was_focused = previous_win == state.win
  local was_terminal_mode = vim.fn.mode() == "t"
  if was_terminal_mode then
    vim.cmd("stopinsert")
  end

  state.side = other_side(resolve_side())
  close_window()
  show_split()

  -- Restore focus to wherever it was before relocating (falling back to the Kilo window,
  -- where show_split() already left focus, if that window is gone), then restore terminal
  -- mode there too. Kilo's window isn't the only terminal that could have been focused: the
  -- "t" mode keymap for this toggle is global, so a user in terminal-insert mode in an
  -- unrelated terminal must be put back into insert mode, not left in normal mode.
  if not was_focused and vim.api.nvim_win_is_valid(previous_win) then
    vim.api.nvim_set_current_win(previous_win)
  end
  if was_terminal_mode then
    vim.cmd("startinsert")
  end
end

---The side the split is currently on.
---@return "bottom"|"right"
function M.current_side()
  return resolve_side()
end

local function buffer_file_path()
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" then
    notify("Save the buffer before sending its context to Kilo.", vim.log.levels.WARN)
    return nil
  end
  return vim.fn.fnamemodify(path, ":p")
end

-- Fallback when Kilo is not connected to the editor socket: typing the mention prefills
-- Kilo's file autocomplete with the range already parsed, so accepting the match attaches
-- the ranged file part. Kilo's mention syntax separates the range from the path with "#",
-- and a single line carries no end bound.
---@param path string
---@param first_line integer
---@param last_line integer
---@return string
function M.context_for_range(path, first_line, last_line)
  path = vim.fs.relpath(state.cwd or vim.fn.getcwd(), path) or path
  if first_line == last_line then
    return string.format("@%s#%d", path, first_line)
  end

  return string.format("@%s#%d-%d", path, first_line, last_line)
end

---Send a line range from the current buffer to Kilo.
---@param first_line integer
---@param last_line integer
function M.send_context(first_line, last_line)
  local path = buffer_file_path()
  if not path then
    return
  end

  if not terminal_visible() then
    show_split()
  end
  if not state.job then
    notify("Kilo terminal is not running.", vim.log.levels.WARN)
    return
  end

  if not editor.mention(path, first_line, last_line) then
    vim.api.nvim_chan_send(state.job, M.context_for_range(path, first_line, last_line))
  end
  focus_terminal()
end

---Send the current line to Kilo.
function M.send_line()
  local line = math.max(1, vim.api.nvim_win_get_cursor(0)[1])
  M.send_context(line, line)
end

---Send the current visual selection to Kilo.
function M.send_selection()
  local first_line = math.max(1, vim.fn.line("v"))
  local last_line = math.max(1, vim.api.nvim_win_get_cursor(0)[1])
  M.send_context(math.min(first_line, last_line), math.max(first_line, last_line))
end

---The terminal buffer id, when one is running.
---@return integer|nil
function M.current_buf()
  return state.buf
end

---The window that owns the terminal, when one is running.
---@return integer|nil
function M.current_win()
  return state.win
end

---Whether the terminal window is currently visible and still shows the terminal buffer.
---@return boolean
function M.visible()
  return terminal_visible()
end

---@private
M._test = {
  other_side = other_side,
}

return M
