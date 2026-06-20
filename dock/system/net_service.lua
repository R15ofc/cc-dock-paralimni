local M = {}
local PROTOCOL = "dockos.v1"

function M.new(ctx)
  local service = { ctx = ctx, modem = nil, hostname = "dockos", protocol = PROTOCOL }

  function service.open()
    if not rednet or not peripheral or not peripheral.getNames then return { ok = false, error = "rednet unavailable", code = "UNAVAILABLE" } end
    for _, name in ipairs(peripheral.getNames()) do
      local kind = peripheral.getType(name)
      if tostring(kind):find("modem") then
        local ok = pcall(rednet.open, name)
        if ok then service.modem = name; return { ok = true, data = name } end
      end
    end
    return { ok = false, error = "modem not found", code = "NOT_FOUND" }
  end

  function service.nodeId() return os.getComputerID and os.getComputerID() or 0 end

  local function envelope(message_type, to, payload)
    return { protocol = PROTOCOL, type = message_type, from = service.nodeId(), to = to, time = os.epoch and os.epoch("utc") or os.clock(), payload = payload or {} }
  end

  function service.send(target, message_type, payload)
    if not service.modem then service.open() end
    if not rednet or not service.modem then return { ok = false, error = "network unavailable", code = "UNAVAILABLE" } end
    rednet.send(target, envelope(message_type, target, payload), PROTOCOL)
    return { ok = true }
  end

  function service.broadcast(message_type, payload)
    if not service.modem then service.open() end
    if not rednet or not service.modem then return { ok = false, error = "network unavailable", code = "UNAVAILABLE" } end
    rednet.broadcast(envelope(message_type, nil, payload), PROTOCOL)
    return { ok = true }
  end

  function service.ping(target)
    if target then return service.send(target, "ping", {}) end
    return service.broadcast("ping", {})
  end

  function service.handleMessage(sender, message, protocol)
    if protocol ~= PROTOCOL or type(message) ~= "table" then return false end
    if message.type == "ping" then service.send(sender, "pong", {}) end
    if ctx.event_bus then ctx.event_bus.emit("network_message", { sender = sender, message = message }) end
    return true
  end

  function service.start()
    service.open()
    return { ok = true }
  end

  return service
end

return M
