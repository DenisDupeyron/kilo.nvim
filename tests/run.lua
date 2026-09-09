local root = vim.fn.getcwd()
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
vim.opt.runtimepath:append(root)

local specs = { "tests.config_spec", "tests.terminal_spec", "tests.editor_spec" }
local total_passed, total_failed = 0, 0

for _, name in ipairs(specs) do
  local spec = require(name)
  for test_name, fn in pairs(spec) do
    local ok, err = pcall(fn)
    if ok then
      total_passed = total_passed + 1
      print("PASS " .. name .. "." .. test_name)
    else
      total_failed = total_failed + 1
      print("FAIL " .. name .. "." .. test_name .. ": " .. tostring(err))
    end
  end
end

print(string.format("%d passed, %d failed", total_passed, total_failed))
if total_failed > 0 then
  os.exit(1)
end
