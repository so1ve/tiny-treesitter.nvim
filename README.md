# tiny-treesitter.nvim

Tiny Tree-sitter parser management for Neovim.

This plugin keeps the fast parser installation workflow inspired by `nvim-treesitter` behind a small installer API. Its bundled parser registry, filetype aliases, and queries come from pinned nvim-treesitter and Arborist revisions. nvim-treesitter entries are kept on conflicts, while Arborist adds missing languages.

The bundled data is intentional: parser revisions and query files move together with the plugin version. Updating tiny-treesitter.nvim updates the local registry and query bundle; installed parsers can then be reconciled against that bundled registry without fetching remote metadata first.

## Why

`nvim-treesitter` is excellent at installing parsers quickly:

```text
curl GitHub tarball
→ tar extract
→ tree-sitter build
→ install parser
```

For configs that use Neovim's native Tree-sitter APIs directly, tiny-treesitter.nvim keeps only the installer surface:

- parser registry, filetype aliases, and queries vendored from `nvim-treesitter`
- parser and query additions from one Arborist commit when their language is absent upstream
- `:TSInstall`, `:TSUpdate`, `:TSUninstall`, `:TSInstallInfo`
- `require("tiny-treesitter").install/update/uninstall/get_available/get_installed/setup`

It does **not** provide highlighting modules, indentation modules, textobjects, or feature toggles.

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
| `ensure_installed` | `{}` | Parser names to install when `setup()` runs. |
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

## Comparison

| Project | Scope | Registry / queries | Parser build model | Best for |
| --- | --- | --- | --- | --- |
| `tiny-treesitter.nvim` | Small installer API with automatic install/update conveniences | Bundled data from nvim-treesitter and Arborist revisions | `curl` GitHub tarball → `tar` extract → `tree-sitter build` | Configs that want native Neovim Tree-sitter APIs with a compact compatibility surface and a slightly wider registry. |
| `nvim-treesitter` | Official parser/query installer with experimental indentation support | Its own parser definitions, filetypes, and queries | `curl` parser archive → extract/build/install | Users who want the official data and API directly, or its experimental indentation integration. |
| `arborist.nvim` | Automatic parser manager | Bundled Arborist registry and queries | WASM-first, then native build fallback | Users who want automatic parser install/start behavior managed by one plugin. |
| `tree-sitter-manager.nvim` | Parser manager with TUI | Bundled queries plus user-overridable parser sources | Clone parser repos → `tree-sitter` CLI build | Users who want an interactive manager UI, custom/fork parser sources, and optional auto-install/highlight behavior. |

tiny-treesitter.nvim intentionally keeps a narrow feature set. It uses GitHub tarballs instead of `git clone`, avoids a manager UI and runtime feature modules, runs parser jobs concurrently, and leaves starting Tree-sitter, highlighting, indentation, and higher-level modules to your own config or other plugins.

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

### Updating vendored data

```bash
node scripts/update-vendor.mjs
```

The source refs default to `main` and can be selected explicitly:

```bash
node scripts/update-vendor.mjs --nvim-ref main --arborist-ref main
```

The weekly [`update-vendor` workflow](./.github/workflows/update-vendor.yml) runs this same command, then proposes the complete update as one pull request.

## 📝 License

[MIT](./LICENSE). Made with ❤️ by [Ray](https://github.com/so1ve)

Vendored `nvim-treesitter` data is distributed under [Apache-2.0 license](./LICENSES/nvim-treesitter.txt), and Arborist data under [MIT license](./LICENSES/arborist.nvim.txt).
