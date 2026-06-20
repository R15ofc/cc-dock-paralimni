local paths = require("dock.system.paths")
local safe_io = require("dock.system.safe_io")

local M = {}

function M.new(ctx)
  local service = {
    ctx = ctx,
    path = paths.join(paths.etc, "users.json"),
    data = {},
    current = { id = "default", name = "Default User", home = paths.userHome("default") },
  }

  local function password_hash(value, salt)
    value = tostring(salt or "") .. ":" .. tostring(value or "")
    local hash = 5381
    for index = 1, #value do hash = (hash * 33 + value:byte(index)) % 2147483647 end
    return tostring(hash)
  end

  local function normalize()
    if type(service.data) ~= "table" then service.data = {} end
    service.data.current = service.data.current or "default"
    if type(service.data.users) ~= "table" then service.data.users = {} end
    if #service.data.users == 0 then
      table.insert(service.data.users, { id = "default", name = "Default User", home = paths.userHome("default") })
    end
    local selected
    for _, user in ipairs(service.data.users) do
      user.id = tostring(user.id or "default")
      user.name = tostring(user.name or "Default User")
      user.home = user.home or paths.userHome(user.id)
      if user.id == service.data.current then selected = user end
    end
    service.current = selected or service.data.users[1]
    service.data.current = service.current.id
    return service.current
  end

  function service.load()
    service.data = safe_io.readJson(service.path, {}).data or {}
    normalize()
    return { ok = true, data = service.data }
  end

  function service.save()
    normalize()
    return safe_io.writeJson(service.path, service.data)
  end

  function service.ensureUserFolders()
    normalize()
    for _, path in ipairs(paths.required_dirs) do
      local ok = safe_io.ensureDir(path)
      if not ok.ok then return ok end
    end
    return { ok = true }
  end

  function service.getCurrentUser()
    normalize()
    return service.current
  end

  function service.profile()
    normalize()
    return { ok = true, data = { id = service.current.id, name = service.current.name, home = service.current.home, has_password = service.current.password_hash ~= nil } }
  end

  function service.hasPassword()
    normalize()
    return { ok = true, data = service.current.password_hash ~= nil and service.current.password_hash ~= "" }
  end

  function service.loginRequired()
    normalize()
    local has_password = service.hasPassword().data == true
    local required = has_password and ctx.settings_service and ctx.settings_service.get("user.security.login_required", true).data
    return { ok = true, data = required == true }
  end

  function service.setLoginRequired(value)
    if value and not service.hasPassword().data then return { ok = false, error = "Set a password first", code = "PASSWORD_REQUIRED" } end
    if ctx.settings_service then return ctx.settings_service.set("user.security.login_required", value == true) end
    return { ok = true }
  end

  function service.setPassword(password)
    normalize()
    password = tostring(password or "")
    if password == "" then
      service.current.password_hash = nil
      service.current.password_salt = nil
      if ctx.settings_service then ctx.settings_service.set("user.security.login_required", false) end
      return service.save()
    end
    service.current.password_salt = service.current.password_salt or (service.current.id .. ":dockos")
    service.current.password_hash = password_hash(password, service.current.password_salt)
    service.save()
    if ctx.settings_service then ctx.settings_service.set("user.security.login_required", true) end
    return { ok = true }
  end

  function service.verifyPassword(password)
    normalize()
    if not service.hasPassword().data then return { ok = true, data = { authenticated = true } } end
    local expected = password_hash(password, service.current.password_salt or (service.current.id .. ":dockos"))
    return { ok = true, data = { authenticated = expected == service.current.password_hash } }
  end

  function service.getHome()
    normalize()
    return service.current.home
  end

  function service.getUserPath(category)
    local folder = paths.user_folders[category] or category
    return paths.userFolder(service.current.id, folder)
  end

  function service.getUserConfig()
    return safe_io.readJson(paths.join(paths.userConfig(service.current.id), "user.json"), {})
  end

  function service.setUserConfig(value)
    return safe_io.writeJson(paths.join(paths.userConfig(service.current.id), "user.json"), value or {})
  end

  service.load()
  service.ensureUserFolders()
  return service
end

return M
