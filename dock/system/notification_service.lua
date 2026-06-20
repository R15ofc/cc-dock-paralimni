local M = {}

function M.new(ctx)
  local service = { ctx = ctx, notifications = {}, next_id = 1 }
  function service.add(title, body, app_id)
    local item = { id = service.next_id, title = title, body = body, app_id = app_id, time = os.clock() }
    service.next_id = service.next_id + 1
    table.insert(service.notifications, item)
    return { ok = true, data = item }
  end
  function service.list() return { ok = true, data = service.notifications } end
  function service.recentForApp(app_id, seconds)
    local now = os.clock()
    seconds = tonumber(seconds) or 2
    for index = #service.notifications, 1, -1 do
      local item = service.notifications[index]
      if item.app_id == app_id and now - (item.time or now) <= seconds then return { ok = true, data = item } end
    end
    return { ok = true, data = nil }
  end
  function service.clear() service.notifications = {}; return { ok = true } end
  return service
end

return M
