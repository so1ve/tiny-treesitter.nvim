local M = {}

local config = {
  install_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "site"),
  ensure_installed = {},
  auto_install = false,
  auto_update = true,
  ignore = {},
}

local install_dir_added = false
local auto_update_checked = false

local function is_normal_buffer(buf)
  return vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == ""
end

local function is_ignored(name)
  return vim.list_contains(config.ignore, name)
end

local function resolve_language(lang, parsers)
  if parsers[lang] then
    return lang
  end

  local resolved = vim.treesitter.language.get_lang(lang)

  if resolved and parsers[resolved] then
    return resolved
  end

  return lang
end

local function is_ignored_language(lang, parsers)
  if is_ignored(lang) then
    return true
  end

  for _, ignored in ipairs(config.ignore) do
    if resolve_language(ignored, parsers) == lang then
      return true
    end
  end

  return false
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
    require("tiny-treesitter.install").install(config.ensure_installed, { summary = true, ignore = true })
  end

  if config.auto_update and not auto_update_checked then
    auto_update_checked = true
    require("tiny-treesitter.install").update(nil, { ignore = true })
  end

  if config.auto_install then
    vim.api.nvim_create_autocmd("FileType", {
      group = vim.api.nvim_create_augroup("TinyTreesitterAutoInstall", { clear = true }),
      desc = "Install missing Tree-sitter parser on demand",
      callback = function(event)
        if not is_normal_buffer(event.buf) then
          return
        end

        local filetype = vim.bo[event.buf].filetype
        local parser = vim.treesitter.language.get_lang(filetype)

        if not parser or is_ignored(filetype) or is_ignored(parser) then
          return
        end

        local parsers = require("tiny-treesitter.parsers")

        -- Some registered filetype aliases resolve to query-only language names
        -- that are not standalone parser registry entries, e.g. JavaScript can
        -- resolve to `ecma`. Fall back to the original filetype when it is the
        -- installable parser name.
        if not parsers[parser] then
          if not parsers[filetype] then
            return
          end

          parser = filetype
        end

        if vim.list_contains(M.get_installed("parsers"), parser) then
          return
        end

        require("tiny-treesitter.install").install(parser)
      end,
    })
  end
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

  local parsers = require("tiny-treesitter.parsers")

  languages = vim.tbl_map(function(lang)
    return resolve_language(lang, parsers)
  end, languages)

  local installed = M.get_installed()

  if skip.missing then
    languages = vim.tbl_filter(function(lang)
      return vim.list_contains(installed, lang)
    end, languages)
  end

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

  if skip.ignore then
    languages = vim.tbl_filter(function(lang)
      return not is_ignored_language(lang, parsers)
    end, languages)
  end

  return vim.list.unique(languages)
end

return M
