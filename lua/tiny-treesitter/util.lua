local M = {}

function M.mkdirp(path)
  local ok, result = pcall(vim.fn.mkdir, path, "p")

  if ok and result == 1 then
    return nil
  end

  local stat = vim.uv.fs_stat(path)

  if stat and stat.type == "directory" then
    return nil
  end

  return ok and tostring(result) or tostring(result)
end

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
  local err = M.mkdirp(vim.fs.dirname(path))

  if err then
    error(err)
  end

  local file = assert(io.open(path, "w"))

  file:write(content)
  file:close()
end

function M.rmpath(path)
  local stat = vim.uv.fs_lstat(path)

  if not stat then
    return nil
  end

  if stat.type == "link" or vim.uv.fs_readlink(path) then
    local ok, err = vim.uv.fs_unlink(path)

    if ok then
      return nil
    end

    ok, err = vim.uv.fs_rmdir(path)

    return ok and nil or err
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
  local err = M.mkdirp(vim.fs.dirname(dest))

  if err then
    return err
  end

  local ok, err = vim.uv.fs_copyfile(src, dest)

  return ok and nil or err
end

function M.copy_dir(src, dest)
  local err = M.rmpath(dest)

  if err then
    return err
  end

  err = M.mkdirp(dest)

  if err then
    return err
  end

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
  src = vim.fs.normalize(src)
  dest = vim.fs.normalize(dest)

  if src == dest then
    return nil
  end

  local parent = vim.fs.dirname(dest)
  local err = M.mkdirp(parent)

  if err then
    return err
  end

  local tmp = string.format("%s.tmp.%s.%s", dest, tostring(vim.uv.os_getpid()), tostring(vim.uv.hrtime()))

  M.rmpath(tmp)

  local ok = vim.uv.fs_symlink(src, tmp, { dir = true, junction = true })

  if not ok then
    err = M.copy_dir(src, tmp)

    if err then
      M.rmpath(tmp)
      return err
    end
  end

  local backup
  if vim.uv.fs_lstat(dest) then
    backup = string.format("%s.old.%s.%s", dest, tostring(vim.uv.os_getpid()), tostring(vim.uv.hrtime()))
    local renamed_old, rename_old_err = vim.uv.fs_rename(dest, backup)

    if not renamed_old then
      M.rmpath(tmp)
      return rename_old_err
    end
  end

  ok, err = vim.uv.fs_rename(tmp, dest)

  if ok then
    if backup then
      M.rmpath(backup)
    end

    return nil
  end

  if backup then
    vim.uv.fs_rename(backup, dest)
  end

  M.rmpath(tmp)
  return err
end

return M
