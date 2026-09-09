local editor = require("kilo.editor")

local M = {}

function M.check()
  local ok = vim.health.start or vim.health.report_start
  local report_ok = vim.health.ok or vim.health.report_ok
  local report_warn = vim.health.warn or vim.health.report_warn
  local report_error = vim.health.error or vim.health.report_error
  local report_info = vim.health.info or vim.health.report_info

  ok("kilo.nvim")

  if vim.version().major == 0 and vim.version().minor < 11 then
    report_error("Neovim 0.11+ required (uses vim.fs.relpath), found %s", vim.version())
  else
    report_ok("Neovim %s", vim.version())
  end

  if vim.fn.executable("kilo") == 1 then
    report_ok("kilo executable found on PATH")
  else
    report_error("kilo executable not found on PATH")
  end

  if vim.fn.executable("openssl") == 1 then
    report_ok("openssl found on PATH")
  else
    report_warn(
      "openssl not found on PATH: the editor integration is disabled and file mentions fall back to typed @path#L-L text"
    )
  end

  if vim.fn.exists("+winfixbuf") == 1 then
    report_info("+winfixbuf available: the Kilo window refuses buffer swaps")
  else
    report_info("+winfixbuf unavailable: the Kilo window can be repointed by :buffer/:edit")
  end

  local status = editor.status()
  if status.disabled then
    report_warn("Editor integration disabled (WebSocket server failed to start)")
  elseif status.connected then
    report_ok("Editor integration connected on port %s%s", status.port, status.ready and " and ready" or "")
  elseif status.port then
    report_info("Editor integration listening on port %s, no Kilo connected", status.port)
  else
    report_info("Editor integration not started (starts with the first Kilo terminal)")
  end
end

return M
