local M = {}

local health = vim.health
local required_neovim_version = "0.12"
local required_tree_sitter_cli_version = { major = 0, minor = 26, patch = 1 }

local function version_string(version)
  return string.format("%d.%d.%d", version.major, version.minor, version.patch)
end

local function first_line(text)
  return (text or ""):match("[^\r\n]+") or ""
end

local function run(cmd)
  local ok, handle = pcall(vim.system, cmd, { text = true })

  if not ok then
    return nil, tostring(handle)
  end

  local result = handle:wait()
  local output = vim.trim(table.concat({ result.stdout or "", result.stderr or "" }, "\n"))

  if result.code ~= 0 then
    return nil, output ~= "" and output or table.concat(cmd, " ")
  end

  return output
end

local function command_name(command)
  if not command or command == "" then
    return nil
  end

  return command:match('^"([^"]+)"') or command:match("^(%S+)")
end

local function is_executable(command)
  local name = command_name(command)

  return name and vim.fn.executable(name) == 1
end

local function check_command(command, args, advice)
  if not is_executable(command) then
    health.error("`" .. command .. "` not found", advice)
    return false, nil
  end

  local output, err = run(vim.list_extend({ command_name(command) }, args or {}))

  if output then
    health.ok("`" .. command .. "` found: " .. first_line(output))
  else
    health.warn("`" .. command .. "` found, but version check failed: " .. err)
  end

  return true, output
end

local function parse_version(output)
  local major, minor, patch = (output or ""):match("(%d+)%.(%d+)%.(%d+)")

  if not major then
    return nil
  end

  return tonumber(major), tonumber(minor), tonumber(patch)
end

local function version_at_least(major, minor, patch, required)
  if major ~= required.major then
    return major > required.major
  end

  if minor ~= required.minor then
    return minor > required.minor
  end

  return patch >= required.patch
end

local function count_keys(tbl)
  local count = 0

  for _ in pairs(tbl) do
    count = count + 1
  end

  return count
end

local function count_dirs(path)
  local count = 0

  for _, kind in vim.fs.dir(path) do
    if kind == "directory" then
      count = count + 1
    end
  end

  return count
end

local function bundled_query_root()
  local paths = vim.api.nvim_get_runtime_file("lua/tiny-treesitter/parsers.lua", true)

  for _, path in ipairs(paths) do
    local root = vim.fn.fnamemodify(path, ":p:h:h:h")
    local queries = vim.fs.joinpath(root, "runtime", "queries")
    local stat = vim.uv.fs_stat(queries)

    if stat and stat.type == "directory" then
      return queries
    end
  end
end

local function check_requirements()
  health.start("tiny-treesitter: requirements")

  if vim.fn.has("nvim-" .. required_neovim_version) == 1 then
    health.ok("Neovim version is " .. version_string(vim.version()))
  else
    health.error(
      "Neovim " .. required_neovim_version .. "+ is required; current version is " .. version_string(vim.version())
    )
    return false
  end

  check_command("curl", { "--version" }, { "Install curl and make sure it is available on $PATH." })
  check_command("tar", { "--version" }, { "Install tar and make sure it is available on $PATH." })

  local has_tree_sitter, tree_sitter_version = check_command("tree-sitter", { "--version" }, {
    "Install tree-sitter CLI " .. version_string(required_tree_sitter_cli_version) .. " or newer.",
    "See https://tree-sitter.github.io/tree-sitter/creating-parsers#installation",
  })

  if has_tree_sitter then
    local major, minor, patch = parse_version(tree_sitter_version)

    if not major then
      health.warn("Could not parse `tree-sitter --version` output: " .. first_line(tree_sitter_version), {
        "tiny-treesitter requires tree-sitter CLI " .. version_string(required_tree_sitter_cli_version) .. " or newer.",
      })
    elseif version_at_least(major, minor, patch, required_tree_sitter_cli_version) then
      health.ok(
        string.format(
          "tree-sitter CLI version %d.%d.%d satisfies %s+",
          major,
          minor,
          patch,
          version_string(required_tree_sitter_cli_version)
        )
      )
    else
      health.error(string.format("tree-sitter CLI version %d.%d.%d is too old", major, minor, patch), {
        "Install tree-sitter CLI " .. version_string(required_tree_sitter_cli_version) .. " or newer.",
      })
    end
  end

  local compilers = { "cc", "gcc", "clang", "cl" }

  if vim.env.CC and vim.env.CC ~= "" then
    table.insert(compilers, 1, vim.env.CC)
  end

  for _, compiler in ipairs(compilers) do
    if is_executable(compiler) then
      health.ok("C compiler found: " .. compiler)
      return true
    end
  end

  health.error("No C compiler found", {
    "Install a C compiler available as `cc`, `gcc`, `clang`, or `cl`.",
    "Alternatively set $CC to the compiler used by `tree-sitter build`.",
  })

  return true
