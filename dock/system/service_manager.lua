local M = {}

function M.new(ctx)
  local manager = { ctx = ctx, services = {} }

  function manager.register(id, service, options)
    if not id or type(service) ~= "table" then
      return { ok = false, error = "invalid service", code = "INVALID_SERVICE" }
    end
    manager.services[id] = {
      id = id,
      service = service,
      autostart = options and options.autostart or false,
      status = "stopped",
      last_error = nil,
    }
    return { ok = true, data = manager.services[id] }
  end

  function manager.start(id)
    local item = manager.services[id]
    if not item then
      return { ok = false, error = "service not found", code = "NOT_FOUND" }
    end
    if item.service.start then
      local ok, err = pcall(item.service.start, ctx)
      if not ok then
        item.status = "crashed"
        item.last_error = tostring(err)
        if ctx.logger then ctx.logger.error("service failed: " .. id .. ": " .. tostring(err), ctx.logger.file("services.log")) end
        return { ok = false, error = item.last_error, code = "SERVICE_FAILED" }
      end
    end
    item.status = "running"
    if ctx.event_bus then ctx.event_bus.emit("service_started", { id = id }) end
    return { ok = true, data = item }
  end

  function manager.stop(id)
    local item = manager.services[id]
    if not item then
      return { ok = false, error = "service not found", code = "NOT_FOUND" }
    end
    if item.service.stop then
      pcall(item.service.stop, ctx)
    end
    item.status = "stopped"
    if ctx.event_bus then ctx.event_bus.emit("service_stopped", { id = id }) end
    return { ok = true, data = item }
  end

  function manager.restart(id)
    manager.stop(id)
    return manager.start(id)
  end

  function manager.list()
    local list = {}
    for _, item in pairs(manager.services) do
      table.insert(list, { id = item.id, status = item.status, autostart = item.autostart, last_error = item.last_error })
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return { ok = true, data = list }
  end

  function manager.health(id)
    local item = manager.services[id]
    if not item then return { ok = false, error = "service not found", code = "NOT_FOUND" } end
    if item.service.health then
      local ok, data = pcall(item.service.health, ctx)
      if ok then return { ok = true, data = data } end
    end
    return { ok = true, data = { status = item.status } }
  end

  function manager.startAutostart()
    for id, item in pairs(manager.services) do
      if item.autostart then
        manager.start(id)
      end
    end
    return { ok = true }
  end

  return manager
end

return M
