local config = require("kilo.config")

local spec = {}

function spec.defaults_when_no_opts()
  vim.g.kilo_opts = nil
  local opts = config.get()
  assert(opts.height == 0.30)
  assert(opts.width == 0.40)
  assert(opts.side == "right")
  assert(opts.keys.toggle == "<leader>k.")
  assert(opts.keys.range == "<leader>kr")
  assert(opts.keys.line == "<leader>kl")
  assert(opts.keys.side == "<leader>ks")
end

function spec.merges_user_opts_over_defaults()
  vim.g.kilo_opts = { height = 0.5 }
  local opts = config.get()
  assert(opts.height == 0.5)
  assert(opts.keys.toggle == "<leader>k.")
end

function spec.keys_false_disables_all()
  vim.g.kilo_opts = { keys = false }
  local opts = config.get()
  assert(opts.keys == false)
end

function spec.partial_keys_keep_defaults()
  vim.g.kilo_opts = { keys = { line = false } }
  local opts = config.get()
  assert(opts.keys.line == false)
  assert(opts.keys.toggle == "<leader>k.")
  assert(opts.keys.range == "<leader>kr")
  assert(opts.keys.side == "<leader>ks")
end

function spec.get_returns_fresh_table()
  vim.g.kilo_opts = nil
  local a = config.get()
  a.height = 99
  assert(config.get().height == 0.30)
end

function spec.number_valid_passththrough()
  assert(config.number("height", 0.5) == 0.5)
  assert(config.number("width", 40) == 40)
end

function spec.number_invalid_falls_back()
  assert(config.number("height", 0) == 0.30)
  assert(config.number("height", "half") == 0.30)
  assert(config.number("width", -5) == 0.40)
end

function spec.side_valid_passthrough()
  assert(config.side("bottom") == "bottom")
  assert(config.side("right") == "right")
end

function spec.side_invalid_falls_back()
  assert(config.side("left") == "right")
  assert(config.side(3) == "right")
end

return spec
