local bit = require("bit")
local editor = require("kilo.editor")

local spec = {}

local function roundtrip(payload)
  local frame = editor._test.encode(1, payload)
  local opcode, decoded, fin, consumed = editor._test.decode(frame)
  assert(opcode == 1)
  assert(decoded == payload)
  assert(fin == true)
  assert(consumed == #frame)
end

function spec.encode_decode_short()
  roundtrip("hello")
end

function spec.encode_decode_126_length()
  roundtrip(string.rep("a", 200))
end

function spec.encode_decode_127_length()
  roundtrip(string.rep("b", 70000))
end

function spec.encode_decode_empty()
  roundtrip("")
end

function spec.decode_masked_frame()
  local payload = "masked-payload"
  local mask = { 0x11, 0x22, 0x33, 0x44 }
  local masked = {}
  for i = 1, #payload do
    masked[i] = string.char(bit.bxor(payload:byte(i), mask[(i - 1) % 4 + 1]))
  end
  local frame = string.char(0x81, 0x80 + #payload, mask[1], mask[2], mask[3], mask[4]) .. table.concat(masked)
  local opcode, decoded = editor._test.decode(frame)
  assert(opcode == 1)
  assert(decoded == payload)
end

function spec.decode_incomplete_returns_nil()
  local opcode = editor._test.decode(string.char(0x81, 0x05, 0x68))
  assert(opcode == nil)
end

return spec
