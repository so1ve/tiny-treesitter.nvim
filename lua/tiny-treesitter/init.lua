--- Tiny Tree-sitter parser manager for Neovim
---
--- tiny-treesitter.nvim installs Tree-sitter parser libraries and query files.
--- It intentionally does not provide highlighting modules, indentation modules,
--- textobjects, or feature toggles. Start Tree-sitter with Neovim's native APIs
--- after installing parsers.
---
--- # Requirements ~
---
--- - Neovim 0.12+
--- - `curl`
--- - `tar`
--- - `tree-sitter` CLI 0.26.1+
--- - C compiler available to `tree-sitter build`
---
--- # Setup ~
---
--- >lua
---   require("tiny-treesitter").setup({
---     install_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "site"),
---     ensure_installed = { "lua", "vim", "vimdoc" },
---     auto_install = true,
---   })
--- <
---
--- See |tiny-treesitter.setup()| for setup options and
--- |tiny-treesitter.install()| for install/update options.
---@tag tiny-treesitter

local TinyTreesitter = {}

--- Configure tiny-treesitter.
---
---@class TinyTreesitterConfig
---
---@field install_dir string|nil Runtime directory that receives `parser/`,
--- `parser-info/`, and `queries/`. Default:
--- `vim.fs.joinpath(vim.fn.stdpath("data"), "site")`. When explicitly set, it is
--- prepended to 'runtimepath'.
---
---@field ensure_installed string|string[]|nil Parser names to install
--- asynchronously when setup() is called. Supports the same language expansion
--- as |tiny-treesitter.install()|, including `"all"`.
---
---@field auto_install boolean|nil Install a missing parser asynchronously when a
--- normal buffer's |FileType| event resolves to that parser. Special buffers like
--- plugin UI, quickfix, terminal, and help buffers are ignored. Default: `false`.
---
---@param opts TinyTreesitterConfig|nil Setup options.
---@return any
---@tag tiny-treesitter.setup()
function TinyTreesitter.setup(...)
  return require("tiny-treesitter.config").setup(...)
end

--- Get available parser names.
---
---@return string[]
---@tag tiny-treesitter.get_available()
function TinyTreesitter.get_available(...)
  return require("tiny-treesitter.config").get_available(...)
end

--- Get installed parser/query names.
---
---@param kind string|nil Optional filter: `"parsers"` or `"queries"`.
---@return string[]
---@tag tiny-treesitter.get_installed()
function TinyTreesitter.get_installed(...)
  return require("tiny-treesitter.config").get_installed(...)
end

--- Install parsers and queries.
---
--- Without `opts.wait`, this returns an async task handle. With `opts.wait`, it
--- returns `success, failures` directly.
---
---@class TinyTreesitterInstallOptions
---
---@field max_jobs number|nil Maximum number of parser jobs to run concurrently.
--- Default: `100`.
---
---@field wait boolean|nil If true, block until the async task finishes and
--- return `success, failures`. Without `wait`, the API returns a task handle.
---
---@field timeout number|nil Timeout in milliseconds used by the task handle when
--- `wait = true`.
---
---@field callback fun(success:boolean, failures:table)|nil Called when an async
--- task completes.
---
---@field summary boolean|nil Show a final summary notification for
--- multi-language install/update tasks.
---
---@field force boolean|nil Reinstall even if the parser exists and the recorded
--- revision matches. Also set by |:TSInstall!|.
---
---@field generate boolean|nil Run `tree-sitter generate` before building. Used
--- by |:TSInstallFromGrammar|.
---
---@param languages string|string[] Parser name, parser names, or `"all"`.
---@param opts TinyTreesitterInstallOptions|nil Install options.
---@return any
---@tag tiny-treesitter.install()
function TinyTreesitter.install(...)
  return require("tiny-treesitter.install").install(...)
end

--- Update installed parsers whose registry revision changed.
---
---@param languages string|string[]|nil Parser names. Defaults to installed parsers.
---@param opts TinyTreesitterInstallOptions|nil Update options.
---@return any
---@tag tiny-treesitter.update()
function TinyTreesitter.update(...)
  return require("tiny-treesitter.install").update(...)
end

--- Remove installed parser, revision, and query files.
---
---@param languages string|string[]|nil Parser names. Defaults to installed parsers.
---@param opts TinyTreesitterInstallOptions|nil Uninstall options.
---@return any
---@tag tiny-treesitter.uninstall()
function TinyTreesitter.uninstall(...)
  return require("tiny-treesitter.install").uninstall(...)
end

return TinyTreesitter
