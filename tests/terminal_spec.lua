local terminal = require("kilo.terminal")

local spec = {}

function spec.split_height_ratio()
  vim.g.kilo_opts = { height = 0.5 }
  vim.o.cmdheight = 1
  local expected = math.max(1, math.floor((vim.o.lines - 1) * 0.5))
  assert(terminal.split_height() == expected)
end

function spec.split_height_rows()
  vim.g.kilo_opts = { height = 15 }
  assert(terminal.split_height() == 15)
end

function spec.split_height_invalid_falls_back()
  vim.g.kilo_opts = { height = 0 }
  vim.o.cmdheight = 1
  local expected = math.max(1, math.floor((vim.o.lines - 1) * 0.30))
  assert(terminal.split_height() == expected)
end

function spec.split_height_non_number_falls_back()
  vim.g.kilo_opts = { height = "half" }
  vim.o.cmdheight = 1
  local expected = math.max(1, math.floor((vim.o.lines - 1) * 0.30))
  assert(terminal.split_height() == expected)
end

function spec.split_height_respects_cmdheight()
  vim.g.kilo_opts = { height = 0.5 }
  vim.o.cmdheight = 2
  local expected = math.max(1, math.floor((vim.o.lines - 2) * 0.5))
  assert(terminal.split_height() == expected)
end

function spec.split_width_ratio()
  vim.g.kilo_opts = { width = 0.4 }
  local expected = math.max(1, math.floor(vim.o.columns * 0.4))
  assert(terminal.split_width() == expected)
end

function spec.split_width_columns()
  vim.g.kilo_opts = { width = 40 }
  assert(terminal.split_width() == 40)
end

function spec.split_width_invalid_falls_back()
  vim.g.kilo_opts = { width = 0 }
  local expected = math.max(1, math.floor(vim.o.columns * 0.40))
  assert(terminal.split_width() == expected)
end

function spec.split_width_non_number_falls_back()
  vim.g.kilo_opts = { width = "wide" }
  local expected = math.max(1, math.floor(vim.o.columns * 0.40))
  assert(terminal.split_width() == expected)
end

function spec.other_side_flips()
  assert(terminal._test.other_side("bottom") == "right")
  assert(terminal._test.other_side("right") == "bottom")
end

function spec.context_single_line()
  vim.fn.chdir("/tmp")
  local base = vim.fn.getcwd()
  local path = base .. "/bar.lua"
  assert(terminal.context_for_range(path, 5, 5) == "@bar.lua#5")
end

function spec.context_range()
  vim.fn.chdir("/tmp")
  local base = vim.fn.getcwd()
  local path = base .. "/bar.lua"
  assert(terminal.context_for_range(path, 5, 9) == "@bar.lua#5-9")
end

function spec.context_outside_cwd_uses_absolute()
  vim.fn.chdir("/tmp")
  local base = vim.fn.getcwd()
  local path = base .. "/bar.lua"
  vim.fn.mkdir(base .. "/sub", "p")
  vim.fn.chdir(base .. "/sub")
  local rel = vim.fs.relpath(vim.fn.getcwd(), path) or path
  assert(terminal.context_for_range(path, 5, 9) == "@" .. rel .. "#5-9")
end

return spec
