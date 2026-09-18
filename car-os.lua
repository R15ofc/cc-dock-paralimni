local args = { ... }

local SIGNAL_ON = 15
local BLINK_INTERVAL = 0.42
local TELEMETRY_INTERVAL = 0.10
local DEVICE_SCAN_INTERVAL = 2.00
local COMPUTER_SIDES = { "top", "right", "back", "left", "front", "bottom" }
local WORLD_SIDES = { "up", "down", "north", "south", "east", "west" }
local HEADINGS = { "north", "east", "south", "west" }

local COLORS = {
  background = 0x07090D,
  surface = 0x10141B,
  surface_alt = 0x171C25,
  border = 0x2B3340,
  text = 0xF5F7FA,
  muted = 0x9099A8,
  blue = 0x2F80ED,
  blue_soft = 0x173457,
  green = 0x36D17C,
  green_soft = 0x153B2A,
  orange = 0xFF9F32,
  red = 0xFF545F,
  red_soft = 0x4A2026,
  yellow = 0xFFD447,
  black = 0x000000,
}

local state = {
  mode = "standard",
  clutch = false,
  reverse = false,
  front_drive_off = false,
  workshop_engine_off = false,
  drive_engine_off = false,
  workshop_boost = false,
  lighting = "none",
  blink = false,
  running = true,
  speed_ms = 0,
  speed_kmh = 0,
  ship_available = false,
  port_heading = "north",
  io_error = nil,
  last_action = "SYSTEM READY",
  keyboard_connected = false,
  held_touch = nil,
}

local devices = {
  gpu_name = nil,
  gpu = nil,
  gpu_width = 384,
  gpu_height = 192,
  keyboard_name = nil,
  keyboard = nil,
  port_name = nil,
  port = nil,
  port_kind = nil,
}

local buttons = {}
local timers = {}
local native_term = term and term.current and term.current() or nil

local function clamp(value, minimum, maximum)
  value = tonumber(value) or minimum
  return math.max(minimum, math.min(maximum, value))
end

local function round(value)
  return math.floor((tonumber(value) or 0) + 0.5)
end

local function settings_get(name, fallback)
  if not settings or not settings.get then return fallback end
  local ok, value = pcall(settings.get, name, fallback)
  if not ok or value == nil then return fallback end
  return value
end

local function settings_set(name, value)
  if not settings or not settings.set then return end
  pcall(settings.set, name, value)
  if settings.save then pcall(settings.save) end
end

local configured_heading = tostring(settings_get("caros.port_heading", "north")):lower()
for _, heading in ipairs(HEADINGS) do
  if configured_heading == heading then state.port_heading = heading end
end

local function peripheral_type(name)
  if not peripheral or not peripheral.getType then return "" end
  local ok, kind = pcall(peripheral.getType, name)
  if not ok then return "" end
  if type(kind) == "table" then return table.concat(kind, ","):lower() end
  return tostring(kind or ""):lower()
end

local function has_method(name, wanted)
  if not peripheral or not peripheral.getMethods then return false end
  local ok, methods = pcall(peripheral.getMethods, name)
  if not ok or type(methods) ~= "table" then return false end
  for _, method in ipairs(methods) do
    if method == wanted then return true end
  end
  return false
end

local function is_gpu(_, device, kind)
  return kind:find("tm_gpu", 1, true) ~= nil
    or (type(device.refreshSize) == "function" and type(device.sync) == "function"
      and (type(device.filledRectangle) == "function" or type(device.fill) == "function"))
end

local function is_keyboard(_, device, kind)
  return kind:find("tm_keyboard", 1, true) ~= nil
    or type(device.setFireNativeEvents) == "function"
end

local function is_tom_port(name, device, kind)
  return kind:find("tm_rsport", 1, true) ~= nil
    or (has_method(name, "getSides") and type(device.setAnalogOutput) == "function")
end

local function is_relay(_, device, kind)
  return kind:find("redstone_relay", 1, true) ~= nil
    or kind:find("redstone", 1, true) ~= nil
    or type(device.setAnalogOutput) == "function"
end

