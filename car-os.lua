local args = { ... }

local SIDES = { "top", "right", "back", "left", "front", "bottom" }
local SIGNAL_ON = 15
local BLINK_INTERVAL = 0.45

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
  message = "",
  held_action = nil,
}

local buttons = {}
local timers = {}
local display_name = "terminal"
local native_term = term.current()

local function has_color()
  return term.isColor and term.isColor()
end

local palette = {
  bg = colors.black,
  panel = has_color() and colors.gray or colors.black,
  active = has_color() and colors.lime or colors.white,
  warning = has_color() and colors.orange or colors.white,
  danger = has_color() and colors.red or colors.white,
  text = colors.white,
  muted = has_color() and colors.lightGray or colors.white,
  button = has_color() and colors.gray or colors.black,
  off = has_color() and colors.gray or colors.black,
}

local function set_colors(fg, bg)
  if term.setTextColor then term.setTextColor(fg or palette.text) end
  if term.setBackgroundColor then term.setBackgroundColor(bg or palette.bg) end
end

local function clear()
  set_colors(palette.text, palette.bg)
  term.clear()
  term.setCursorPos(1, 1)
end

local function write_at(x, y, text, fg, bg)
  local width = term.getSize()
  if y < 1 or x > width then return end
  text = tostring(text or "")
  if x < 1 then
    text = text:sub(2 - x)
    x = 1
  end
  if #text > width - x + 1 then text = text:sub(1, width - x + 1) end
  term.setCursorPos(x, y)
  set_colors(fg or palette.text, bg or palette.bg)
  term.write(text)
end

local function fill(x, y, width, height, bg)
  if width <= 0 or height <= 0 then return end
  set_colors(palette.text, bg or palette.bg)
  local line = string.rep(" ", width)
  for row = 0, height - 1 do
    term.setCursorPos(x, y + row)
    term.write(line)
  end
end

