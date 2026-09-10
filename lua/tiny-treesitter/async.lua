local modern = vim.async
local core
if not modern then
  core = require("vim._async")
end

local await = modern and modern.await or core.await

local M = {}

local function scheduled(callback)
  return vim.schedule_wrap(callback)
end

local function spawn(cmd, opts, done)
  opts = vim.tbl_extend("force", { text = true }, opts or {})

  local complete = scheduled(done)
  local ok, result = pcall(vim.system, cmd, opts, complete)

  if ok then
    return result
  end

  complete({
    code = 125,
    signal = 0,
    stdout = "",
    stderr = tostring(result),
  })
end

function M.schedule()
  return await(1, vim.schedule)
end

function M.system(cmd, opts)
  return await(3, spawn, cmd, opts)
end

function M.join(limit, tasks)
  local results = {}
  local errors = {}
  local wrapped = {}

  for index, task in ipairs(tasks) do
    wrapped[index] = function()
      local result = { pcall(task) }
      local ok = table.remove(result, 1)

      if ok then
        results[index] = result
      else
        errors[index] = tostring(result[1])
      end
    end
  end

  if #wrapped > 0 then
    if modern then
      local semaphore = modern.semaphore(limit)
      local handles = {}

      for index, task in ipairs(wrapped) do
        handles[index] = modern.run(function()
          semaphore:with(task)
        end)
      end

      for _, handle in ipairs(handles) do
        modern.await(handle)
      end
    else
      core.join(limit, wrapped)
    end
  end

  return results, errors
end

function M.run(task, opts)
  opts = opts or {}

  if opts.wait and vim.in_fast_event() then
    return false, { error = "tiny-treesitter: wait=true cannot be used from a fast event" }
  end

  local function execute()
    M.schedule()

    return task()
  end

  local handle
  if modern then
    handle = modern.run(execute)
    if opts.callback then
      handle:on_complete(opts.callback)
    end
  else
    handle = core.run(execute, opts.callback)
  end

  if not opts.wait then
    return handle
  end

  local ok, result, extra = pcall(function()
    return handle:wait(opts.timeout or 120000)
  end)

  if ok then
    return result, extra
  end

  return false, { error = tostring(result) }
end

return M
