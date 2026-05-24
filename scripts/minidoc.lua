local minidoc_path = vim.env.MINIDOC_PATH

if minidoc_path and minidoc_path ~= "" then
  vim.opt.runtimepath:prepend(minidoc_path)
end

local minidoc = require("mini.doc")

if _G.MiniDoc == nil then
  minidoc.setup()
end

MiniDoc.generate({ "lua/tiny-treesitter/init.lua" }, "doc/tiny-treesitter.txt")