local function find_device(predicate, preferred)
  if not peripheral or not peripheral.getNames or not peripheral.wrap then return nil, nil, nil end
  if preferred and preferred ~= "" and peripheral.isPresent and peripheral.isPresent(preferred) then
    local device = peripheral.wrap(preferred)
    local kind = peripheral_type(preferred)
    if device and predicate(preferred, device, kind) then return preferred, device, kind end
  end
  for _, name in ipairs(peripheral.getNames()) do
    local device = peripheral.wrap(name)
    local kind = peripheral_type(name)
    if device and predicate(name, device, kind) then return name, device, kind end
  end
  return nil, nil, nil
end

local function refresh_gpu_size(configure)
  local gpu = devices.gpu
  if not gpu then return end
  if configure and gpu.refreshSize then pcall(gpu.refreshSize) end
  if configure and gpu.setSize then pcall(gpu.setSize, 64) end
  if gpu.getSize then
    local ok, width, height = pcall(gpu.getSize)
    width, height = tonumber(width), tonumber(height)
    if ok and width and height and width > 0 and height > 0 then
      devices.gpu_width = math.floor(width)
      devices.gpu_height = math.floor(height)
    end
  end
end

local function configure_keyboard()
  if devices.keyboard and devices.keyboard.setFireNativeEvents then
    local ok = pcall(devices.keyboard.setFireNativeEvents, true)
    if not ok then state.io_error = "KEYBOARD CONFIGURATION FAILED" end
  end
end

local function scan_devices(initial)
  local previous_gpu = devices.gpu_name
  local previous_keyboard = devices.keyboard_name
  local previous_port = devices.port_name

  devices.gpu_name, devices.gpu = find_device(is_gpu)
  devices.keyboard_name, devices.keyboard = find_device(is_keyboard)

  local preferred_port = args[1] or settings_get("caros.port", nil)
  local port_name, port = find_device(is_tom_port, preferred_port)
  if port then
    devices.port_name, devices.port, devices.port_kind = port_name, port, "tom"
  else
    port_name, port = find_device(is_relay, preferred_port)
    devices.port_name, devices.port = port_name, port
    devices.port_kind = port and "relay" or nil
  end

  if devices.port_name and settings_get("caros.port", nil) ~= devices.port_name then
    settings_set("caros.port", devices.port_name)
  end
  if initial or previous_keyboard ~= devices.keyboard_name then configure_keyboard() end
  refresh_gpu_size(initial or previous_gpu ~= devices.gpu_name)

  if not initial and (previous_gpu ~= devices.gpu_name or previous_keyboard ~= devices.keyboard_name or previous_port ~= devices.port_name) then
    state.last_action = "DEVICES UPDATED"
  end
end

local function horizontal_port_map(heading)
  if heading == "east" then
    return { front = "east", right = "south", back = "west", left = "north" }
  elseif heading == "south" then
    return { front = "south", right = "west", back = "north", left = "east" }
  elseif heading == "west" then
    return { front = "west", right = "north", back = "east", left = "south" }
  end
  return { front = "north", right = "east", back = "south", left = "west" }
end

local function port_side(relative_side)
  if devices.port_kind ~= "tom" then return relative_side end
  if relative_side == "top" then return "up" end
  if relative_side == "bottom" then return "down" end
  return horizontal_port_map(state.port_heading)[relative_side]
end

local function set_error(scope, side, err)
  state.io_error = string.upper(scope .. " " .. tostring(side) .. ": " .. tostring(err or "write failed"))
end

local function write_chassis(side, enabled)
  if not redstone then
    set_error("computer", side, "redstone API missing")
    return false
  end
  local value = enabled and SIGNAL_ON or 0
  if redstone.setAnalogOutput then
    local ok, err = pcall(redstone.setAnalogOutput, side, value)
    if ok then return true end
    set_error("computer", side, err)
  elseif redstone.setOutput then
    local ok, err = pcall(redstone.setOutput, side, enabled == true)
    if ok then return true end
    set_error("computer", side, err)
  end
  return false
end

local function write_port(relative_side, enabled)
  local port = devices.port
  if not port then
    set_error("port", relative_side, "not found")
    return false
  end
  local side = port_side(relative_side)
  local value = enabled and SIGNAL_ON or 0
  local ok, err
  if port.setAnalogOutput then
    ok, err = pcall(port.setAnalogOutput, side, value)
  elseif port.setAnalogueOutput then
    ok, err = pcall(port.setAnalogueOutput, side, value)
  elseif port.setOutput then
    ok, err = pcall(port.setOutput, side, enabled == true)
  else
    set_error("port", side, "output method missing")
    return false
  end
  if not ok then
    set_error("port", side, err)
    return false
  end
  return true
