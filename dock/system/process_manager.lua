local M = {}

function M.new(ctx)
  local manager = { ctx = ctx, next_pid = 1, processes = {} }

  function manager.spawn(name, target, meta)
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
      last_error = nil,
    }
    manager.processes[pid] = process
    local ok, err = pcall(target, ctx, process)
    if ok then
      process.status = "stopped"
    else
      process.status = "crashed"
      process.last_error = tostring(err)
      if ctx and ctx.logger then
        ctx.logger.error("process crashed: " .. process.name .. ": " .. tostring(err), ctx.logger.file("apps.log"))
      end
      if ctx and ctx.event_bus then
        ctx.event_bus.emit("process_crashed", process)
      end
    end
    return { ok = ok, data = process, error = ok and nil or process.last_error, code = ok and nil or "PROCESS_CRASHED" }
  end

  function manager.stop(pid)
    local process = manager.processes[tonumber(pid)]
    if not process then
      return { ok = false, error = "process not found", code = "NOT_FOUND" }
    end
    process.status = "stopped"
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