end

local function check_bundled_data()
  health.start("tiny-treesitter: bundled data")

  local ok, parsers = pcall(require, "tiny-treesitter.parsers")

  if ok and type(parsers) == "table" then
    health.ok(string.format("Bundled parser registry loaded (%d parsers)", count_keys(parsers)))
  else
    health.error("Failed to load bundled parser registry", tostring(parsers))
    parsers = nil
  end

  local query_root = bundled_query_root()

  if query_root then
    health.ok(string.format("Bundled queries found: %s (%d languages)", query_root, count_dirs(query_root)))
  else
    health.error("Bundled queries were not found", {
      "runtime/queries must be present in the tiny-treesitter.nvim plugin directory.",
    })
  end

  return parsers
end

local function check_install_state(parsers)
  health.start("tiny-treesitter: install state")

  local ok, config = pcall(require, "tiny-treesitter.config")

  if not ok then
    health.error("Failed to load tiny-treesitter.config", tostring(config))
    return
  end

  local dirs = {
    parser = config.get_install_dir("parser"),
    ["parser-info"] = config.get_install_dir("parser-info"),
    queries = config.get_install_dir("queries"),
  }

  for name, path in pairs(dirs) do
    local stat = vim.uv.fs_stat(path)

    if stat and stat.type == "directory" then
      local writable = vim.fn.filewritable(path) == 2

      if writable then
        health.ok(name .. " directory is writable: " .. path)
      else
        health.error(name .. " directory is not writable: " .. path)
      end
    else
      health.error(name .. " directory is missing: " .. path)
    end
  end

  local installed_parsers = config.get_installed("parsers")
  local installed_queries = config.get_installed("queries")

  table.sort(installed_parsers)
  table.sort(installed_queries)

  if #installed_parsers == 0 then
    health.info("No parser libraries are installed yet")
  else
    health.ok(string.format("%d parser libraries installed", #installed_parsers))
  end

  health.info(string.format("%d query sets installed", #installed_queries))

  if not parsers or #installed_parsers == 0 then
    return
  end

  local outdated = {}
  local missing_revision = {}
  local unknown = {}

  for _, lang in ipairs(installed_parsers) do
    local parser = parsers[lang]
    local info = parser and parser.install_info

    if not info then
      unknown[#unknown + 1] = lang
    else
      local expected = info.revision or info.branch or "main"
      local revision_file = vim.fs.joinpath(dirs["parser-info"], lang .. ".revision")
      local revision = vim.fn.filereadable(revision_file) == 1
          and vim.trim(table.concat(vim.fn.readfile(revision_file), "\n"))
        or nil

      if not revision or revision == "" then
        missing_revision[#missing_revision + 1] = lang
      elseif revision ~= expected then
        outdated[#outdated + 1] = lang
      end
    end
  end

  if #unknown > 0 then
    health.warn("Installed parsers not present in bundled registry: " .. table.concat(unknown, ", "))
  end

  if #missing_revision > 0 then
    health.warn("Installed parsers missing revision metadata: " .. table.concat(missing_revision, ", "), {
      "Run :TSUpdate to reinstall them with revision tracking.",
    })
  end

  if #outdated > 0 then
    health.warn("Installed parsers behind bundled registry: " .. table.concat(outdated, ", "), {
      "Run :TSUpdate to rebuild outdated parsers.",
    })
  elseif #unknown == 0 and #missing_revision == 0 then
    health.ok("Installed parser revisions match the bundled registry")
  end
end

function M.check()
  if not health then
    error("tiny-treesitter health checks require vim.health")
  end

  if not check_requirements() then
    return
  end

  local parsers = check_bundled_data()
  check_install_state(parsers)
end

return M
