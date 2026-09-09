local terminal = require("kilo.terminal")

local M = {}

---Toggle the Kilo terminal split.
function M.toggle()
  terminal.toggle()
end

---Toggle the split between the bottom and the right.
function M.toggle_side()
  terminal.toggle_side()
end

---Send the current line to Kilo.
function M.send_line()
  terminal.send_line()
end

---Send the current visual selection to Kilo.
function M.send_selection()
  terminal.send_selection()
end

return M