end

local function all_chassis_off()
  for _, side in ipairs(COMPUTER_SIDES) do write_chassis(side, false) end
end

local function all_port_off()
  if not devices.port then return end
  local sides = devices.port_kind == "tom" and WORLD_SIDES or COMPUTER_SIDES
  for _, side in ipairs(sides) do
    local port = devices.port
    if port.setAnalogOutput then pcall(port.setAnalogOutput, side, 0)
    elseif port.setAnalogueOutput then pcall(port.setAnalogueOutput, side, 0)
    elseif port.setOutput then pcall(port.setOutput, side, false) end
  end
end

local function all_off()
  all_chassis_off()
  all_port_off()
end

local function set_lighting(mode)
  if state.lighting == mode then mode = "none" end
  state.lighting = mode or "none"
end

local function cycle_indicator()
  if state.lighting == "right" then
    state.lighting = "left"
  elseif state.lighting == "left" then
    state.lighting = "none"
  else
    state.lighting = "right"
  end
end

local function apply_outputs()
  state.io_error = nil

  write_chassis("top", state.mode == "sport" or state.mode == "sport_plus")
  write_chassis("right", state.mode == "sport_plus")
  write_chassis("back", state.reverse)
  write_chassis("left", state.front_drive_off)
  write_chassis("front", state.workshop_engine_off)
  write_chassis("bottom", state.drive_engine_off)

  write_port("top", state.clutch)
  write_port("left", state.workshop_boost)
  write_port("right", (state.lighting == "right" or state.lighting == "hazard") and state.blink)
  write_port("back", (state.lighting == "left" or state.lighting == "hazard") and state.blink)
  write_port("bottom", state.lighting == "headlights")
end

local function update_speed()
  state.ship_available = false
  state.speed_ms = 0
  state.speed_kmh = 0
  if type(ship) ~= "table" or type(ship.getVelocity) ~= "function" then return end
  local ok, velocity = pcall(ship.getVelocity)
  if not ok or type(velocity) ~= "table" then return end
  local x = tonumber(velocity.x or velocity[1]) or 0
  local y = tonumber(velocity.y or velocity[2]) or 0
  local z = tonumber(velocity.z or velocity[3]) or 0
  state.speed_ms = math.sqrt((x * x) + (y * y) + (z * z))
  state.speed_kmh = state.speed_ms * 3.6
  state.ship_available = true
end

local function gpu_rect(x, y, width, height, color)
  local gpu = devices.gpu
  if not gpu then return end
  x, y = math.floor(x), math.floor(y)
  width, height = math.floor(width), math.floor(height)
  local right = math.min(devices.gpu_width, x + width - 1)
  local bottom = math.min(devices.gpu_height, y + height - 1)
  x, y = math.max(1, x), math.max(1, y)
  width, height = right - x + 1, bottom - y + 1
  if width <= 0 or height <= 0 then return end
  if gpu.filledRectangle then
    pcall(gpu.filledRectangle, x, y, width, height, color)
  elseif gpu.fillRect then
    local red = math.floor(color / 65536) % 256
    local green = math.floor(color / 256) % 256
    local blue = color % 256
    pcall(gpu.fillRect, x, y, width, height, red, green, blue)
  end
end

local function gpu_round_rect(x, y, width, height, color)
  if width < 8 or height < 8 then return gpu_rect(x, y, width, height, color) end
  gpu_rect(x + 3, y, width - 6, height, color)
  gpu_rect(x, y + 3, width, height - 6, color)
  gpu_rect(x + 1, y + 1, width - 2, height - 2, color)
end

local function gpu_outline(x, y, width, height, color)
  gpu_rect(x + 3, y, width - 6, 1, color)
  gpu_rect(x + 3, y + height - 1, width - 6, 1, color)
  gpu_rect(x, y + 3, 1, height - 6, color)
  gpu_rect(x + width - 1, y + 3, 1, height - 6, color)
  gpu_rect(x + 1, y + 1, 2, 1, color)
  gpu_rect(x + width - 3, y + 1, 2, 1, color)
  gpu_rect(x + 1, y + height - 2, 2, 1, color)
  gpu_rect(x + width - 3, y + height - 2, 2, 1, color)
