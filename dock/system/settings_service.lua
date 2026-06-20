local paths = require("dock.system.paths")
local safe_io = require("dock.system.safe_io")

local M = {}

function M.new(ctx)
  local service = {
    ctx = ctx,
    system_path = paths.join(paths.etc, "system.json"),
    user_path = paths.join(paths.userConfig("default"), "user.json"),
    system = {},
    user = {},
  }

  function service.load()
    service.system = safe_io.readJson(service.system_path, {}).data or {}
    service.user = safe_io.readJson(service.user_path, {}).data or {}
    return { ok = true }
  end

  function service.save()
    local a = safe_io.writeJson(service.system_path, service.system)
    local b = safe_io.writeJson(service.user_path, service.user)
    if not a.ok then return a end
    return b
  end

  local function split(key)
    local scope, name = tostring(key or ""):match("^([%w_%-]+)%.(.+)$")
    if scope == "system" or scope == "user" then return scope, name end
    return "user", key
  end

  function service.get(key, default)
    local scope, name = split(key)
    local source = scope == "system" and service.system or service.user
    local value = source[name]
    if value == nil then value = default end
    return { ok = true, data = value }
  end

  function service.set(key, value)
    local scope, name = split(key)
    local source = scope == "system" and service.system or service.user
    source[name] = value
    if ctx.event_bus then ctx.event_bus.emit("setting_changed", { key = key, value = value }) end
    return service.save()
  end

  function service.getAppSettings(app_id)
    local path = paths.appConfig("default", app_id)
    return safe_io.readJson(path, {})
  end

  function service.setAppSettings(app_id, value)
    return safe_io.writeJson(paths.appConfig("default", app_id), value or {})
  end

  service.load()
  return service
end

return M
