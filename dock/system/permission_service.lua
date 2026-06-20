local paths = require("dock.system.paths")
local safe_io = require("dock.system.safe_io")

local M = {}

local function ok(data) return { ok = true, data = data } end
local function err(message, code) return { ok = false, error = tostring(message), code = code or "PERMISSION_ERROR" } end

local DEFAULT_PERMISSIONS = {
  "fs.read",
  "fs.write",
  "fs.delete",
  "network.rednet",
  "peripheral.access",
  "settings.read",
  "settings.write",
  "process.spawn",
  "ipc.message",
  "notification.send",
  "storage.app",
  "window.manage",
}

local function table_set(list)
  local out = {}
  for _, item in ipairs(list or {}) do out[tostring(item)] = true end
  return out
end

local function sorted_keys(map)
  local out = {}
  for key in pairs(map or {}) do table.insert(out, key) end
  table.sort(out)
  return out
end

function M.new(ctx)
  local service = {
    ctx = ctx,
    policy_path = paths.join(paths.etc, "permissions.json"),
    grant_path = paths.join(paths.db, "app_permissions.json"),
    allowed = table_set(DEFAULT_PERMISSIONS),
    grants = {},
  }

  function service.load()
    local policy = safe_io.readJson(service.policy_path, { permissions = DEFAULT_PERMISSIONS })
    service.allowed = table_set(DEFAULT_PERMISSIONS)
    for _, permission in ipairs(policy.data and policy.data.permissions or {}) do
      service.allowed[tostring(permission)] = true
    end
    safe_io.writeJson(service.policy_path, { permissions = sorted_keys(service.allowed) })
    local grant_data = safe_io.readJson(service.grant_path, {})
    service.grants = grant_data.data or {}
    return ok({ allowed = sorted_keys(service.allowed), grants = service.grants })
  end

  function service.save()
    return safe_io.writeJson(service.grant_path, service.grants)
  end

  function service.isKnown(permission)
    return service.allowed[tostring(permission)] == true
  end

  function service.validateManifest(manifest)
    if type(manifest) ~= "table" then return err("manifest must be table", "INVALID_MANIFEST") end
    for _, permission in ipairs(manifest.permissions or {}) do
      if not service.isKnown(permission) then
        return err("unknown permission: " .. tostring(permission), "UNKNOWN_PERMISSION")
      end
    end
    return ok(manifest)
  end

  function service.registerApp(manifest)
    local valid = service.validateManifest(manifest)
    if not valid.ok then return valid end
    local app_id = manifest.id
    service.grants[app_id] = service.grants[app_id] or { granted = {}, denied = {}, requested = {} }
    local record = service.grants[app_id]
    record.requested = manifest.permissions or {}
    if manifest.type == "system" then
      record.granted = manifest.permissions or {}
      record.trusted = true
    else
      record.granted = record.granted or {}
      record.trusted = record.trusted == true
    end
    service.save()
    return ok(record)
  end

  function service.list(app_id)
    if app_id then return ok(service.grants[app_id] or { granted = {}, denied = {}, requested = {} }) end
    return ok(service.grants)
  end

  function service.check(app_id, permission)
    permission = tostring(permission or "")
    local record = service.grants[tostring(app_id)] or {}
    local granted = table_set(record.granted or {})
    local denied = table_set(record.denied or {})
    if denied[permission] then return ok(false) end
    return ok(granted[permission] == true)
  end

  function service.require(app_id, permission)
    local allowed = service.check(app_id, permission)
    if allowed.ok and allowed.data then return ok(true) end
    return err("permission denied: " .. tostring(permission), "PERMISSION_DENIED")
  end

  function service.grant(app_id, permission)
    app_id = tostring(app_id or "")
    permission = tostring(permission or "")
    if app_id == "" then return err("missing app id", "MISSING_APP_ID") end
    if not service.isKnown(permission) then return err("unknown permission: " .. permission, "UNKNOWN_PERMISSION") end
    local record = service.grants[app_id] or { granted = {}, denied = {}, requested = {} }
    local granted = table_set(record.granted)
    local denied = table_set(record.denied)
    granted[permission] = true
    denied[permission] = nil
    record.granted = sorted_keys(granted)
    record.denied = sorted_keys(denied)
    service.grants[app_id] = record
    service.save()
    if ctx.event_bus then ctx.event_bus.emit("permission_granted", { app_id = app_id, permission = permission }) end
    return ok(record)
  end

  function service.revoke(app_id, permission)
    app_id = tostring(app_id or "")
    permission = tostring(permission or "")
    local record = service.grants[app_id] or { granted = {}, denied = {}, requested = {} }
    local granted = table_set(record.granted)
    local denied = table_set(record.denied)
    granted[permission] = nil
    denied[permission] = true
    record.granted = sorted_keys(granted)
    record.denied = sorted_keys(denied)
    service.grants[app_id] = record
    service.save()
    if ctx.event_bus then ctx.event_bus.emit("permission_revoked", { app_id = app_id, permission = permission }) end
    return ok(record)
  end

  function service.start()
    return service.load()
  end

  service.load()
  return service
end

return M
