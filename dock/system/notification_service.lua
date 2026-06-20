local M = {}

function M.new(ctx)
  local service = { ctx = ctx, notifications = {}, next_id = 1 }
  function service.add(title, body)
    local item = { id = service.next_id, title = title, body = body, time = os.clock() }
    service.next_id = service.next_id + 1
    table.insert(service.notifications, item)
    return { ok = true, data = item }
  end
  function service.list() return { ok = true, data = service.notifications } end
  function service.clear() service.notifications = {}; return { ok = true } end
  return service
end

return M
