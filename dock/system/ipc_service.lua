local M = {}

local function ok(data) return { ok = true, data = data } end
local function err(message, code) return { ok = false, error = tostring(message), code = code or "IPC_ERROR" } end

function M.new(ctx)
  local service = { ctx = ctx, channels = {}, inbox = {}, next_message_id = 1 }

  local function message(kind, source, target, payload)
    local item = {
      id = service.next_message_id,
      kind = kind,
      source = source,
      target = target,
      payload = payload or {},
      time = os.clock(),
    }
    service.next_message_id = service.next_message_id + 1
    return item
  end

  local function push(pid, item)
    pid = tonumber(pid)
    if not pid then return err("invalid pid", "INVALID_PID") end
    service.inbox[pid] = service.inbox[pid] or {}
    table.insert(service.inbox[pid], item)
    if ctx.process_manager and ctx.process_manager.send then ctx.process_manager.send(pid, item) end
    if ctx.event_bus then ctx.event_bus.emit("ipc_message", item) end
    return ok(item)
  end

  function service.subscribe(pid, channel)
    pid = tonumber(pid)
    channel = tostring(channel or "")
    if not pid or channel == "" then return err("invalid subscription", "INVALID_SUBSCRIPTION") end
    service.channels[channel] = service.channels[channel] or {}
    service.channels[channel][pid] = true
    return ok({ pid = pid, channel = channel })
  end

  function service.unsubscribe(pid, channel)
    pid = tonumber(pid)
    channel = tostring(channel or "")
    if service.channels[channel] then service.channels[channel][pid] = nil end
    return ok(true)
  end

  function service.send(source, target, kind, payload)
    return push(target, message(kind or "message", source, target, payload))
  end

  function service.publish(source, channel, kind, payload)
    channel = tostring(channel or "")
    if channel == "" then return err("missing channel", "MISSING_CHANNEL") end
    local subscribers = service.channels[channel] or {}
    local sent = {}
    for pid in pairs(subscribers) do
      local item = message(kind or "broadcast", source, pid, payload)
      item.channel = channel
      local pushed = push(pid, item)
      if pushed.ok then table.insert(sent, pid) end
    end
    return ok(sent)
  end

  function service.receive(pid)
    pid = tonumber(pid)
    local box = service.inbox[pid] or {}
    local item = table.remove(box, 1)
    return ok(item)
  end

  function service.peek(pid)
    pid = tonumber(pid)
    return ok(service.inbox[pid] or {})
  end

  function service.clear(pid)
    service.inbox[tonumber(pid)] = {}
    return ok(true)
  end

  function service.start()
    return ok(true)
  end

  return service
end

return M
