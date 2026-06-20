local M = {}

local function ptype(name)
  if not peripheral or not peripheral.getType then return "" end
  local ok, kind = pcall(peripheral.getType, name)
  if not ok then return "" end
  return type(kind) == "table" and table.concat(kind, ",") or tostring(kind or "")
end

local function find(predicate)
  if not peripheral or not peripheral.getNames or not peripheral.wrap then return nil, "peripheral API unavailable" end
  for _, name in ipairs(peripheral.getNames()) do
    local device = peripheral.wrap(name)
    local kind = ptype(name):lower()
    if device and predicate(name, device, kind) then return name, device end
  end
  return nil, "not found"
end

function M.isAvailable()
  return M.findGPU() ~= nil or M.findKeyboard() ~= nil or M.findWatchdog() ~= nil
end

function M.findGPU()
  return find(function(_, device, kind)
    return (kind:find("gpu", 1, true) ~= nil) or type(device.decodeImage) == "function" or type(device.filledRectangle) == "function" or type(device.drawText) == "function"
  end)
end

function M.findKeyboard()
  return find(function(_, device, kind)
    return kind:find("keyboard", 1, true) ~= nil or type(device.setFireNativeEvents) == "function"
  end)
end

function M.findRedstonePort()
  return find(function(_, device, kind)
    return kind:find("redstone", 1, true) ~= nil or type(device.setOutput) == "function"
  end)
end

function M.findWatchdog()
  return find(function(_, device, kind)
    return kind:find("watchdog", 1, true) ~= nil or type(device.setTimeout) == "function" or type(device.feed) == "function"
  end)
end

function M.getCapabilities()
  local _, gpu = M.findGPU()
  local _, keyboard = M.findKeyboard()
  local _, redstone = M.findRedstonePort()
  local _, watchdog = M.findWatchdog()
  return {
    ["display.bitmap"] = gpu ~= nil,
    ["input.keyboard"] = keyboard ~= nil,
    ["redstone.extended"] = redstone ~= nil,
    watchdog = watchdog ~= nil,
  }
end

function M.setupWatchdog(timeout)
  local _, watchdog = M.findWatchdog()
  if not watchdog then return { ok = false, error = "watchdog not found", code = "NOT_FOUND" } end
  if watchdog.setTimeout then pcall(watchdog.setTimeout, timeout or 10) end
  if watchdog.start then pcall(watchdog.start) end
  return { ok = true }
end

function M.feedWatchdog()
  local _, watchdog = M.findWatchdog()
  if watchdog and watchdog.feed then pcall(watchdog.feed) end
  return { ok = watchdog ~= nil }
end

function M.shutdownWatchdog()
  local _, watchdog = M.findWatchdog()
  if watchdog and watchdog.stop then pcall(watchdog.stop) end
  return { ok = watchdog ~= nil }
end

function M.normalizeInputEvent(event, a, b, c, d)
  if event == "tm_keyboard_char" then return "char", b end
  if event == "tm_keyboard_key" then return "key", b, c end
  if event == "tm_keyboard_paste" then return "paste", b end
  if event == "tm_monitor_mouse_click" then return "mouse_click", c or 1, math.floor((a or b or 0) / 6) + 1, math.floor((b or c or 0) / 9) + 1 end
  return event, a, b, c, d
end

return M
