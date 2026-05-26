local minidoc = require("mini.doc")

if _G.MiniDoc == nil then
  minidoc.setup()
end

MiniDoc.generate({ "lua/tiny-treesitter/init.lua" }, "doc/tiny-treesitter.txt")
