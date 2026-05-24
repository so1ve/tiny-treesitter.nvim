local M = {}

function M.setup(...)
  return require("tiny-treesitter.config").setup(...)
end

function M.get_available(...)
  return require("tiny-treesitter.config").get_available(...)
end

function M.get_installed(...)
  return require("tiny-treesitter.config").get_installed(...)
end

function M.install(...)
  return require("tiny-treesitter.install").install(...)
end

function M.update(...)
  return require("tiny-treesitter.install").update(...)
end

function M.uninstall(...)
  return require("tiny-treesitter.install").uninstall(...)
end

return M