end

local function text_width(text, size)
  text = tostring(text or "")
  size = math.max(1, math.floor(size or 1))
  local gpu = devices.gpu
  if gpu and gpu.getTextLength then
    local ok, width = pcall(gpu.getTextLength, text, size, 0)
    if ok and type(width) == "number" then return width end
  end
  return #text * 6 * size
end

local function gpu_text(x, y, text, color, size)
  local gpu = devices.gpu
  if not gpu or not gpu.drawText then return end
  text = tostring(text or "")
  x, y = math.floor(x), math.floor(y)
  size = math.max(1, math.floor(size or 1))
  if x > devices.gpu_width or y > devices.gpu_height then return end
  pcall(gpu.drawText, x, y, text, color or COLORS.text, -1, size, 0)
end

local function gpu_center_text(x, y, width, text, color, size)
  gpu_text(x + math.max(0, math.floor((width - text_width(text, size)) / 2)), y, text, color, size)
end

local function add_button(id, x, y, width, height, label, subtitle, active, accent, kind)
  table.insert(buttons, { id = id, x = x, y = y, w = width, h = height, kind = kind or "toggle" })
  local fill_color = active and accent or COLORS.surface_alt
  local border_color = active and accent or COLORS.border
  gpu_round_rect(x, y, width, height, fill_color)
  gpu_outline(x, y, width, height, border_color)
  gpu_center_text(x, y + 6, width, label, active and COLORS.black or COLORS.text, 1)
  if subtitle and subtitle ~= "" then
    gpu_center_text(x, y + height - 10, width, subtitle, active and COLORS.black or COLORS.muted, 1)
  end
end

local function find_button(x, y)
  for index = #buttons, 1, -1 do
    local button = buttons[index]
    if x >= button.x and x <= button.x + button.w - 1 and y >= button.y and y <= button.y + button.h - 1 then return button end
  end
  return nil
end

local function mode_label()
  if state.mode == "sport_plus" then return "SPORT+" end
  if state.mode == "sport" then return "SPORT" end
  return "STANDARD"
end

local function lighting_label()
  if state.lighting == "headlights" then return "HEADLIGHTS" end
  if state.lighting == "hazard" then return "HAZARD" end
  if state.lighting == "left" then return "LEFT SIGNAL" end
  if state.lighting == "right" then return "RIGHT SIGNAL" end
  return "LIGHTS OFF"
end

