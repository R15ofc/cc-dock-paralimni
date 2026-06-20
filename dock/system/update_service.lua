local version = require("dock.system.version")
local splash = require("dock.system.splash")

local M = {}

local DEFAULT_SOURCE_URL = "https://raw.githubusercontent.com/R15ofc/cc-dock-paralimni/main"

local function ok(data) return { ok = true, data = data } end
local function err(message, code) return { ok = false, error = tostring(message), code = code or "UPDATE_ERROR" } end

local function parse_field(source, field)
  return tostring(source or ""):match(field .. '%s*=%s*"([^"]+)"')
end

local function compare_versions(left, right)
  local function parts(value)
    local out = {}
    for part in tostring(value or "0"):gmatch("%d+") do table.insert(out, tonumber(part) or 0) end
    return out
  end
  local a, b = parts(left), parts(right)
  local size = math.max(#a, #b, 3)
  for index = 1, size do
    local av, bv = a[index] or 0, b[index] or 0
    if av ~= bv then return av > bv and 1 or -1 end
  end
  return 0
end

local function normalize_source(value)
  value = tostring(value or DEFAULT_SOURCE_URL)
  return value:gsub("/+$", "")
end

function M.new(ctx)
  local service = {
    ctx = ctx,
    state = {
      status = "idle",
      source = DEFAULT_SOURCE_URL,
      current = version.codename .. " " .. version.version,
      available = nil,
      error = nil,
      started_at = 0,
    },
  }

  local function configured_source()
    local stored = ctx.settings_service and ctx.settings_service.get("system.update_source", DEFAULT_SOURCE_URL).data or DEFAULT_SOURCE_URL
    if tostring(stored or ""):find("raw.githubusercontent.com/R15ofc/cc%-dock%-paralimni/", 1, false) then
      stored = DEFAULT_SOURCE_URL
    end
    return normalize_source(stored)
  end

  local function read_remote_version(source)
    if not http or not http.get then return nil, "HTTP unavailable" end
    local url = normalize_source(source) .. "/dock/system/version.lua"
    local handle, request_error = http.get(url)
    if not handle then return nil, request_error or "request failed" end
    local body = handle.readAll() or ""
    handle.close()
    local remote_codename = parse_field(body, "codename") or version.codename
    local remote_version = parse_field(body, "version") or version.version
    local remote_channel = parse_field(body, "channel") or version.channel
    return {
      codename = remote_codename,
      version = remote_version,
      channel = remote_channel,
      source = normalize_source(source),
    }
  end

  function service.beginCheck()
    service.state = {
      status = "checking",
      source = configured_source(),
      current = version.codename .. " " .. version.version,
      available = nil,
      error = nil,
      started_at = os.clock and os.clock() or 0,
    }
    return ok(service.state)
  end

  function service.checkNow()
    local source = configured_source()
    local remote, request_error = read_remote_version(source)
    if not remote then
      service.state.status = "error"
      service.state.error = request_error
      service.state.available = nil
      service.state.source = source
      return ok(service.state)
    end
    local newer = remote.codename ~= version.codename or compare_versions(remote.version, version.version) > 0
    if newer then
      service.state.status = "available"
      service.state.available = {
        title = "DockOS " .. remote.codename .. " " .. remote.version,
        changelog = "System files, apps, and interface assets from the update channel.",
        eta = "About 1 minute",
        source = remote.source,
        channel = remote.channel,
      }
    else
      service.state.status = "no_updates"
      service.state.available = nil
    end
    service.state.source = source
    service.state.error = nil
    return ok(service.state)
  end

  function service.poll()
    if service.state.status == "idle" then return service.beginCheck() end
    if service.state.status == "checking" then
      local elapsed = (os.clock and os.clock() or 0) - (service.state.started_at or 0)
      if elapsed >= 1.1 then return service.checkNow() end
    end
    return ok(service.state)
  end

  function service.status()
    return ok(service.state)
  end

  function service.setSource(source)
    source = normalize_source(source)
    if ctx.settings_service then ctx.settings_service.set("system.update_source", source) end
    service.state.source = source
    return ok(service.state)
  end

  function service.installAvailable()
    if service.state.status ~= "available" or not service.state.available then
      return err("no update available", "NO_UPDATE")
    end
    if not http or not http.get or not shell or not shell.run then
      return err("installer runtime unavailable", "UNAVAILABLE")
    end
    service.state.status = "installing"
    splash.sequence({
      logo = "DockOS",
      message = "Please do not turn off your computer",
      steps = { 8, 18, 28 },
      delay = 0.08,
    })
    local source = normalize_source(service.state.available.source)
    local handle, request_error = http.get(source .. "/dock-installer.lua")
    if not handle then
      service.state.status = "available"
      return err(request_error or "installer download failed", "DOWNLOAD_FAILED")
    end
    local installer_path = "/tmp/dock-update-installer.lua"
    if fs.exists(installer_path) then fs.delete(installer_path) end
    local out = fs.open(installer_path, "w")
    if not out then
      handle.close()
      service.state.status = "available"
      return err("cannot write installer", "WRITE_FAILED")
    end
    out.write(handle.readAll() or "")
    out.close()
    handle.close()
    splash.show({ logo = "DockOS", message = "Please do not turn off your computer", progress = 72 })
    shell.run(installer_path, source)
    splash.show({ logo = "DockOS", message = "Please do not turn off your computer", progress = 100 })
    service.state.status = "installed"
    return ok(service.state)
  end

  function service.start()
    return ok(true)
  end

  return service
end

return M
