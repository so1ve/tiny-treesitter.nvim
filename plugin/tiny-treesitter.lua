if vim.g.loaded_tiny_treesitter then
  return
end

vim.g.loaded_tiny_treesitter = true

local function complete_available(arglead)
  return vim.tbl_filter(function(lang)
    return lang:find(arglead, 1, true) ~= nil
  end, require("tiny-treesitter.config").get_available())
end

local function complete_installed(arglead)
  return vim.tbl_filter(function(lang)
    return lang:find(arglead, 1, true) ~= nil
  end, require("tiny-treesitter.config").get_installed())
end

vim.api.nvim_create_user_command("TSInstall", function(args)
  require("tiny-treesitter").install(args.fargs, { force = args.bang, summary = true })
end, {
  nargs = "+",
  bang = true,
  bar = true,
  complete = complete_available,
  desc = "Install Tree-sitter parsers",
})

vim.api.nvim_create_user_command("TSInstallFromGrammar", function(args)
  require("tiny-treesitter").install(args.fargs, {
    force = args.bang,
    generate = true,
    summary = true,
  })
end, {
  nargs = "+",
  bang = true,
  bar = true,
  complete = complete_available,
  desc = "Generate and install Tree-sitter parsers",
})

vim.api.nvim_create_user_command("TSUpdate", function(args)
  require("tiny-treesitter").update(args.fargs, { summary = true })
end, {
  nargs = "*",
  bar = true,
  complete = complete_installed,
  desc = "Update installed Tree-sitter parsers",
})

vim.api.nvim_create_user_command("TSUninstall", function(args)
  require("tiny-treesitter").uninstall(args.fargs, { summary = true })
end, {
  nargs = "+",
  bar = true,
  complete = complete_installed,
  desc = "Uninstall Tree-sitter parsers",
})

vim.api.nvim_create_user_command("TSInstallInfo", function()
  local installed = {}

  for _, lang in ipairs(require("tiny-treesitter").get_installed()) do
    installed[lang] = true
  end

  local lines = {}

  for _, lang in ipairs(require("tiny-treesitter").get_available()) do
    lines[#lines + 1] = string.format("%s %s", installed[lang] and "✓" or " ", lang)
  end

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Tree-sitter parsers" })
end, {
  desc = "Show Tree-sitter parser install status",
})