local function draw_gpu()
  local gpu = devices.gpu
  if not gpu then return end
  buttons = {}
  local width, height = devices.gpu_width, devices.gpu_height
  local scale_x = width / 384
  local scale_y = height / 192
  local function px(value) return math.max(1, math.floor(value * scale_x + 0.5)) end
  local function py(value) return math.max(1, math.floor(value * scale_y + 0.5)) end

  if gpu.fill then pcall(gpu.fill, COLORS.background) else gpu_rect(1, 1, width, height, COLORS.background) end

  gpu_text(px(10), py(8), "CAR OS", COLORS.text, 1)
  gpu_text(px(57), py(8), "DRIVE CONTROL", COLORS.muted, 1)

  local status_x = width - px(153)
  gpu_round_rect(status_x, py(5), px(44), py(15), devices.port and COLORS.green_soft or COLORS.red_soft)
  gpu_center_text(status_x, py(9), px(44), devices.port and "PORT" or "NO PORT", devices.port and COLORS.green or COLORS.red, 1)
  gpu_round_rect(status_x + px(48), py(5), px(44), py(15), devices.keyboard and COLORS.green_soft or COLORS.red_soft)
  gpu_center_text(status_x + px(48), py(9), px(44), devices.keyboard and "KEYS" or "NO KEYS", devices.keyboard and COLORS.green or COLORS.red, 1)
  add_button("heading", status_x + px(96), py(5), px(55), py(15), "PORT " .. state.port_heading:sub(1, 1):upper(), nil, false, COLORS.blue)

  local speed_x, speed_y, speed_w, speed_h = px(9), py(29), px(112), py(134)
  gpu_round_rect(speed_x, speed_y, speed_w, speed_h, COLORS.surface)
  gpu_outline(speed_x, speed_y, speed_w, speed_h, COLORS.border)
  gpu_text(speed_x + px(10), speed_y + py(10), "SPEED", COLORS.muted, 1)
  gpu_text(speed_x + speed_w - px(42), speed_y + py(10), state.ship_available and "CC:VS" or "NO VS", state.ship_available and COLORS.green or COLORS.red, 1)
  local speed_text = state.ship_available and string.format("%03d", clamp(round(state.speed_kmh), 0, 999)) or "---"
  gpu_center_text(speed_x, speed_y + py(39), speed_w, speed_text, COLORS.text, 3)
  gpu_center_text(speed_x, speed_y + py(72), speed_w, "KM/H", COLORS.muted, 1)
  gpu_center_text(speed_x, speed_y + py(91), speed_w, mode_label(), state.mode == "standard" and COLORS.text or COLORS.orange, 1)
  local speed_bar_x = speed_x + px(10)
  local speed_bar_y = speed_y + speed_h - py(14)
  local speed_bar_w = speed_w - px(20)
  gpu_round_rect(speed_bar_x, speed_bar_y, speed_bar_w, py(5), COLORS.border)
  gpu_round_rect(speed_bar_x, speed_bar_y, math.max(px(4), math.floor(speed_bar_w * clamp(state.speed_kmh / 180, 0, 1))), py(5), state.speed_kmh > 130 and COLORS.red or COLORS.blue)

  local panel_x = px(129)
  local panel_w = width - panel_x - px(9)
  local gap = px(5)
  local three_w = math.floor((panel_w - gap * 2) / 3)
  local four_w = math.floor((panel_w - gap * 3) / 4)

  local row_y, row_h = py(29), py(29)
  add_button("standard", panel_x, row_y, three_w, row_h, "STANDARD", "0", state.mode == "standard", COLORS.blue)
  add_button("sport", panel_x + three_w + gap, row_y, three_w, row_h, "SPORT", "TOP", state.mode == "sport", COLORS.orange)
  add_button("sport_plus", panel_x + (three_w + gap) * 2, row_y, panel_w - (three_w + gap) * 2, row_h, "SPORT+", "TOP + RIGHT", state.mode == "sport_plus", COLORS.red)

  row_y = py(64)
  row_h = py(31)
  add_button("clutch", panel_x, row_y, four_w, row_h, "CLUTCH", "W HOLD", state.clutch, COLORS.green, "hold")
  add_button("reverse", panel_x + four_w + gap, row_y, four_w, row_h, "REVERSE", "S HOLD", state.reverse, COLORS.orange, "hold")
  add_button("front_drive", panel_x + (four_w + gap) * 2, row_y, four_w, row_h, "FRONT", state.front_drive_off and "DISABLED" or "DRIVE ON", state.front_drive_off, COLORS.red)
  add_button("drive_engine", panel_x + (four_w + gap) * 3, row_y, panel_w - (four_w + gap) * 3, row_h, "DRIVE", state.drive_engine_off and "OFF" or "ON", state.drive_engine_off, COLORS.red)

  row_y = py(101)
  add_button("work_engine", panel_x, row_y, three_w, row_h, "WORKSHOP", state.workshop_engine_off and "OFF" or "ON", state.workshop_engine_off, COLORS.red)
  add_button("boost", panel_x + three_w + gap, row_y, three_w, row_h, "WORK BOOST", "PORT LEFT", state.workshop_boost, COLORS.orange, "hold")
  gpu_round_rect(panel_x + (three_w + gap) * 2, row_y, panel_w - (three_w + gap) * 2, row_h, COLORS.surface)
  gpu_outline(panel_x + (three_w + gap) * 2, row_y, panel_w - (three_w + gap) * 2, row_h, COLORS.border)
  gpu_center_text(panel_x + (three_w + gap) * 2, row_y + py(6), panel_w - (three_w + gap) * 2, lighting_label(), COLORS.text, 1)
  gpu_center_text(panel_x + (three_w + gap) * 2, row_y + py(20), panel_w - (three_w + gap) * 2, "L / Z / X", COLORS.muted, 1)

  row_y = py(138)
  add_button("headlights", panel_x, row_y, four_w, row_h, "LIGHTS", "L", state.lighting == "headlights", COLORS.blue)
  add_button("left", panel_x + four_w + gap, row_y, four_w, row_h, "LEFT", "Z", state.lighting == "left" and state.blink, COLORS.yellow)
  add_button("right", panel_x + (four_w + gap) * 2, row_y, four_w, row_h, "RIGHT", "Z", state.lighting == "right" and state.blink, COLORS.yellow)
  add_button("hazard", panel_x + (four_w + gap) * 3, row_y, panel_w - (four_w + gap) * 3, row_h, "HAZARD", "X", state.lighting == "hazard" and state.blink, COLORS.red)

  local footer_y = height - py(15)
  gpu_text(px(10), footer_y, state.io_error or state.last_action, state.io_error and COLORS.red or COLORS.muted, 1)
  local hint = "G FRONT  F DRIVE  R PORT  Q EXIT"
  gpu_text(width - text_width(hint, 1) - px(10), footer_y, hint, COLORS.muted, 1)
  if gpu.sync then pcall(gpu.sync) end
