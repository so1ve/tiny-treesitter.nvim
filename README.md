# tiny-treesitter.nvim

Tiny Tree-sitter parser management for Neovim.

This plugin keeps the fast parser installation workflow inspired by `nvim-treesitter` while dropping its feature modules. It vendors `arborist.nvim` registry data plus `arborist.nvim` query files, then exposes a small installer API for existing configs.

## Why

`nvim-treesitter` is excellent at installing parsers quickly:

```text
curl GitHub tarball
→ tar extract
→ tree-sitter build
→ install parser
```

For configs that already use Neovim's native Tree-sitter APIs directly, the rest of `nvim-treesitter` is unnecessary. tiny-treesitter.nvim keeps only the installer surface:

- parser registry generated from `arborist-ts/arborist.nvim/registry`
- Arborist query files
- `:TSInstall`, `:TSUpdate`, `:TSUninstall`, `:TSInstallInfo`
- `require("tiny-treesitter").install/update/uninstall/get_available/get_installed/setup`

It does **not** provide highlighting modules, indentation modules, textobjects, or feature toggles.

## Requirements

- Neovim 0.12+
- `curl`
- `tar`
- `tree-sitter` CLI 0.26.1+
- C compiler available to `tree-sitter build`

## Installation

### `lazy.nvim`

```lua
{
  "so1ve/tiny-treesitter.nvim",
  lazy = false,
  build = function()
    require("tiny-treesitter").install({ "lua", "vim", "vimdoc" }, { wait = true })
  end,
}
```

> [!TIP]
> If you intentionally use this plugin as a drop-in shim for another lazy.nvim dependency name, add `name = "..."` to the spec. For example, `name = "nvim-treesitter"` makes dependencies that still request `nvim-treesitter/nvim-treesitter` resolve to this installer-only shim. Omit `name` when every dependent spec already references `so1ve/tiny-treesitter.nvim` explicitly.

## Usage

```vim
:TSInstall lua vim vimdoc
:TSUpdate
:TSUninstall lua
:TSInstallInfo
```

Lua API:

```lua
require("tiny-treesitter").setup({
  install_dir = vim.fn.stdpath("data") .. "/site",
  ensure_installed = { "lua", "vim", "vimdoc" },
  auto_install = false,
})

require("tiny-treesitter").install({ "lua", "typescript", "vue" })
require("tiny-treesitter").update()
require("tiny-treesitter").uninstall("lua")
```

Installs and updates are asynchronous by default. They run parser jobs concurrently, so `:TSInstall` and `:TSUpdate` return without freezing the UI. Use `{ wait = true }` only in build hooks or scripts that must block until the operation finishes:

```lua
local ok = require("tiny-treesitter").install({ "lua", "vim" }, { wait = true })
```

Set `auto_install = true` to install missing parsers when a buffer's `FileType` event is seen.

## Documentation

See `:help tiny-treesitter` for the full generated help text, or read [`doc/tiny-treesitter.txt`](./doc/tiny-treesitter.txt) directly.

The help file is generated from Lua annotations with [`mini.doc`](https://github.com/nvim-mini/mini.doc).

## Notes

This plugin installs parsers and query files only. Start Tree-sitter with Neovim's native APIs:

```lua
vim.api.nvim_create_autocmd("FileType", {
  callback = function(event)
    local parser = vim.treesitter.language.get_lang(vim.bo[event.buf].filetype)

    if parser and vim.treesitter.language.add(parser) == true then
      vim.treesitter.start(event.buf, parser)
    end
  end,
})
```

### Updating generated registry

`lua/tiny-treesitter/parsers.lua` and `plugin/filetypes.lua` are generated from `arborist-ts/arborist.nvim/registry`:

```bash
node scripts/update-registry.mjs
```

Optional environment variable:

- `REGISTRY_SOURCE_URL`: raw registry base URL. Defaults to `https://raw.githubusercontent.com/arborist-ts/arborist.nvim/main/registry`.

Generated registry files are intentionally ignored by Stylua.

### Updating vendored queries

`runtime/queries` is vendored from `arborist-ts/queries`. The Arborist repository stores query files under top-level `queries/`; this updater copies those language directories into this plugin's `runtime/queries` source cache.

Refresh it periodically with:

```bash
node scripts/update-queries.mjs
```

Optional environment variables:

- `QUERY_SOURCE_REF`: upstream branch, tag, or commit to vendor. Defaults to `main`.
- `QUERY_SOURCE_URL`: upstream repository URL. Defaults to `https://github.com/arborist-ts/queries`.
- `TINY_TREESITTER_UPDATE_QUERIES_DRY_RUN=1`: print what would be updated without touching files.

## 📝 License

The generated parser registry and filetype aliases are derived from `arborist-ts/arborist.nvim`; vendored queries are derived from `arborist-ts/queries`.

[MIT](./LICENSE). Made with ❤️ by [Ray](https://github.com/so1ve)
