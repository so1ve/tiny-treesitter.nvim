local async = require("tiny-treesitter.async")
local config = require("tiny-treesitter.config")
local util = require("tiny-treesitter.util")

local M = {}

local installing = {}
local install_results = {}

local function parser_lib(lang)
  return vim.fs.joinpath(config.get_install_dir("parser"), lang .. ".so")
end

local function parser_revision_file(lang)
  return vim.fs.joinpath(config.get_install_dir("parser-info"), lang .. ".revision")
end

local function get_parser_info(lang)
  return require("tiny-treesitter.parsers")[lang]
end

local function get_install_info(lang)
  local parser = get_parser_info(lang)

  return parser and parser.install_info
end

local function upstream_root()
  local paths = vim.api.nvim_get_runtime_file("lua/tiny-treesitter/parsers.lua", true)

  for _, path in ipairs(paths) do
    local root = vim.fn.fnamemodify(path, ":p:h:h:h")

    if root ~= vim.fn.stdpath("config") then
      return root
    end
  end
end

local function query_source(lang)
  local root = upstream_root()

  if not root then
    return nil
  end

  local path = vim.fs.joinpath(root, "runtime", "queries", lang)

  if vim.uv.fs_stat(path) then
    return path
  end
end

local function installed_revision(lang)
  return util.read_file(parser_revision_file(lang))
end

local function notify(message, level)
  if vim.in_fast_event() then
    vim.schedule(function()
      notify(message, level)
    end)
    return
  end

  vim.notify(message, level or vim.log.levels.INFO, { title = "treesitter install" })
end

local function run(cmd, opts, context)
  local result = async.system(cmd, opts)

  if result.code ~= 0 then
    local stderr = result.stderr and vim.trim(result.stderr) or ""

    return string.format("%s failed: %s", context, stderr ~= "" and stderr or table.concat(cmd, " "))
  end
end

local function concurrency(opts)
  local requested = tonumber(opts.max_jobs)

  if requested and requested > 0 then
    return requested
  end

  return 100
end

local function download(info, lang, cache_dir)
  local revision = info.revision or info.branch or "main"
  local url = info.url:gsub("%.git$", "")
  local project_name = "tree-sitter-" .. lang .. "-" .. tostring(vim.uv.hrtime())
  local tarball = vim.fs.joinpath(cache_dir, project_name .. ".tar.gz")
  local project_dir = vim.fs.joinpath(cache_dir, project_name)
  local tmp_dir = project_dir .. "-tmp"
  local archive_url = string.format("%s/archive/%s.tar.gz", url, revision)

  util.rmpath(project_dir)
  util.rmpath(tmp_dir)

  local err = run({
    "curl",
    "--silent",
    "--fail",
    "--show-error",
    "--retry",
    "7",
    "-L",
    archive_url,
    "--output",
    tarball,
  }, nil, "download " .. lang)

  if err then
    return nil, revision, err
  end

  vim.fn.mkdir(tmp_dir, "p")

  err = run({ "tar", "-xzf", project_name .. ".tar.gz", "-C", project_name .. "-tmp" }, {
    cwd = cache_dir,
  }, "extract " .. lang)

  pcall(vim.uv.fs_unlink, tarball)

  if err then
    return nil, revision, err
  end

  local dir_revision = revision:find("^v%d") and revision:sub(2) or revision
  local repo_name = url:match("[^/]+$")
  local extracted = vim.fs.joinpath(tmp_dir, repo_name .. "-" .. dir_revision)
  local ok, rename_err = vim.uv.fs_rename(extracted, project_dir)

  util.rmpath(tmp_dir)

  if not ok then
    return nil, revision, "rename extracted parser failed: " .. tostring(rename_err)
  end

  return project_dir, revision
end

local function generate_parser(info, compile_dir, lang, force_generate)
  if not (info.generate or force_generate) then
    return nil
  end

  local from_json = info.generate_from_json ~= false
  local cmd = {
    "tree-sitter",
    "generate",
    "--abi",
    tostring(vim.treesitter.language_version),
  }

  if from_json then
    table.insert(cmd, "src/grammar.json")
  end

  return run(cmd, {
    cwd = compile_dir,
    env = { TREE_SITTER_JS_RUNTIME = "native" },
  }, "generate " .. lang)
end

local function compile_parser(compile_dir, lang)
  return run({ "tree-sitter", "build", "-o", "parser.so" }, { cwd = compile_dir }, "build " .. lang)
end

local function install_parser(compile_dir, lang)
  local source = vim.fs.joinpath(compile_dir, "parser.so")
  local target = parser_lib(lang)
  local suffix = "." .. tostring(vim.uv.hrtime())
  local next = target .. suffix .. ".next"
  local backup = target .. suffix .. ".old"

  local err = util.copy_file(source, next)

  if err then
    return err
  end

  local had_parser = vim.uv.fs_stat(target) ~= nil

  if had_parser then
    local ok, rename_err = vim.uv.fs_rename(target, backup)

    if not ok then
      pcall(vim.uv.fs_unlink, next)
      return rename_err
    end
  end

  local ok, rename_err = vim.uv.fs_rename(next, target)

  if not ok then
    if had_parser then
      pcall(vim.uv.fs_rename, backup, target)
    end

    pcall(vim.uv.fs_unlink, next)
    return rename_err
  end

  if had_parser then
    pcall(vim.uv.fs_unlink, backup)
  end
end

