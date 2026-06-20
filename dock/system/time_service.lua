local M = {}

local function clamp_offset(value)
  local number = tonumber(value) or 3
  if number < -12 then number = -12 end
  if number > 14 then number = 14 end
  return number
end

local function pad(value)
  value = tonumber(value) or 0
  if value < 10 then return "0" .. tostring(value) end
  return tostring(value)
end

function M.new(ctx)
  local service = { ctx = ctx, timezone = 3 }

  function service.load()
    local stored = ctx.settings_service and ctx.settings_service.get("user.timezone", 3).data or 3
    service.timezone = clamp_offset(stored)
    return { ok = true, data = service.timezone }
  end

  function service.setTimezone(offset)
    service.timezone = clamp_offset(offset)
    if ctx.settings_service then ctx.settings_service.set("user.timezone", service.timezone) end
    if ctx.event_bus then ctx.event_bus.emit("time_timezone_changed", { timezone = service.timezone }) end
    return { ok = true, data = service.timezone }
  end

  function service.getTimezone()
    return { ok = true, data = service.timezone }
  end

  function service.epochUtc()
    if os.epoch then return math.floor(os.epoch("utc") / 1000) end
    return math.floor(os.time() * 86400)
  end

  function service.parts()
    local seconds = service.epochUtc() + service.timezone * 3600
    local day = seconds % 86400
    local hour = math.floor(day / 3600)
    local minute = math.floor((day % 3600) / 60)
    local second = day % 60
    return { ok = true, data = { hour = hour, minute = minute, second = second, timezone = service.timezone } }
  end

  function service.clockText()
    local parts = service.parts().data
    return pad(parts.hour) .. ":" .. pad(parts.minute)
  end

  function service.timezoneText()
    if service.timezone >= 0 then return "UTC+" .. tostring(service.timezone) end
    return "UTC" .. tostring(service.timezone)
  end

  function service.start()
    return service.load()
  end

  service.load()
  return service
end

return M
