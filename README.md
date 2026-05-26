# tiny-treesitter.nvim

Tiny Tree-sitter parser management for Neovim.

This plugin keeps the fast parser installation workflow inspired by `nvim-treesitter` while dropping its feature modules. It bundles Arborist registry data plus Arborist query files, then exposes a small installer API for existing configs.

The bundled data is intentional: parser revisions and query files move together with the plugin version. Updating tiny-treesitter.nvim updates the local registry and query bundle; installed parsers can then be reconciled against that bundled registry without fetching remote metadata first.

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
- bundled Arborist query files
- `:TSInstall`, `:TSUpdate`, `:TSUninstall`, `:TSInstallInfo`
- `require("tiny-treesitter").install/update/uninstall/get_available/get_installed/setup`

It does **not** provide highlighting modules, indentation modules, textobjects, or feature toggles.

## Comparison

| Project | Scope | Registry / queries | Parser build model | Best for |
| --- | --- | --- | --- | --- |
| `tiny-treesitter.nvim` | Tiny installer-only surface | Bundled Arborist registry and queries | `curl` GitHub tarball → `tar` extract → `tree-sitter build` | Configs that want fast parser/query management without git clones, manager UI, highlight modules, indentation modules, or textobjects. |
| `nvim-treesitter` | Full Tree-sitter plugin ecosystem | Own parser/query data plus feature modules | Installer plus highlight, indent, textobject, and module integrations | Users who want the traditional all-in-one Tree-sitter plugin surface. |
| `arborist.nvim` | Automatic parser manager | Bundled Arborist registry and queries | WASM-first, then native build fallback | Users who want automatic parser install/start behavior managed by one plugin. |
| `tree-sitter-manager.nvim` | Parser manager with TUI | Bundled queries plus user-overridable parser sources | Clone parser repos → `tree-sitter` CLI build | Users who want an interactive manager UI, custom/fork parser sources, and optional auto-install/highlight behavior. |

tiny-treesitter.nvim intentionally keeps the smallest feature set in this comparison. It uses GitHub tarballs instead of `git clone`, avoids manager UI and runtime feature modules, runs parser jobs concurrently, and leaves starting Tree-sitter, highlighting, indentation, and higher-level modules to your own config or other plugins.

## Requirements

- Neovim 0.12+
- `curl`
- `tar`
- `tree-sitter` CLI 0.26.1+
- C compiler available to `tree-sitter build`

Run `:checkhealth tiny-treesitter` to verify the local toolchain, bundled
registry, bundled queries, and installed parser revisions.

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
  auto_update = true,
  ignore = {},
})

require("tiny-treesitter").install({ "lua", "typescript", "vue" })
require("tiny-treesitter").update()
require("tiny-treesitter").uninstall("lua")
```

Setup options:

| Option | Default | Description |
| --- | --- | --- |
| `install_dir` | `vim.fs.joinpath(vim.fn.stdpath("data"), "site")` | Runtime directory that receives `parser/`, `parser-info/`, and `queries/`. |
| `ensure_installed` | `{}` | Parser names to install when `setup()` runs. Supports parser names and `"all"`. |
| `auto_install` | `false` | Install missing parsers when a normal buffer's `FileType` event resolves to that parser. |
| `auto_update` | `true` | Check installed parser revisions against the bundled registry on startup and rebuild outdated parsers. |
| `ignore` | `{}` | Parser names or filetypes to skip for automatic install/update only. Explicit installs are still allowed. |

Installs and updates are asynchronous by default. They run parser jobs concurrently, so `:TSInstall` and `:TSUpdate` return without freezing the UI. Use `{ wait = true }` only in build hooks or scripts that must block until the operation finishes:

> [!INFO]
>
> To control install behavior, use the Lua API instead of adding more setup
> options. `setup()` intentionally exposes only a minimal compatibility surface
> for nvim-treesitter-style configs: where to install parsers, what to install
> automatically, and what automatic work to skip. Fine-grained controls such as
> waiting, summaries, forced reinstalls, grammar generation, and job limits belong
> to explicit `install()` / `update()` calls.

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