local function install_queries(info, lang, project_dir)
  local source

  if info and info.queries and info.path then
    source = vim.fs.joinpath(vim.fs.normalize(info.path), info.queries)
  elseif info and info.queries and project_dir then
    source = vim.fs.joinpath(project_dir, info.queries)
  else
    source = query_source(lang)
  end

  if not source or not vim.uv.fs_stat(source) then
    return nil
  end

  return util.link_or_copy_dir(source, vim.fs.joinpath(config.get_install_dir("queries"), lang))
end

local function needs_update(lang)
  local info = get_install_info(lang)

  if not info then
    return false
  end

  return (info.revision or info.branch or "main") ~= installed_revision(lang)
end

local function fail(action, lang, err)
  notify("Failed to " .. action .. " " .. lang .. ": " .. tostring(err), vim.log.levels.ERROR)

  return false, tostring(err)
end

local function install_lang_inner(lang, opts)
  opts = opts or {}

  if not opts.force and vim.uv.fs_stat(parser_lib(lang)) and not needs_update(lang) then
    local err = install_queries(get_install_info(lang), lang)

    if err then
      return fail("install queries for", lang, err)
    end

    return true, nil, false
  end

  local info = get_install_info(lang)
  local project_dir
  local revision

  if not info then
    local err = install_queries(nil, lang)

    if err then
      return fail("install queries for", lang, err)
    end

    return true, nil, false
  end

  notify("Installing " .. lang)

  if info.path then
    project_dir = vim.fs.normalize(info.path)
    revision = info.revision or info.branch or "local"
  else
    local cache_dir = vim.fs.joinpath(vim.fn.stdpath("cache"), "tiny-treesitter")

    vim.fn.mkdir(cache_dir, "p")

    local err

    project_dir, revision, err = download(info, lang, cache_dir)

    if err then
      return fail("install", lang, err)
    end
  end

  local compile_dir = info.location and vim.fs.joinpath(project_dir, info.location) or project_dir
  local err = generate_parser(info, compile_dir, lang, opts.generate)

  if err then
    return fail("install", lang, err)
  end

  err = compile_parser(compile_dir, lang)

  if err then
    return fail("install", lang, err)
  end

  err = install_parser(compile_dir, lang)

  if err then
    return fail("install", lang, err)
  end

  util.write_file(parser_revision_file(lang), revision or "")

  err = install_queries(info, lang, project_dir)

  if err then
    return fail("install queries for", lang, err)
  end

  if info and not info.path then
    util.rmpath(project_dir)
  end

  notify("Installed " .. lang)
  return true, nil, true
end

local function install_lang(lang, opts)
  if installing[lang] then
    local done = vim.wait(60000, function()
      return not installing[lang]
    end)

    if not done then
      return fail("install", lang, "timed out waiting for active install")
    end

    local result = install_results[lang]

    if result then
      return result[1], result[2], result[3]
    end

    return true, nil, false
  end

  installing[lang] = true

  local ran, ok, err, installed = pcall(install_lang_inner, lang, opts)

  installing[lang] = nil

  if not ran then
    install_results[lang] = { false, tostring(ok), false }
    error(ok)
  end

  install_results[lang] = { ok, err, installed }
  return ok, err, installed
end

local function run_languages(languages, opts, runner)
  local ok_count = 0
  local installed_count = 0
  local failures = {}
  local tasks = {}

  for _, lang in ipairs(languages) do
    tasks[#tasks + 1] = function()
      return runner(lang, opts)
    end
  end

  local results, errors = async.join(concurrency(opts), tasks)

  for index, lang in ipairs(languages) do
    local result = results[index]
    local task_error = errors[index]

    if task_error then
      failures[lang] = task_error
    elseif result and result[1] then
      ok_count = ok_count + 1

      if result[3] then
        installed_count = installed_count + 1
      end
    else
      failures[lang] = (result and result[2]) or "failed"
    end
  end

  if opts.summary and installed_count > 0 and #languages > 1 then
    notify(string.format("Installed %d new parser%s", installed_count, installed_count == 1 and "" or "s"))
  end

  return ok_count == #languages, failures
end

local function start(task, opts)
  opts = opts or {}

  local result, failures = async.run(task, {
    wait = opts.wait,
    timeout = opts.timeout,
    callback = function(err, success, callback_failures)
      if err then
        success = false
        callback_failures = { error = tostring(err) }
        notify(tostring(err), vim.log.levels.ERROR)
      end

      if opts.callback then
        opts.callback(success, callback_failures)
      end
    end,
  })

  if opts.wait and result == false and failures and failures.error then
    notify(failures.error, vim.log.levels.ERROR)
  end

  return result, failures
end

function M.install(languages, opts)
  opts = opts or {}

  return start(function()
    local normalized = config.norm_languages(languages)

    return run_languages(normalized, opts, install_lang)
  end, opts)
end

function M.update(languages, opts)
  opts = opts or {}

  if not languages or (type(languages) == "table" and #languages == 0) then
    languages = "all"
  end

  return start(function()
    local normalized = config.norm_languages(languages, { missing = true })
    local pending = vim.tbl_filter(needs_update, normalized)

    if #pending == 0 then
      if opts.summary then
        notify("All parsers are up to date")
      end

      return true, {}
    end

    return run_languages(pending, vim.tbl_extend("force", opts, { force = true }), install_lang)
  end, opts)
end

function M.uninstall(languages, opts)
  opts = opts or {}

  return start(function()
    local normalized = config.norm_languages(languages or "all", { missing = true, dependencies = true })

    for _, lang in ipairs(normalized) do
      util.rmpath(parser_lib(lang))
      util.rmpath(parser_revision_file(lang))
      util.rmpath(vim.fs.joinpath(config.get_install_dir("queries"), lang))
      notify("Uninstalled " .. lang)
    end

    return true, {}
  end, opts)
end

return M
