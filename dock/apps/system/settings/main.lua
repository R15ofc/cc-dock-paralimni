return {
  run = function(ctx)
    print(ctx.version.name .. " " .. ctx.version.codename .. " " .. ctx.version.version)
    print("User: " .. ctx.user_service.getCurrentUser().name)
    local caps = ctx.device_service.getCapabilities().data or {}
    for key, value in pairs(caps) do
      print(key .. ": " .. tostring(value))
    end
    return { ok = true }
  end,
}
