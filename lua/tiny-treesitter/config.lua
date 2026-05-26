local M = {}

local config = {
  install_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "site"),
  ensure_installed = {},
  auto_install = false,
}

local install_dir_added = false

local function is_normal_buffer(buf)
  return vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == ""
end

function M.setup(opts)
  opts = opts or {}

  if opts.install_dir then
    opts.install_dir = vim.fs.normalize(opts.install_dir)
  end

  config = vim.tbl_deep_extend("force", config, opts)

  if opts.install_dir and not install_dir_added then
    vim.opt.runtimepath:prepend(config.install_dir)
    install_dir_added = true
  end

  if opts.ensure_installed then
    require("tiny-treesitter.install").install(config.ensure_installed, { summary = true })
  end

  if config.auto_install then
    vim.api.nvim_create_autocmd("FileType", {
      group = vim.api.nvim_create_augroup("TinyTreesitterAutoInstall", { clear = true }),
      desc = "Install missing Tree-sitter parser on demand",
      callback = function(event)
        if not is_normal_buffer(event.buf) then
          return
        end

        local parser = vim.treesitter.language.get_lang(vim.bo[event.buf].filetype)

        if not parser or vim.list_contains(M.get_installed("parsers"), parser) then
          return
        end

        require("tiny-treesitter.install").install(parser)
      end,
    })
  end
end

function M.get()
  return config
end

function M.get_install_dir(name)
  local dir = vim.fs.joinpath(config.install_dir, name)

  vim.fn.mkdir(dir, "p")

  return dir
end

local function parser_name(file)
  return file:match("^(.+)%.so$")
end

function M.get_installed(kind)
  local installed = {}

  if kind ~= "queries" then
    local parser_dir = M.get_install_dir("parser")

    for file in vim.fs.dir(parser_dir) do
      local name = parser_name(file)

      if name then
        installed[name] = true
      end
    end
  end

  if kind ~= "parsers" then
    local query_dir = M.get_install_dir("queries")

    for file in vim.fs.dir(query_dir) do
      installed[file] = true
    end
  end

  return vim.tbl_keys(installed)
end

function M.get_available()
  vim.api.nvim_exec_autocmds("User", { pattern = "TSUpdate" })

  local parsers = require("tiny-treesitter.parsers")
  local languages = vim.tbl_keys(parsers)

  table.sort(languages)

  return languages
end

function M.norm_languages(languages, skip)
  skip = skip or {}

  if not languages then
    return {}
  end

  if type(languages) == "string" then
    languages = { languages }
  end

  if vim.list_contains(languages, "all") then
    languages = skip.missing and M.get_installed() or M.get_available()
  end

  local installed = M.get_installed()

  if skip.installed then
    languages = vim.tbl_filter(function(lang)
      return not vim.list_contains(installed, lang)
    end, languages)
  end

  if skip.missing then
    languages = vim.tbl_filter(function(lang)
      return vim.list_contains(installed, lang)
    end, languages)
  end

  local parsers = require("tiny-treesitter.parsers")

  languages = vim.tbl_filter(function(lang)
    if parsers[lang] then
      return true
    end

    vim.notify("Skipping unknown parser: " .. lang, vim.log.levels.WARN)
    return false
  end, languages)

  if not skip.dependencies then
    for _, lang in ipairs(vim.deepcopy(languages)) do
      if parsers[lang] and parsers[lang].requires then
        vim.list_extend(languages, parsers[lang].requires)
      end
    end
  end

  return vim.list.unique(languages)
end

return M
