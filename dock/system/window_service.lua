local paths = require("dock.system.paths")
local safe_io = require("dock.system.safe_io")

local M = {}

local function ok(data) return { ok = true, data = data } end
local function err(message, code) return { ok = false, error = tostring(message), code = code or "WINDOW_ERROR" } end

local function clamp_window(window, screen_width, screen_height)
  local sw = math.max(80, tonumber(screen_width) or 384)
  local sh = math.max(72, tonumber(screen_height) or 192)
  local max_w = math.max(64, sw - 2)
  local max_h = math.max(44, sh - 36)
  window.w = math.min(math.max(64, tonumber(window.w) or 220), max_w)
  window.h = math.min(math.max(44, tonumber(window.h) or 120), max_h)
  window.x = math.max(1, math.min(tonumber(window.x) or 1, sw - window.w + 1))
  window.y = math.max(12, math.min(tonumber(window.y) or 12, sh - window.h - 26))
  return window
end

function M.new(ctx)
  local service = {
    ctx = ctx,
    path = paths.join(paths.db, "windows.json"),
    windows = {},
    active = nil,
    next_z = 1,
  }

  local function serialize()
    local windows = {}
    for _, window in ipairs(service.windows) do
      table.insert(windows, {
        id = window.id,
        app_id = window.app_id,
        x = window.x,
        y = window.y,
        w = window.w,
        h = window.h,
        minimized = window.minimized,
        fullscreen = window.fullscreen,
        z = window.z,
      })
    end
    return { active = service.active, next_z = service.next_z, windows = windows }
  end

  local function decorate(item)
    local app = ctx.app_service and ctx.app_service.getApp(item.app_id)
    if not app or not app.ok then return nil end
    return {
      id = item.id,
      app_id = item.app_id,
      app = app.data,
      x = tonumber(item.x) or 42,
      y = tonumber(item.y) or 24,
      w = tonumber(item.w) or 220,
      h = tonumber(item.h) or 120,
      minimized = item.minimized == true,
      fullscreen = item.fullscreen == true,
      z = tonumber(item.z) or service.next_z,
    }
  end

  function service.save()
    return safe_io.writeJson(service.path, serialize())
  end

  function service.restore(screen_width, screen_height)
    local read = safe_io.readJson(service.path, { windows = {} })
    service.windows = {}
    service.active = read.data and read.data.active or nil
    service.next_z = read.data and tonumber(read.data.next_z) or 1
    for _, item in ipairs((read.data and read.data.windows) or {}) do
      local window = decorate(item)
      if window then
        clamp_window(window, screen_width, screen_height)
        table.insert(service.windows, window)
      end
    end
    table.sort(service.windows, function(a, b) return a.z < b.z end)
    return ok(service.windows)
  end

  function service.list()
    return ok(service.windows)
  end

  function service.activeId()
    return ok(service.active)
  end

  function service.get(id)
    for _, window in ipairs(service.windows) do
      if window.id == id then return ok(window) end
    end
    return err("window not found", "NOT_FOUND")
  end

  function service.focus(id)
    local focused
    local next_windows = {}
    for _, window in ipairs(service.windows) do
      if window.id == id then focused = window else table.insert(next_windows, window) end
    end
    if not focused then return err("window not found", "NOT_FOUND") end
    service.next_z = service.next_z + 1
    focused.z = service.next_z
    table.insert(next_windows, focused)
    service.windows = next_windows
    service.active = id
    service.save()
    if ctx.event_bus then ctx.event_bus.emit("window_focused", { id = id, app_id = focused.app_id }) end
    return ok(focused)
  end

  function service.open(app_id, geometry)
    if not ctx.app_service then return err("app service unavailable", "APP_SERVICE_UNAVAILABLE") end
    local app = ctx.app_service.getApp(app_id)
    if not app.ok then return app end
    for _, window in ipairs(service.windows) do
      if window.app_id == app_id then
        window.minimized = false
        return service.focus(window.id)
      end
    end
    service.next_z = service.next_z + 1
    local id = tostring(os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)) .. "-" .. tostring(service.next_z)
    local window = {
      id = id,
      app_id = app_id,
      app = app.data,
      x = geometry and geometry.x or 42,
      y = geometry and geometry.y or 24,
      w = geometry and geometry.w or 220,
      h = geometry and geometry.h or 120,
      minimized = false,
      fullscreen = false,
      z = service.next_z,
    }
    clamp_window(window, geometry and geometry.screen_width, geometry and geometry.screen_height)
    table.insert(service.windows, window)
    service.active = id
    service.save()
    if ctx.event_bus then ctx.event_bus.emit("window_opened", { id = id, app_id = app_id }) end
    return ok(window)
  end

  function service.close(id)
    local removed
    local next_windows = {}
    for _, window in ipairs(service.windows) do
      if window.id == id then removed = window else table.insert(next_windows, window) end
    end
    if not removed then return err("window not found", "NOT_FOUND") end
    service.windows = next_windows
    service.active = next_windows[#next_windows] and next_windows[#next_windows].id or nil
    service.save()
    if ctx.event_bus then ctx.event_bus.emit("window_closed", { id = id, app_id = removed.app_id }) end
    return ok(removed)
  end

  function service.minimize(id, value)
    local window = service.get(id)
    if not window.ok then return window end
    window.data.minimized = value ~= false
    if window.data.minimized and service.active == id then service.active = nil end
    service.save()
    return ok(window.data)
  end

  function service.toggleFullscreen(id)
    local window = service.get(id)
    if not window.ok then return window end
    window.data.fullscreen = not window.data.fullscreen
    service.focus(id)
    service.save()
    return ok(window.data)
  end

  function service.move(id, x, y, screen_width, screen_height)
    local window = service.get(id)
    if not window.ok then return window end
    if window.data.fullscreen then return ok(window.data) end
    window.data.x = math.floor(tonumber(x) or window.data.x)
    window.data.y = math.floor(tonumber(y) or window.data.y)
    clamp_window(window.data, screen_width, screen_height)
    service.save()
    return ok(window.data)
  end

  function service.start()
    return ok(true)
  end

  return service
end

return M
