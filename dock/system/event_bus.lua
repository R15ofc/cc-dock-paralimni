local M = {}

function M.new(logger)
  local bus = { handlers = {}, logger = logger }

  function bus.subscribe(event_name, handler)
    if type(handler) ~= "function" then
      return { ok = false, error = "handler must be function", code = "INVALID_HANDLER" }
    end
    bus.handlers[event_name] = bus.handlers[event_name] or {}
    table.insert(bus.handlers[event_name], handler)
    return { ok = true, data = handler }
  end

  function bus.unsubscribe(event_name, handler)
    local list = bus.handlers[event_name] or {}
    local next_list = {}
    for _, candidate in ipairs(list) do
      if candidate ~= handler then
        table.insert(next_list, candidate)
      end
    end
    bus.handlers[event_name] = next_list
    return { ok = true }
  end

  function bus.emit(event_name, payload)
    local list = bus.handlers[event_name] or {}
    for _, handler in ipairs(list) do
      local ok, err = pcall(handler, payload, event_name)
      if not ok and bus.logger then
        bus.logger.error("event handler failed for " .. tostring(event_name) .. ": " .. tostring(err))
      end
    end
    return { ok = true }
  end

  return bus
end

return M
