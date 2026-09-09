local notify = require("kilo.util").notify

---@class kilo.Opts.Keys
---@field toggle? string|false Keymap to toggle the Kilo terminal.
---@field range? string|false Visual-mode keymap to send the selection to Kilo.
---@field line? string|false Normal-mode keymap to send the current line to Kilo.
---@field side? string|false Keymap to toggle the split between bottom and right.

---@class kilo.Opts
---@field height? number Split height: a ratio (0 < h <= 1) of the window, or a row count (h > 1).
---@field width? number Split width: a ratio (0 < w <= 1) of the window, or a column count (w > 1).
---@field side? "bottom"|"right" Side for a new split.
---@field keys? kilo.Opts.Keys|false Keymaps to register. Set to false to register none.

local defaults = {
  height = 0.30,
  width = 0.40,
  side = "right",
  keys = {
    toggle = "<leader>k.",
    range = "<leader>kr",
    line = "<leader>kl",
    side = "<leader>ks",
  },
}

local M = {}

---Resolve the effective options by merging vim.g.kilo_opts over the defaults.
---@return kilo.Opts
function M.get()
  return vim.tbl_deep_extend("force", {}, defaults, vim.g.kilo_opts or {})
end

---Validate a sizing option (height or width). Returns the value when it is a positive number,
---otherwise warns and returns the configured default for that option.
---@param name "height"|"width"
---@param value unknown
---@return number
function M.number(name, value)
  local default = defaults[name] --[[@as number]]
  if type(value) ~= "number" or value <= 0 then
    notify(string.format("Invalid %s %s, falling back to %s.", name, vim.inspect(value), default), vim.log.levels.WARN)
    return default
  end
  return value
end

---Validate the split side. Returns the value when it is "bottom" or "right", otherwise warns and
---returns "right".
---@param value unknown
---@return "bottom"|"right"
function M.side(value)
  if value == "bottom" or value == "right" then
    return value
  end
  local default = defaults.side --[[@as "bottom"|"right"]]
  notify(string.format("Invalid side %s, falling back to %q.", vim.inspect(value), default), vim.log.levels.WARN)
  return default
end

return M
