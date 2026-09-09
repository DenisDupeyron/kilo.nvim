local notify = require("kilo.util").notify
local bit = require("bit")

local M = {}

-- Kilo's editor integration (Claude Code IDE protocol): when KILO_EDITOR_SSE_PORT is set,
-- the TUI connects back over a WebSocket and treats "at_mentioned" notifications as file
-- mentions attached straight to the prompt. Sending mentions over this channel avoids the
-- file-autocomplete popup that typing "@path#L-L" into the terminal would open.
local WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

-- Generous headroom over any legitimate handshake header or JSON-RPC message this protocol
-- exchanges (all well under a few KB). Bounds worst-case memory when a peer never completes
-- a header or frame, whether from a bug or a hostile local connection.
local MAX_BUFFER_SIZE = 1024 * 1024

-- The TCP handles are module-level locals rather than table fields so the type checker can
-- track their type from uv.new_tcp() across functions.
local server = nil
local client = nil

local ws = {
  port = nil,
  buffer = "",
  handshaken = false,
  ready = false,
  disabled = false,
  fragments = {},
  pending = {},
}

local function ws_encode(opcode, payload)
  local len = #payload
  if len < 126 then
    return string.char(0x80 + opcode, len) .. payload
  end
  if len < 65536 then
    return string.char(0x80 + opcode, 126, math.floor(len / 256), len % 256) .. payload
  end
  return string.char(
    0x80 + opcode,
    127,
    0,
    0,
    0,
    0,
    math.floor(len / 16777216) % 256,
    math.floor(len / 65536) % 256,
    math.floor(len / 256) % 256,
    len % 256
  ) .. payload
end

local function ws_decode_frame(buf)
  if #buf < 2 then
    return nil
  end
  local b1, b2 = buf:byte(1), buf:byte(2)
  local fin = b1 >= 0x80
  local opcode = b1 % 0x10
  local len = b2 % 0x80
  local offset = 2
  if len == 126 then
    if #buf < 4 then
      return nil
    end
    len = buf:byte(3) * 256 + buf:byte(4)
    offset = 4
  elseif len == 127 then
    if #buf < 10 then
      return nil
    end
    len = 0
    for i = 1, 8 do
      len = len * 256 + buf:byte(offset + i)
    end
    offset = 10
  end
  local mask
  if b2 >= 0x80 then
    if #buf < offset + 4 then
      return nil
    end
    mask = { buf:byte(offset + 1), buf:byte(offset + 2), buf:byte(offset + 3), buf:byte(offset + 4) }
    offset = offset + 4
  end
  if #buf < offset + len then
    return nil
  end
  local payload = buf:sub(offset + 1, offset + len)
  if mask and len > 0 then
    local bytes = {}
    for i = 1, len do
      bytes[i] = string.char(bit.bxor(payload:byte(i), mask[(i - 1) % 4 + 1]))
    end
    payload = table.concat(bytes)
  end
  return opcode, payload, fin, offset + len
end

local function ws_close_client()
  if client then
    pcall(function()
      client:read_stop()
      client:close()
    end)
  end
  client = nil
  ws.buffer = ""
  ws.handshaken = false
  ws.ready = false
  ws.fragments = {}
  if #ws.pending > 0 then
    -- Mentions queued for a client that never reached "ready" would otherwise be silently
    -- lost (or wrongly flushed to a later, unrelated connection). Drop them and say so.
    -- vim.schedule regardless of caller context: this function also runs directly from a
    -- raw libuv accept callback, where calling the Neovim API is unsafe.
    local dropped = #ws.pending
    ws.pending = {}
    vim.schedule(function()
      notify(
        string.format(
          "Kilo editor integration: %d pending file mention(s) were lost because the connection "
            .. "closed before Kilo was ready. Send them again.",
          dropped
        ),
        vim.log.levels.WARN
      )
    end)
  end
end

local function ws_send_json(message)
  if not client then
    return
  end
  local ok, payload = pcall(vim.json.encode, message)
  if ok then
    client:write(ws_encode(1, payload))
  end
end

local function ws_send_mention(path, first_line, last_line)
  ws_send_json({
    jsonrpc = "2.0",
    method = "at_mentioned",
    params = { filePath = path, lineStart = first_line, lineEnd = last_line },
  })
end

