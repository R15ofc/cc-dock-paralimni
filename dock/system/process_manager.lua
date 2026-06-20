local M = {}

function M.new(ctx)
  local manager = { ctx = ctx, next_pid = 1, processes = {} }

  local function create_process(name, target, meta)
    if type(target) ~= "function" then
      return { ok = false, error = "target must be function", code = "INVALID_PROCESS" }
    end
    local pid = manager.next_pid
    manager.next_pid = manager.next_pid + 1
    local process = {
      pid = pid,
      name = name or ("process-" .. tostring(pid)),
      app_id = meta and meta.app_id,
      service_id = meta and meta.service_id,
      status = "running",
      started_at = os.clock(),
      updated_at = os.clock(),
      last_error = nil,
      inbox = {},
      wait_filter = nil,
    }
    manager.processes[pid] = process
    return process
  end

  local function mark_crashed(process, err)
    process.status = "crashed"
    process.last_error = tostring(err)
    process.updated_at = os.clock()
    if ctx and ctx.logger then
      ctx.logger.error("process crashed: " .. process.name .. ": " .. tostring(err), ctx.logger.file("apps.log"))
    end
    if ctx and ctx.event_bus then
      ctx.event_bus.emit("process_crashed", process)
    end
  end

  function manager.spawn(name, target, meta)
    local process_or_error = create_process(name, target, meta)
    if process_or_error.ok == false then return process_or_error end
    local process = process_or_error
    local ok, err = pcall(target, ctx, process)
    if ok then
      process.status = "stopped"
      process.updated_at = os.clock()
    else
      mark_crashed(process, err)
    end
    return { ok = ok, data = process, error = ok and nil or process.last_error, code = ok and nil or "PROCESS_CRASHED" }
  end

  function manager.spawnAsync(name, target, meta)
    local process_or_error = create_process(name, target, meta)
    if process_or_error.ok == false then return process_or_error end
    local process = process_or_error
    process.status = "ready"
    process.coroutine = coroutine.create(function(...)
      return target(ctx, process, ...)
    end)
    if ctx and ctx.event_bus then ctx.event_bus.emit("process_spawned", process) end
    return { ok = true, data = process }
  end

  local function resume_process(process, event_name, ...)
    if not process or not process.coroutine or process.status == "stopped" or process.status == "crashed" then
      return { ok = false, error = "process not runnable", code = "NOT_RUNNABLE" }
    end
    if coroutine.status(process.coroutine) == "dead" then
      process.status = "stopped"
      process.updated_at = os.clock()
      return { ok = true, data = process }
    end
    process.status = "running"
    process.updated_at = os.clock()
    local ok, wait_filter_or_error = coroutine.resume(process.coroutine, event_name, ...)
    if not ok then
      mark_crashed(process, wait_filter_or_error)
      return { ok = false, error = process.last_error, code = "PROCESS_CRASHED" }
    end
    if coroutine.status(process.coroutine) == "dead" then
      process.status = "stopped"
      process.wait_filter = nil
    else
      process.status = "waiting"
      process.wait_filter = wait_filter_or_error
    end
    process.updated_at = os.clock()
    return { ok = true, data = process }
  end

  function manager.step()
    local results = {}
    for _, process in pairs(manager.processes) do
      if process.status == "ready" then table.insert(results, resume_process(process)) end
    end
    return { ok = true, data = results }
  end

  function manager.dispatch(event_name, ...)
    local results = {}
    for _, process in pairs(manager.processes) do
      if process.coroutine and (process.status == "ready" or process.status == "waiting") then
        if process.wait_filter == nil or process.wait_filter == event_name or process.wait_filter == "*" then
          table.insert(results, resume_process(process, event_name, ...))
        end
      end
    end
    return { ok = true, data = results }
  end

  function manager.send(pid, message)
    local process = manager.processes[tonumber(pid)]
    if not process then return { ok = false, error = "process not found", code = "NOT_FOUND" } end
    table.insert(process.inbox, message)
    process.updated_at = os.clock()
    return { ok = true, data = process }
  end

  function manager.receive(pid)
    local process = manager.processes[tonumber(pid)]
    if not process then return { ok = false, error = "process not found", code = "NOT_FOUND" } end
    return { ok = true, data = table.remove(process.inbox, 1) }
  end

  function manager.stop(pid)
    local process = manager.processes[tonumber(pid)]
    if not process then
      return { ok = false, error = "process not found", code = "NOT_FOUND" }
    end
    process.status = "stopped"
    process.updated_at = os.clock()
    return { ok = true, data = process }
  end

  function manager.get(pid)
    return { ok = true, data = manager.processes[tonumber(pid)] }
  end

  function manager.list()
    local list = {}
    for _, process in pairs(manager.processes) do
      table.insert(list, process)
    end
    table.sort(list, function(a, b) return a.pid < b.pid end)
    return { ok = true, data = list }
  end

  return manager
end

return M
