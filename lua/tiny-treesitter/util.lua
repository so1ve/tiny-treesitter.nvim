local M = {}

function M.read_file(path)
  local file = io.open(path, "r")

  if not file then
    return nil
  end

  local content = file:read("*a")

  file:close()

  return content
end

function M.write_file(path, content)
  vim.fn.mkdir(vim.fs.dirname(path), "p")

  local file = assert(io.open(path, "w"))

  file:write(content)
  file:close()
end

function M.rmpath(path)
  local stat = vim.uv.fs_lstat(path)

  if not stat then
    return nil
  end

  if stat.type == "directory" then
    for name in vim.fs.dir(path) do
      local err = M.rmpath(vim.fs.joinpath(path, name))

      if err then
        return err
      end
    end

    local ok, err = vim.uv.fs_rmdir(path)

    return ok and nil or err
  end

  local ok, err = vim.uv.fs_unlink(path)

  return ok and nil or err
end

function M.copy_file(src, dest)
  vim.fn.mkdir(vim.fs.dirname(dest), "p")

  local ok, err = vim.uv.fs_copyfile(src, dest)

  return ok and nil or err
end

function M.copy_dir(src, dest)
  M.rmpath(dest)
  vim.fn.mkdir(dest, "p")

  for name in vim.fs.dir(src) do
    local from = vim.fs.joinpath(src, name)
    local to = vim.fs.joinpath(dest, name)
    local stat = vim.uv.fs_lstat(from)

    if stat and stat.type == "directory" then
      local err = M.copy_dir(from, to)

      if err then
        return err
      end
    elseif stat then
      local err = M.copy_file(from, to)

      if err then
        return err
      end
    end
  end
end

function M.link_or_copy_dir(src, dest)
  M.rmpath(dest)
  vim.fn.mkdir(vim.fs.dirname(dest), "p")

  local ok = vim.uv.fs_symlink(src, dest, { dir = true, junction = true })

  if ok then
    return nil
  end

  return M.copy_dir(src, dest)
end

return M