end

local function draw_terminal()
  if not term then return end
  pcall(function()
    term.redirect(native_term)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    print("CarOS Drive Control")
    print("Mode: " .. mode_label())
    print("Speed: " .. (state.ship_available and string.format("%.1f km/h", state.speed_kmh) or "CC:VS unavailable"))
    print("GPU: " .. tostring(devices.gpu_name or "not found"))
    print("Keyboard: " .. tostring(devices.keyboard_name or "not found"))
    print("Redstone port: " .. tostring(devices.port_name or "not found"))
    print("Port heading: " .. state.port_heading)
    print("")
    print("W/S hold  G/F/L/Z/X toggle  Q exit")
    if state.io_error then
      term.setTextColor(colors.red)
      print(state.io_error)
    end
  end)
end

local function draw()
  if devices.gpu then draw_gpu() else draw_terminal() end
end

local function perform(action, pressed, touch_toggle)
  if action == "standard" then state.mode = "standard"
  elseif action == "sport" then state.mode = "sport"
  elseif action == "sport_plus" then state.mode = "sport_plus"
  elseif action == "clutch" then
    if touch_toggle then state.clutch = not state.clutch else state.clutch = pressed end
  elseif action == "reverse" then
    if touch_toggle then state.reverse = not state.reverse else state.reverse = pressed end
  elseif action == "boost" then
    if touch_toggle then state.workshop_boost = not state.workshop_boost else state.workshop_boost = pressed end
  elseif action == "front_drive" and pressed then state.front_drive_off = not state.front_drive_off
  elseif action == "drive_engine" and pressed then state.drive_engine_off = not state.drive_engine_off
  elseif action == "work_engine" and pressed then state.workshop_engine_off = not state.workshop_engine_off
  elseif action == "headlights" and pressed then set_lighting("headlights")
  elseif action == "right" and pressed then set_lighting("right")
  elseif action == "left" and pressed then set_lighting("left")
  elseif action == "hazard" and pressed then set_lighting("hazard")
  elseif action == "heading" and pressed then
    all_port_off()
    local current = 1
    for index, heading in ipairs(HEADINGS) do if heading == state.port_heading then current = index break end end
    state.port_heading = HEADINGS[(current % #HEADINGS) + 1]
    settings_set("caros.port_heading", state.port_heading)
  end
  state.last_action = string.upper(tostring(action or "control"))
  apply_outputs()
  draw()
end

local function key_name(code)
  if type(code) == "string" then return code:lower() end
  if keys and keys.getName then
    local ok, name = pcall(keys.getName, code)
    if ok and name then return tostring(name):lower() end
  end
  return tostring(code or ""):lower()
end

local function release_drive_keys()
  state.clutch = false
  state.reverse = false
  apply_outputs()
end

local function handle_key(code, down, repeated)
  local name = key_name(code)
  local fresh = down and not repeated
  if name == "w" then state.clutch = down
  elseif name == "s" then state.reverse = down
  elseif fresh and name == "g" then state.front_drive_off = not state.front_drive_off
  elseif fresh and name == "f" then state.drive_engine_off = not state.drive_engine_off
  elseif fresh and name == "l" then set_lighting("headlights")
  elseif fresh and name == "x" then set_lighting("hazard")
  elseif fresh and name == "z" then cycle_indicator()
  elseif fresh and name == "r" then perform("heading", true, false) return
  elseif fresh and name == "q" then state.running = false
  else return end
  state.last_action = string.upper(name) .. (down and " PRESSED" or " RELEASED")
  apply_outputs()
  draw()
end

local function schedule(name, delay)
  if os and os.startTimer then timers[os.startTimer(delay)] = name end
end

local function handle_pointer(event, a, b, c)
  local x, y, button, released, touch
  if event == "tm_monitor_mouse_click" then
    x, y, button = tonumber(a), tonumber(b), tonumber(c) or 1
  elseif event == "tm_monitor_mouse_up" then
    x, y, button, released = tonumber(a), tonumber(b), tonumber(c) or 1, true
  elseif event == "tm_monitor_touch" then
    x, y, button, touch = tonumber(a), tonumber(b), 1, true
  elseif event == "monitor_touch" then
    x, y, button, touch = tonumber(b), tonumber(c), 1, true
  elseif event == "mouse_click" then
    button = tonumber(a) or 1
    x = ((tonumber(b) or 1) - 1) * 6 + 1
    y = ((tonumber(c) or 1) - 1) * 9 + 1
  elseif event == "mouse_up" then
    button = tonumber(a) or 1
    x = ((tonumber(b) or 1) - 1) * 6 + 1
    y = ((tonumber(c) or 1) - 1) * 9 + 1
    released = true
  else
    return false
  end

  if released then
    if state.held_touch then
      local held = state.held_touch
      state.held_touch = nil
      perform(held, false, false)
    end
    return true
  end

  if button ~= 1 or not x or not y then return true end
  local hit = find_button(x, y)
  if hit then
    if hit.kind == "hold" and not touch then state.held_touch = hit.id end
    perform(hit.id, true, touch == true)
  end
  return true
end

local function initialize()
  scan_devices(true)
  if devices.gpu and sleep then sleep(0.12) refresh_gpu_size(true) end
  update_speed()
  all_off()
  apply_outputs()
  draw()
  schedule("blink", BLINK_INTERVAL)
  schedule("telemetry", TELEMETRY_INTERVAL)
  schedule("scan", DEVICE_SCAN_INTERVAL)
end

local function main()
  initialize()
  while state.running do
    local event, a, b, c, d = os.pullEventRaw()
    if event == "terminate" then
      state.running = false
    elseif event == "timer" then
      local timer_name = timers[a]
      timers[a] = nil
      if timer_name == "blink" then
        state.blink = not state.blink
        apply_outputs()
        draw()
        schedule("blink", BLINK_INTERVAL)
      elseif timer_name == "telemetry" then
        update_speed()
        draw()
        schedule("telemetry", TELEMETRY_INTERVAL)
      elseif timer_name == "scan" then
        scan_devices(false)
        apply_outputs()
        draw()
        schedule("scan", DEVICE_SCAN_INTERVAL)
      end
    elseif event == "key" then handle_key(a, true, b == true)
    elseif event == "key_up" then handle_key(a, false, false)
    elseif event == "tm_keyboard_key" then handle_key(b, true, c == true)
    elseif event == "tm_keyboard_key_up" then handle_key(b, false, false)
    elseif event == "portable_connect" or event == "tm_keyboard_portable_connect" then
      state.keyboard_connected = true
      state.last_action = "PORTABLE KEYBOARD CONNECTED"
      draw()
    elseif event == "portable_disconnect" or event == "tm_keyboard_portable_disconnect" then
      state.keyboard_connected = false
      release_drive_keys()
      state.last_action = "PORTABLE KEYBOARD DISCONNECTED"
      draw()
    elseif event == "peripheral" or event == "peripheral_detach" then
      scan_devices(false)
      apply_outputs()
      draw()
    else
      handle_pointer(event, a, b, c, d)
    end
  end
end

local ok, err = xpcall(main, debug.traceback)
all_off()
if native_term and term and term.redirect then term.redirect(native_term) end
if term then
  pcall(function()
    term.setBackgroundColor(colors.black)
    term.setTextColor(ok and colors.white or colors.red)
    term.clear()
    term.setCursorPos(1, 1)
    if ok then print("CarOS stopped. All outputs are off.") else print("CarOS failure:\n" .. tostring(err)) end
  end)
end