local function box(x, y, width, height, title, active)
  local bg = active and palette.active or palette.button
  fill(x, y, width, height, bg)
  local label = tostring(title or "")
  local text_x = x + math.max(0, math.floor((width - #label) / 2))
  local fg = active and colors.black or palette.text
  write_at(text_x, y + math.floor(height / 2), label, fg, bg)
end

local function add_button(id, x, y, width, height, label, active, kind)
  table.insert(buttons, { id = id, x = x, y = y, w = width, h = height, kind = kind or "toggle" })
  box(x, y, width, height, label, active)
end

local function find_button(x, y)
  for index = #buttons, 1, -1 do
    local button = buttons[index]
    if x >= button.x and x <= button.x + button.w - 1 and y >= button.y and y <= button.y + button.h - 1 then
      return button
    end
  end
  return nil
end

local function write_chassis(side, value)
  if not redstone then return false end
  value = value and SIGNAL_ON or 0
  if redstone.setAnalogOutput and pcall(redstone.setAnalogOutput, side, value) then return true end
  if redstone.setOutput and pcall(redstone.setOutput, side, value > 0) then return true end
  return false
end

local function is_redstone_peripheral(name)
  if not peripheral or not peripheral.getMethods then return false end
  local ok, methods = pcall(peripheral.getMethods, name)
  if not ok or type(methods) ~= "table" then return false end
  for _, method in ipairs(methods) do
    if method == "setAnalogOutput" or method == "setOutput" then return true end
  end
  return false
end

local function find_port()
  local configured = args[1] or (settings and settings.get and settings.get("caros.port"))
  if configured and configured ~= "" and peripheral and peripheral.isPresent and peripheral.isPresent(configured) and is_redstone_peripheral(configured) then
    if settings and settings.set then
      settings.set("caros.port", configured)
      if settings.save then pcall(settings.save, ".settings") end
    end
    return configured, peripheral.wrap(configured)
  end
  if not peripheral or not peripheral.getNames then return nil, nil end
  for _, name in ipairs(peripheral.getNames()) do
    if is_redstone_peripheral(name) then return name, peripheral.wrap(name) end
  end
  return nil, nil
end

local port_name, port = find_port()

local function write_port(side, value)
  if not port then return false end
  value = value and SIGNAL_ON or 0
  if port.setAnalogOutput and pcall(port.setAnalogOutput, side, value) then return true end
  if port.setOutput and pcall(port.setOutput, side, value > 0) then return true end
  return false
end

local function all_off()
  for _, side in ipairs(SIDES) do
    write_chassis(side, false)
    write_port(side, false)
  end
end

local function set_lighting(mode)
  mode = mode or "none"
  if state.lighting == mode then mode = "none" end
  state.lighting = mode
end

local function cycle_indicator()
  if state.lighting == "right" then state.lighting = "left"
  elseif state.lighting == "left" then state.lighting = "none"
  else state.lighting = "right" end
end

local function set_mode(mode)
  if mode == "sport" or mode == "sport_plus" then state.mode = mode else state.mode = "standard" end
end

local function apply_outputs()
  write_chassis("top", state.mode == "sport" or state.mode == "sport_plus")
  write_chassis("right", state.mode == "sport_plus")
  write_chassis("back", state.reverse)
  write_chassis("left", state.front_drive_off)
  write_chassis("front", state.workshop_engine_off)
  write_chassis("bottom", state.drive_engine_off)

  write_port("top", state.clutch)
  write_port("left", state.workshop_boost)

  local blink_on = state.blink
  write_port("right", (state.lighting == "right" or state.lighting == "hazard") and blink_on)
  write_port("back", (state.lighting == "left" or state.lighting == "hazard") and blink_on)
  write_port("bottom", state.lighting == "headlights")
end

local function mode_label()
  if state.mode == "sport_plus" then return "SPORT+" end
  if state.mode == "sport" then return "SPORT" end
  return "STANDARD"
end

local function bool_label(value)
  return value and "ON" or "OFF"
end

local function draw()
  buttons = {}
  local width, height = term.getSize()
  clear()
  write_at(2, 1, "CarOS Drive Controller", colors.white, palette.bg)
  write_at(width - math.min(width - 1, 18), 1, "Q exit", palette.muted, palette.bg)
  write_at(2, 2, "Display: " .. display_name .. "  Port: " .. (port_name or "missing"), port and palette.active or palette.danger, palette.bg)
  write_at(2, 3, "Mode: " .. mode_label() .. "  Light: " .. state.lighting .. "  Blink: " .. bool_label(state.blink), palette.muted, palette.bg)

  local y = 5
  add_button("standard", 2, y, 11, 3, "STANDARD", state.mode == "standard")
  add_button("sport", 15, y, 9, 3, "SPORT", state.mode == "sport")
  add_button("sport_plus", 26, y, 10, 3, "SPORT+", state.mode == "sport_plus")

  y = y + 4
  add_button("clutch", 2, y, 12, 3, "W CLUTCH", state.clutch, "hold")
  add_button("reverse", 16, y, 12, 3, "S REV", state.reverse, "hold")
  add_button("boost", 30, y, 12, 3, "BOOST", state.workshop_boost, "hold")

  y = y + 4
  add_button("front_drive", 2, y, 13, 3, "G FWD CUT", state.front_drive_off)
  add_button("drive_engine", 17, y, 13, 3, "F ENG CUT", state.drive_engine_off)
  add_button("work_engine", 32, y, 13, 3, "SHOP CUT", state.workshop_engine_off)

  y = y + 4
  add_button("headlights", 2, y, 10, 3, "L LIGHT", state.lighting == "headlights")
  add_button("right", 14, y, 10, 3, "RIGHT", state.lighting == "right")
  add_button("left", 26, y, 10, 3, "LEFT", state.lighting == "left")
  add_button("hazard", 38, y, 10, 3, "X HAZ", state.lighting == "hazard")

  y = y + 4
  write_at(2, y, "Keyboard: W/S hold, G/F/L/Z/X toggle. Z cycles right -> left -> off.", palette.muted, palette.bg)
  write_at(2, y + 1, "Lights, indicators and hazard are mutually exclusive.", palette.muted, palette.bg)
  if not port then
    write_at(2, y + 3, "No redstone port found. Use: set caros.port <name>, then reboot.", palette.danger, palette.bg)
  end
  if state.message ~= "" and y + 4 <= height then write_at(2, y + 4, state.message, palette.warning, palette.bg) end
end

local function perform(action, pressed, from_touch)
  if action == "standard" then set_mode("standard")
  elseif action == "sport" then set_mode("sport")
  elseif action == "sport_plus" then set_mode("sport_plus")
  elseif action == "clutch" then state.clutch = from_touch and not state.clutch or pressed
  elseif action == "reverse" then state.reverse = from_touch and not state.reverse or pressed
  elseif action == "boost" then state.workshop_boost = from_touch and not state.workshop_boost or pressed
  elseif action == "front_drive" then state.front_drive_off = not state.front_drive_off
  elseif action == "drive_engine" then state.drive_engine_off = not state.drive_engine_off
  elseif action == "work_engine" then state.workshop_engine_off = not state.workshop_engine_off
  elseif action == "headlights" then set_lighting("headlights")
  elseif action == "right" then set_lighting("right")
  elseif action == "left" then set_lighting("left")
  elseif action == "hazard" then set_lighting("hazard") end
  apply_outputs()
  draw()
end

local function key_name(code)
  if keys and keys.getName then return keys.getName(code) end
  return tostring(code)
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
  elseif fresh and name == "q" then state.running = false
  end
  apply_outputs()
  draw()
end

local function handle_char(char)
  char = tostring(char or ""):lower()
  if char == "g" then state.front_drive_off = not state.front_drive_off
  elseif char == "f" then state.drive_engine_off = not state.drive_engine_off
  elseif char == "l" then set_lighting("headlights")
  elseif char == "x" then set_lighting("hazard")
  elseif char == "z" then cycle_indicator()
  elseif char == "q" then state.running = false
  else return end
  apply_outputs()
  draw()
end

local function start_timer(name, seconds)
  timers[os.startTimer(seconds)] = name
end

local function setup_display()
  if peripheral and peripheral.find then
    local monitor = peripheral.find("monitor")
    if monitor then
      pcall(monitor.setTextScale, 0.5)
      term.redirect(monitor)
      display_name = "monitor"
    end
  end
end

local function main()
  setup_display()
  all_off()
  apply_outputs()
  draw()
  start_timer("blink", BLINK_INTERVAL)
  while state.running do
    local event, a, b, c = os.pullEvent()
    if event == "timer" and timers[a] == "blink" then
      timers[a] = nil
      state.blink = not state.blink
      apply_outputs()
      draw()
      start_timer("blink", BLINK_INTERVAL)
    elseif event == "key" then
      handle_key(a, true, b == true)
    elseif event == "key_up" then
      handle_key(a, false, false)
    elseif event == "tm_keyboard_key" then
      handle_key(b or a, true, false)
    elseif event == "tm_keyboard_key_up" then
      handle_key(b or a, false, false)
    elseif event == "char" or event == "tm_keyboard_char" then
      if not keys then handle_char(b or a) end
    elseif event == "mouse_click" then
      local button = find_button(b, c)
      if button then
        if button.kind == "hold" then state.held_action = button.id end
        perform(button.id, true, false)
      end
    elseif event == "mouse_up" then
      if state.held_action then
        local action = state.held_action
        state.held_action = nil
        perform(action, false, false)
      end
    elseif event == "monitor_touch" then
      local button = find_button(b, c)
      if button then perform(button.id, true, true) end
    elseif event == "peripheral" or event == "peripheral_detach" then
      port_name, port = find_port()
      state.message = "Peripheral refresh"
      draw()
    end
  end
end

local ok, err = xpcall(main, debug.traceback)
all_off()
if term.current() ~= native_term then term.redirect(native_term) end
set_colors(colors.white, colors.black)
term.clear()
term.setCursorPos(1, 1)
if not ok then
  print("CarOS stopped with error:")
  print(err)
else
  print("CarOS stopped. Outputs are off.")
end
