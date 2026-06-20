local tom = require("dock.system.tom_adapter")

local M = {}

function M.new(ctx)
  local service = { ctx = ctx, devices = {}, capabilities = {} }

  function service.scan()
    local list = {}
    if peripheral and peripheral.getNames then
      for _, name in ipairs(peripheral.getNames()) do
        local ok, kind = pcall(peripheral.getType, name)
        table.insert(list, { name = name, type = ok and kind or "unknown" })
      end
    end
    service.devices = list
    service.capabilities = {
      ["display.text"] = term ~= nil,
      ["display.color"] = term and term.isColor and term.isColor() or false,
      ["display.bitmap"] = tom.getCapabilities()["display.bitmap"] or false,
      ["input.keyboard"] = true,
      ["input.mouse"] = true,
      ["network.rednet"] = rednet ~= nil,
      ["redstone.extended"] = tom.getCapabilities()["redstone.extended"] or false,
      watchdog = tom.getCapabilities().watchdog or false,
    }
    return { ok = true, data = list }
  end

  function service.listPeripherals() return { ok = true, data = service.devices } end
  function service.getCapabilities() return { ok = true, data = service.capabilities } end
  function service.findMonitors() local out = {}; for _, d in ipairs(service.devices) do if tostring(d.type):find("monitor") then table.insert(out, d) end end; return { ok = true, data = out } end
  function service.findModems() local out = {}; for _, d in ipairs(service.devices) do if tostring(d.type):find("modem") then table.insert(out, d) end end; return { ok = true, data = out } end
  function service.findSpeakers() local out = {}; for _, d in ipairs(service.devices) do if tostring(d.type):find("speaker") then table.insert(out, d) end end; return { ok = true, data = out } end
  function service.findPrinters() local out = {}; for _, d in ipairs(service.devices) do if tostring(d.type):find("printer") then table.insert(out, d) end end; return { ok = true, data = out } end
  function service.findRedstoneRelays() local name, device = tom.findRedstonePort(); return { ok = true, data = name and { { name = name, device = device } } or {} } end

  function service.start()
    service.scan()
    return { ok = true }
  end

  service.scan()
  return service
end

return M