local function ws_handle_message(message)
  local ok, rpc = pcall(vim.json.decode, message)
  if not ok or type(rpc) ~= "table" then
    return
  end
  if rpc.method == "initialize" and rpc.id ~= nil then
    ws_send_json({
      jsonrpc = "2.0",
      id = rpc.id,
      result = {
        protocolVersion = "2025-11-25",
        serverInfo = { name = "kilo.nvim", version = "1.0" },
        capabilities = {},
      },
    })
  elseif rpc.method == "notifications/initialized" then
    ws.ready = true
    for _, mention in ipairs(ws.pending) do
      ws_send_mention(mention.path, mention.first_line, mention.last_line)
    end
    ws.pending = {}
  end
end

local function ws_sha1_base64(text)
  local cmd = "printf '%s' " .. vim.fn.shellescape(text) .. " | openssl dgst -sha1 -binary | openssl base64"
  local out = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return (out:gsub("%s+", ""))
end

local function ws_process()
  if not client then
    return
  end

  if not ws.handshaken then
    local header_end = ws.buffer:find("\r\n\r\n", 1, true)
    if not header_end then
      return
    end
    local key = ws.buffer:sub(1, header_end):match("[Ss]ec%-[Ww]eb[Ss]ocket%-[Kk]ey:%s*(%S+)")
    ws.buffer = ws.buffer:sub(header_end + 4)
    local accept = key and ws_sha1_base64(key .. WS_GUID)
    if not accept then
      ws.disabled = true
      ws_close_client()
      pcall(function()
        if server then
          server:close()
        end
      end)
      server = nil
      notify("Kilo editor integration disabled: WebSocket handshake failed (openssl missing?).", vim.log.levels.WARN)
      return
    end
    client:write(
      "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: "
        .. accept
        .. "\r\n\r\n"
    )
    ws.handshaken = true
  end

  while client do
    local opcode, payload, fin, consumed = ws_decode_frame(ws.buffer)
    if not opcode then
      break
    end
    ws.buffer = ws.buffer:sub(consumed + 1)
    if opcode == 0x8 then
      ws_close_client()
      break
    elseif opcode == 0x9 then
      client:write(ws_encode(0xA, payload))
    elseif opcode <= 0x2 then
      table.insert(ws.fragments, payload)
      if fin then
        local message = table.concat(ws.fragments)
        ws.fragments = {}
        ws_handle_message(message)
      end
    end
  end
end

---Start the editor-integration server. Returns true when the server is listening.
---@return boolean
function M.start()
  if ws.disabled then
    return false
  end
  if server then
    return true
  end
  local uv = vim.uv or vim.loop
  local new_server = uv.new_tcp()
  local ok, err = pcall(function()
    assert(new_server:bind("127.0.0.1", 0))
    assert(new_server:listen(128, function(listen_err)
      if listen_err then
        return
      end
      local new_client = uv.new_tcp()
      new_server:accept(new_client)
      ws_close_client()
      client = new_client
      new_client:read_start(function(read_err, chunk)
        if read_err or not chunk then
          vim.schedule(ws_close_client)
          return
        end
        ws.buffer = ws.buffer .. chunk
        if #ws.buffer > MAX_BUFFER_SIZE then
          vim.schedule(function()
            notify("Kilo editor integration: closing a connection that exceeded the buffer limit.", vim.log.levels.WARN)
            ws_close_client()
          end)
          return
        end
        vim.schedule(ws_process)
      end)
    end))
  end)
  if not ok then
    pcall(function()
      new_server:close()
    end)
    ws.disabled = true
    notify("Kilo editor integration disabled: " .. tostring(err), vim.log.levels.WARN)
    return false
  end
  server = new_server
  ws.port = new_server:getsockname().port
  return true
end

---Port the editor server listens on, when it is running.
---@return integer|nil
function M.port()
  return ws.port
end

---Send a file mention over the editor channel, or queue it until Kilo connects.
---Returns true when the mention went (or will go) over the channel; false when no Kilo is
---connected and the caller should fall back to typing the mention into the terminal.
---@param path string
---@param first_line integer
---@param last_line integer
---@return boolean
function M.mention(path, first_line, last_line)
  if ws.ready then
    ws_send_mention(path, first_line, last_line)
    return true
  end
  if client and #ws.pending < 20 then
    table.insert(ws.pending, { path = path, first_line = first_line, last_line = last_line })
    return true
  end
  return false
end

---Current editor-integration state for :checkhealth.
---@return { disabled: boolean, connected: boolean, ready: boolean, port: integer|nil }
function M.status()
  return {
    disabled = ws.disabled,
    connected = client ~= nil,
    ready = ws.ready,
    port = ws.port,
  }
end

---@private
M._test = {
  encode = ws_encode,
  decode = ws_decode_frame,
}

return M
