local M = {}

---Notify the user with a "KILO" titled message.
---@param message string
---@param level integer|nil
function M.notify(message, level)
  vim.notify(message, level, { title = "KILO" })
end

return M
