local paths = require("dock.system.paths")
local tom = require("dock.system.tom_adapter")

local M = {}
local unpacker = table.unpack or unpack
local CELL_W, CELL_H = 6, 9

local function join_words(args, start_index)
  local parts = {}
  for index = start_index or 1, #args do table.insert(parts, tostring(args[index])) end
  return table.concat(parts, " ")
end

local function rgb(red, green, blue)
  red = math.max(0, math.min(255, math.floor(red or 0)))
  green = math.max(0, math.min(255, math.floor(green or 0)))
  blue = math.max(0, math.min(255, math.floor(blue or 0)))
  return red * 65536 + green * 256 + blue
end

local COLORS = {
  black = rgb(0, 0, 0),
  white = rgb(245, 245, 245),
  red = rgb(255, 59, 48),
  yellow = rgb(255, 204, 0),
  green = rgb(52, 199, 89),
  blue = rgb(0, 122, 255),
  gray = rgb(92, 92, 96),
  glass = rgb(18, 18, 20),
}

local function terminal_type()
  if term and term.isColor and term.isColor() then return "Advanced" end
  return "Normal"
end

local function safe_print(line)
  print(tostring(line or ""))
end

local function draw_text(gpu, x, y, text, fg, bg)
  if not gpu or not gpu.drawText then return end
  pcall(gpu.drawText, math.floor(x), math.floor(y), tostring(text or ""), fg or COLORS.white, bg or -1, 1, 0)
end

local function rect(gpu, x, y, width, height, color)
  if not gpu or width <= 0 or height <= 0 then return end
  x, y, width, height = math.floor(x), math.floor(y), math.floor(width), math.floor(height)
  if gpu.filledRectangle and pcall(gpu.filledRectangle, x, y, width, height, color) then return end
  local red = math.floor(color / 65536) % 256
  local green = math.floor(color / 256) % 256
  local blue = color % 256
  if gpu.fillRect and pcall(gpu.fillRect, x, y, width, height, red, green, blue) then return end
end

local function outline(gpu, x, y, width, height, color)
  rect(gpu, x, y, width, 1, color)
  rect(gpu, x, y + height - 1, width, 1, color)
  rect(gpu, x, y, 1, height, color)
  rect(gpu, x + width - 1, y, 1, height, color)
end

local function rounded_outline(gpu, x, y, width, height, color)
  rect(gpu, x + 7, y, width - 14, 1, color)
  rect(gpu, x + 7, y + height - 1, width - 14, 1, color)
  rect(gpu, x, y + 7, 1, height - 14, color)
  rect(gpu, x + width - 1, y + 7, 1, height - 14, color)
  rect(gpu, x + 2, y + 3, 1, 4, color)
  rect(gpu, x + 3, y + 2, 4, 1, color)
  rect(gpu, x + width - 3, y + 3, 1, 4, color)
  rect(gpu, x + width - 7, y + 2, 4, 1, color)
  rect(gpu, x + 2, y + height - 7, 1, 4, color)
  rect(gpu, x + 3, y + height - 3, 4, 1, color)
  rect(gpu, x + width - 3, y + height - 7, 1, 4, color)
  rect(gpu, x + width - 7, y + height - 3, 4, 1, color)
end

local function rounded_fill(gpu, x, y, width, height, color)
  rect(gpu, x + 7, y, width - 14, height, color)
  rect(gpu, x, y + 7, width, height - 14, color)
  rect(gpu, x + 3, y + 3, width - 6, height - 6, color)
end

local function small_round(gpu, x, y, width, height, color)
  rect(gpu, x + 2, y, width - 4, height, color)
  rect(gpu, x, y + 2, width, height - 4, color)
  rect(gpu, x + 1, y + 1, width - 2, height - 2, color)
end

local function glyph_close(gpu, x, y, color)
  rect(gpu, x + 2, y + 2, 1, 1, color); rect(gpu, x + 3, y + 3, 1, 1, color)
  rect(gpu, x + 4, y + 4, 1, 1, color); rect(gpu, x + 5, y + 5, 1, 1, color)
  rect(gpu, x + 5, y + 2, 1, 1, color); rect(gpu, x + 4, y + 3, 1, 1, color)
  rect(gpu, x + 3, y + 4, 1, 1, color); rect(gpu, x + 2, y + 5, 1, 1, color)
end

local function glyph_minus(gpu, x, y, color)
  rect(gpu, x + 2, y + 4, 5, 1, color)
end

local function glyph_full(gpu, x, y, color)
  outline(gpu, x + 2, y + 2, 5, 5, color)
end

local function draw_control_button(gpu, x, y, color, kind)
  small_round(gpu, x, y, 8, 8, color)
  if kind == "close" then glyph_close(gpu, x, y, COLORS.white)
  elseif kind == "min" then glyph_minus(gpu, x, y, COLORS.white)
  elseif kind == "full" then glyph_full(gpu, x, y, COLORS.white) end
end

local function write_buffer_chunk(buffer, chunk)
  if type(chunk) == "number" then chunk = string.char(chunk) end
  if type(chunk) ~= "string" then return false, "invalid chunk" end
  local offset = 1
  while offset <= #chunk do
    local last = math.min(#chunk, offset + 511)
    local ok, err = pcall(function() buffer.write(chunk:byte(offset, last)) end)
    if not ok then return false, err end
    offset = last + 1
  end
  return true
end

local function image_from_file(gpu, path, cache)
  if not gpu or not gpu.newBuffer or not gpu.decodeImage or not gpu.drawImage or not fs.exists(path) or fs.isDir(path) then return nil end
  local key = path .. ":" .. tostring(fs.getSize(path) or 0)
  if cache[key] then return cache[key] end
  local ok_buffer, buffer = pcall(gpu.newBuffer, math.max(32, fs.getSize(path) or 32))
  if not ok_buffer or not buffer then return nil end
  local handle = fs.open(path, "rb") or fs.open(path, "r")
  if not handle then pcall(buffer.free); return nil end
  while true do
    local ok_read, chunk = pcall(handle.read, 4096)
    if not ok_read then break end
    if chunk == nil then break end
    local wrote = write_buffer_chunk(buffer, chunk)
    if not wrote then break end
  end
  handle.close()
  local ok_image, image = pcall(function() return gpu.decodeImage(buffer.ref()) end)
  pcall(buffer.free)
  if ok_image and image then cache[key] = image; return image end
  return nil
end

local function pixel_event(event, a, b, c, d)
  if event == "mouse_click" or event == "mouse_drag" or event == "mouse_up" then
    return event, a or 1, ((b or 1) - 1) * CELL_W + 1, ((c or 1) - 1) * CELL_H + 1
  end
  if event == "tm_monitor_mouse_click" or event == "tm_monitor_mouse_drag" or event == "tm_monitor_mouse_up" or event == "tm_monitor_touch" then
    local px, py, button
    if type(a) == "number" and type(b) == "number" then
      px, py, button = a, b, c or 1
    else
      px, py, button = b or 1, c or 1, d or 1
    end
    local mapped = event == "tm_monitor_mouse_drag" and "mouse_drag" or (event == "tm_monitor_mouse_up" and "mouse_up" or "mouse_click")
    return mapped, button or 1, px, py
  end
  return event, a, b, c
end

local function hit_at(state, x, y)
  for index = #state.hits, 1, -1 do
    local hit = state.hits[index]
    if x >= hit.x and x <= hit.x + hit.w - 1 and y >= hit.y and y <= hit.y + hit.h - 1 then return hit end
  end
  return nil
end

local function block_size(width, height)
  local known = {
    { label = "1x2", width = 128, height = 64 },
    { label = "2x3", width = 256, height = 96 },
    { label = "2x4", width = 256, height = 128 },
    { label = "3x6", width = 384, height = 192 },
    { label = "4x8", width = 512, height = 256 },
  }
  for _, size in ipairs(known) do
    if math.abs(width - size.width) <= 6 and math.abs(height - size.height) <= 6 then
      return size.label
    end
  end
  local blocks_w = math.max(1, math.floor((width / 128) + 0.5))
  local blocks_h = math.max(1, math.floor((height / 32) + 0.5))
  return tostring(blocks_w) .. "x" .. tostring(blocks_h)
end

function M.new(ctx)
  local service = { ctx = ctx }

  function service.printHelp()
    safe_print("dock about | version | services | ps | devices | apps")
    safe_print("dock time | timezone <offset> | windows")
    safe_print("dock ipc send <pid> <type> <text> | ipc inbox <pid>")
    safe_print("dock run <app_id> | files | ls <path> | open <path>")
    safe_print("dock mkdir <path> | touch <path> | write <path> <text> | cat <path> | rm <path>")
    safe_print("dock trash <path> | restore <trash_id> | search <query>")
    safe_print("dock install-local <path> | uninstall <app_id>")
    safe_print("dock settings get <key> | settings set <key> <value>")
    safe_print("dock test | reboot | shutdown")
  end

  local function print_result(result)
    if not result or result.ok then return result end
    safe_print(result.error or "Command failed")
    return result
  end

  function service.runCommand(args)
    local command = args[1] or "help"
    if command == "about" then
      safe_print(ctx.version.name .. " " .. ctx.version.codename .. " " .. ctx.version.version)
      safe_print("Channel: " .. ctx.version.channel)
      safe_print("Previous: " .. ctx.version.previous_codename)
    elseif command == "version" then
      safe_print(ctx.version.codename .. " " .. ctx.version.version)
    elseif command == "help" then
      service.printHelp()
    elseif command == "services" then
      for _, item in ipairs(ctx.service_manager.list().data) do safe_print(item.id .. " " .. item.status) end
    elseif command == "time" then
      safe_print(ctx.time_service.clockText() .. " " .. ctx.time_service.timezoneText())
    elseif command == "timezone" then
      if args[2] then ctx.time_service.setTimezone(args[2]) end
      safe_print(ctx.time_service.timezoneText())
    elseif command == "windows" then
      for _, window in ipairs(ctx.window_service.list().data) do
        safe_print(window.id .. " " .. window.app_id .. " " .. (window.minimized and "minimized" or "visible"))
      end
    elseif command == "ipc" and args[2] == "send" then
      return print_result(ctx.ipc_service.send("shell", tonumber(args[3]), args[4] or "message", { text = join_words(args, 5) }))
    elseif command == "ipc" and args[2] == "inbox" then
      local result = ctx.ipc_service.peek(tonumber(args[3]))
      for _, item in ipairs(result.data or {}) do safe_print(tostring(item.id) .. " " .. tostring(item.kind)) end
      return result
    elseif command == "ps" then
      for _, item in ipairs(ctx.process_manager.list().data) do safe_print(tostring(item.pid) .. " " .. item.status .. " " .. item.name) end
    elseif command == "devices" then
      ctx.device_service.scan()
      for key, value in pairs(ctx.device_service.getCapabilities().data) do safe_print(key .. "=" .. tostring(value)) end
      for _, device in ipairs(ctx.device_service.listPeripherals().data) do safe_print(device.name .. " " .. tostring(device.type)) end
    elseif command == "apps" then
      for _, app in ipairs(ctx.app_service.scanApps().data) do safe_print(app.manifest.id .. " " .. app.manifest.name) end
    elseif command == "app" then
      local app = ctx.app_service.getApp(args[2])
      if not app.ok then return print_result(app) end
      for key, value in pairs(app.data.manifest) do if type(value) ~= "table" then safe_print(key .. ": " .. tostring(value)) end end
    elseif command == "run" then
      return print_result(ctx.app_service.launch(args[2], { select(3, unpacker(args)) }))
    elseif command == "files" then
      for _, folder in ipairs(ctx.fs_service.getUserFolders().data) do safe_print(folder.category .. " " .. folder.path) end
    elseif command == "ls" then
      local result = ctx.fs_service.listDirectory(args[2] or ctx.user_service.getHome())
      if not result.ok then return print_result(result) end
      for _, item in ipairs(result.data) do safe_print((item.dir and "[D] " or "[F] ") .. item.name) end
    elseif command == "mkdir" then
      return print_result(ctx.fs_service.createDirectory(args[2]))
    elseif command == "touch" then
      return print_result(ctx.fs_service.createFile(args[2], ""))
    elseif command == "cat" then
      local result = ctx.fs_service.readFile(args[2])
      if result.ok then safe_print(result.data) end
      return print_result(result)
    elseif command == "write" then
      return print_result(ctx.fs_service.writeFile(args[2], join_words(args, 3)))
    elseif command == "rm" then
      return print_result(ctx.fs_service.delete(args[2]))
    elseif command == "trash" then
      local result = ctx.fs_service.moveToTrash(args[2])
      if result.ok then safe_print(result.data.id) end
      return print_result(result)
    elseif command == "restore" then
      return print_result(ctx.fs_service.restoreFromTrash(args[2]))
    elseif command == "search" then
      local result = ctx.fs_service.searchByName(args[2] or "")
      for _, path in ipairs(result.data or {}) do safe_print(path) end
    elseif command == "open" then
      return print_result(ctx.fs_service.openFile(args[2]))
    elseif command == "install-local" then
      return print_result(ctx.package_service.installLocal(args[2]))
    elseif command == "uninstall" then
      return print_result(ctx.package_service.uninstall(args[2]))
    elseif command == "settings" and args[2] == "get" then
      safe_print(tostring(ctx.settings_service.get(args[3], "").data))
    elseif command == "settings" and args[2] == "set" then
      return print_result(ctx.settings_service.set(args[3], join_words(args, 4)))
    elseif command == "test" then
      local test = dofile(paths.join(paths.tests, "selftest.lua"))
      return test.run(ctx)
    elseif command == "reboot" then
      os.reboot()
    elseif command == "shutdown" then
      os.shutdown()
    else
      service.printHelp()
    end
    return { ok = true }
  end

  local function initial_ui_state(gpu, width, height)
    local apps = ctx.app_service.listAppsForDesktop().data or {}
    local pinned_setting = ctx.settings_service.get("user.dock.pinned", nil).data
    local pinned = {}
    if type(pinned_setting) == "table" then pinned = pinned_setting else
      for _, app in ipairs(apps) do table.insert(pinned, app.manifest.id) end
      ctx.settings_service.set("user.dock.pinned", pinned)
    end
    ctx.window_service.restore(width, height)
    return {
      gpu = gpu,
      width = width,
      height = height,
      hits = {},
      image_cache = {},
      pinned = pinned,
      windows = ctx.window_service.list().data,
      active = ctx.window_service.activeId().data,
      menu = false,
      context = nil,
      about = false,
      selecting = nil,
      dragging_dock = nil,
      dragging_window = nil,
      dock_metrics = nil,
    }
  end

  local function save_pinned(ui)
    ctx.settings_service.set("user.dock.pinned", ui.pinned)
  end

  local function is_pinned(ui, app_id)
    for _, id in ipairs(ui.pinned) do if id == app_id then return true end end
    return false
  end

  local function set_pinned(ui, app_id, should_pin)
    local already = is_pinned(ui, app_id)
    if should_pin and not already then
      table.insert(ui.pinned, app_id)
      save_pinned(ui)
    elseif (not should_pin) and already then
      local next_pinned = {}
      for _, id in ipairs(ui.pinned) do if id ~= app_id then table.insert(next_pinned, id) end end
      ui.pinned = next_pinned
      save_pinned(ui)
    end
  end

  local function add_hit(ui, id, x, y, w, h, payload)
    table.insert(ui.hits, { id = id, x = x, y = y, w = w, h = h, payload = payload })
  end

  local function sync_windows(ui)
    ui.windows = ctx.window_service.list().data
    ui.active = ctx.window_service.activeId().data
  end

  local function draw_wallpaper(ui)
    local exact_path = paths.join(paths.assets, "wallpaper-" .. tostring(ui.width) .. "x" .. tostring(ui.height) .. ".png")
    local image = image_from_file(ui.gpu, exact_path, ui.image_cache)
    if not image then image = image_from_file(ui.gpu, paths.join(paths.assets, "wallpaper-384x192.png"), ui.image_cache) end
    if image and ui.gpu.drawImage then
      local iw = image.getWidth and image.getWidth() or ui.width
      local ih = image.getHeight and image.getHeight() or ui.height
      if iw <= ui.width and ih <= ui.height then
        local x = math.floor((ui.width - iw) / 2) + 1
        local y = math.floor((ui.height - ih) / 2) + 1
        pcall(ui.gpu.drawImage, x, y, image.ref())
      else
        rect(ui.gpu, 1, 1, ui.width, ui.height, rgb(28, 60, 72))
      end
    elseif ui.gpu.fill then
      pcall(ui.gpu.fill, rgb(28, 60, 72))
    else
      rect(ui.gpu, 1, 1, ui.width, ui.height, rgb(28, 60, 72))
    end
  end

  local function draw_top(ui)
    rect(ui.gpu, 1, 1, 6, 6, COLORS.black)
    add_hit(ui, "system_menu", 1, 1, 12, 12)
    local x = 13
    local menu = { "About", "File", "Edit", "View", "Window" }
    for _, label in ipairs(menu) do
      draw_text(ui.gpu, x, 3, label, COLORS.white, -1)
      x = x + (#label * 6) + 10
    end
    local clock = ctx.time_service and ctx.time_service.clockText() or ""
    draw_text(ui.gpu, ui.width - (#clock * 6) - 5, 3, clock, COLORS.white, -1)
  end

  local function open_window(ui, app_id)
    ctx.window_service.open(app_id, { x = 42, y = 24, w = math.min(220, ui.width - 70), h = math.min(120, ui.height - 58) })
    sync_windows(ui)
  end

  local function active_app_id(ui)
    for _, window in ipairs(ui.windows) do if window.id == ui.active and not window.minimized then return window.app_id end end
    return nil
  end

  local function dock_apps(ui)
    local pinned = {}
    for _, id in ipairs(ui.pinned) do local app = ctx.app_service.getApp(id); if app.ok then table.insert(pinned, app.data) end end
    local opened = {}
    for _, window in ipairs(ui.windows) do if not is_pinned(ui, window.app_id) then table.insert(opened, window.app) end end
    return pinned, opened
  end

  local function draw_icon_square(ui, x, y, app, active)
    small_round(ui.gpu, x, y, 16, 16, active and COLORS.blue or COLORS.red)
    local icon = app.manifest.icon
    if icon == "folder" then
      rect(ui.gpu, x + 3, y + 6, 10, 6, COLORS.white)
      rect(ui.gpu, x + 4, y + 4, 5, 2, COLORS.white)
    elseif icon == "terminal" then
      draw_text(ui.gpu, x + 3, y + 4, ">", COLORS.white, -1)
      rect(ui.gpu, x + 9, y + 11, 4, 1, COLORS.white)
    elseif icon == "settings" then
      outline(ui.gpu, x + 5, y + 5, 6, 6, COLORS.white)
      rect(ui.gpu, x + 7, y + 7, 2, 2, COLORS.white)
    else
      rect(ui.gpu, x + 5, y + 5, 6, 6, COLORS.white)
    end
    add_hit(ui, "dock_app", x - 2, y - 2, 20, 20, app.manifest.id)
  end

  local function draw_dock_glass(ui, x, y, width, height)
    local image = image_from_file(ui.gpu, paths.join(paths.assets, "dock-glass-" .. tostring(ui.width) .. "x" .. tostring(ui.height) .. ".png"), ui.image_cache)
    if image and ui.gpu.drawImage then
      pcall(ui.gpu.drawImage, x, y, image.ref())
    else
      rounded_fill(ui.gpu, x, y, width, height, rgb(228, 236, 244))
    end
    rounded_outline(ui.gpu, x, y, width, height, COLORS.white)
  end

  local function draw_dock(ui)
    local dock_w, dock_h = ui.width - 10, 24
    local dock_x, dock_y = 5, ui.height - dock_h - 4
    draw_dock_glass(ui, dock_x, dock_y, dock_w, dock_h)
    local x = dock_x + 9
    local y = dock_y + 4
    local pinned, opened = dock_apps(ui)
    local active = active_app_id(ui) or (pinned[1] and pinned[1].manifest.id)
    for _, app in ipairs(pinned) do
      draw_icon_square(ui, x, y, app, active == app.manifest.id)
      x = x + 20
    end
    ui.dock_metrics = { x = dock_x, y = dock_y, w = dock_w, h = dock_h, divider_x = x + 1 }
    rect(ui.gpu, x + 1, dock_y + 5, 1, dock_h - 10, COLORS.white)
    add_hit(ui, "dock_divider", x - 4, dock_y, 9, dock_h)
    x = x + 11
    for _, app in ipairs(opened) do
      draw_icon_square(ui, x, y, app, active == app.manifest.id)
      x = x + 20
    end
    draw_text(ui.gpu, math.max(dock_x + 10, ui.width - 86), dock_y + 8, "DockOS 0.0.1", COLORS.white, -1)
  end

  local function draw_menu(ui)
    if not ui.menu then return end
    outline(ui.gpu, 2, 10, 92, 44, COLORS.white)
    draw_text(ui.gpu, 8, 16, "About DockOS", COLORS.white, -1)
    draw_text(ui.gpu, 8, 28, "Reboot", COLORS.white, -1)
    draw_text(ui.gpu, 8, 40, "Shutdown", COLORS.white, -1)
    add_hit(ui, "about", 4, 12, 88, 12)
    add_hit(ui, "reboot", 4, 24, 88, 12)
    add_hit(ui, "shutdown", 4, 36, 88, 12)
  end

  local function draw_about(ui)
    if not ui.about then return end
    local w, h = 230, 72
    local x, y = math.floor((ui.width - w) / 2), math.floor((ui.height - h) / 2)
    outline(ui.gpu, x, y, w, h, COLORS.white)
    draw_text(ui.gpu, x + 10, y + 10, "DockOS", COLORS.white, -1)
    draw_text(ui.gpu, x + 10, y + 24, "Type: " .. terminal_type(), COLORS.white, -1)
    draw_text(ui.gpu, x + 10, y + 36, "Monitor Size: " .. block_size(ui.width, ui.height) .. " (" .. ui.width .. "x" .. ui.height .. ")", COLORS.white, -1)
    draw_text(ui.gpu, x + 10, y + 48, "DockOS Version: Paralimni 0.0.1", COLORS.white, -1)
    add_hit(ui, "about_close", x, y, w, h)
  end

  local function draw_context(ui)
    if not ui.context then return end
    local text = is_pinned(ui, ui.context.app_id) and "Remove from Dock" or "Keep in Dock"
    outline(ui.gpu, ui.context.x, ui.context.y, 104, 20, COLORS.white)
    draw_text(ui.gpu, ui.context.x + 6, ui.context.y + 7, text, COLORS.white, -1)
    add_hit(ui, "dock_keep", ui.context.x, ui.context.y, 104, 20, ui.context.app_id)
  end

  local function draw_selection(ui)
    if not ui.selecting then return end
    local x1, y1 = ui.selecting.x1, ui.selecting.y1
    local x2, y2 = ui.selecting.x2 or x1, ui.selecting.y2 or y1
    local x, y = math.min(x1, x2), math.min(y1, y2)
    local w, h = math.abs(x2 - x1) + 1, math.abs(y2 - y1) + 1
    outline(ui.gpu, x, y, w, h, COLORS.white)
  end

  local function draw_window(ui, window)
    if window.minimized then return end
    local x, y, w, h = window.x, window.y, window.w, window.h
    if window.fullscreen then x, y, w, h = 1, 12, ui.width, ui.height - 44 end
    rect(ui.gpu, x, y, w, h, rgb(20, 24, 28))
    outline(ui.gpu, x, y, w, h, COLORS.white)
    add_hit(ui, "window_body", x, y, w, h, window.id)
    add_hit(ui, "window_drag", x, y, w, 18, window.id)
    draw_control_button(ui.gpu, x + 5, y + 5, COLORS.red, "close")
    draw_control_button(ui.gpu, x + 16, y + 5, COLORS.yellow, "min")
    draw_control_button(ui.gpu, x + 27, y + 5, COLORS.green, "full")
    add_hit(ui, "window_close", x + 4, y + 4, 10, 10, window.id)
    add_hit(ui, "window_min", x + 14, y + 4, 10, 10, window.id)
    add_hit(ui, "window_full", x + 24, y + 4, 10, 10, window.id)
    local app_id = window.app_id
    local content_x, content_y = x + 10, y + 22
    if app_id == "dock.files" then
      draw_text(ui.gpu, content_x, content_y, "Files", COLORS.white, -1)
      local rows = ctx.fs_service.getUserFolders().data or {}
      local row_y = content_y + 14
      for _, folder in ipairs(rows) do
        draw_text(ui.gpu, content_x, row_y, folder.category, COLORS.white, -1)
        row_y = row_y + 11
        if row_y > y + h - 8 then break end
      end
    elseif app_id == "dock.settings" then
      draw_text(ui.gpu, content_x, content_y, "DockOS Paralimni 0.0.1", COLORS.white, -1)
      draw_text(ui.gpu, content_x, content_y + 14, "User: " .. ctx.user_service.getCurrentUser().name, COLORS.white, -1)
      draw_text(ui.gpu, content_x, content_y + 28, "Type: " .. terminal_type(), COLORS.white, -1)
    elseif app_id == "dock.terminal" then
      draw_text(ui.gpu, content_x, content_y, "Terminal", COLORS.white, -1)
      draw_text(ui.gpu, content_x, content_y + 14, "Use dock commands from CraftOS.", COLORS.white, -1)
    else
      draw_text(ui.gpu, content_x, content_y, window.app.manifest.name, COLORS.white, -1)
    end
  end

  local function render(ui)
    ui.hits = {}
    draw_wallpaper(ui)
    draw_top(ui)
    for _, window in ipairs(ui.windows) do draw_window(ui, window) end
    draw_selection(ui)
    draw_dock(ui)
    draw_menu(ui)
    draw_context(ui)
    draw_about(ui)
    if ui.gpu.sync then pcall(ui.gpu.sync) end
  end

  local function pin_app(ui, app_id)
    set_pinned(ui, app_id, not is_pinned(ui, app_id))
  end

  local function focus_window(ui, id)
    local focused = ctx.window_service.focus(id)
    sync_windows(ui)
    return focused.ok and focused.data or nil
  end

  local function close_window(ui, id)
    ctx.window_service.close(id)
    sync_windows(ui)
  end

  local function handle_action(ui, hit, button, x, y)
    if not hit then
      ui.menu, ui.context = false, nil
      if button == 1 then ui.selecting = { x1 = x, y1 = y, x2 = x, y2 = y } end
      return
    end
    if hit.id == "system_menu" then ui.menu = not ui.menu; ui.context = nil
    elseif hit.id == "about" then ui.about = true; ui.menu = false
    elseif hit.id == "about_close" then ui.about = false
    elseif hit.id == "reboot" then os.reboot()
    elseif hit.id == "shutdown" then os.shutdown()
    elseif hit.id == "dock_app" then
      if button == 2 then
        ui.context = { app_id = hit.payload, x = math.max(2, math.min(ui.width - 106, x)), y = math.max(10, math.min(ui.height - 50, y - 24)) }
      else
        open_window(ui, hit.payload)
        ui.dragging_dock = { app_id = hit.payload }
      end
    elseif hit.id == "dock_keep" then pin_app(ui, hit.payload); ui.context = nil
    elseif hit.id == "window_close" then close_window(ui, hit.payload)
    elseif hit.id == "window_min" then ctx.window_service.minimize(hit.payload, true); sync_windows(ui)
    elseif hit.id == "window_full" then ctx.window_service.toggleFullscreen(hit.payload); sync_windows(ui)
    elseif hit.id == "window_body" then focus_window(ui, hit.payload)
    elseif hit.id == "window_drag" then
      local window = focus_window(ui, hit.payload)
      if window and not window.fullscreen then
        ui.dragging_window = { id = window.id, dx = x - window.x, dy = y - window.y }
      end
    end
  end

  local function run_graphical(gpu, width, height)
    local ui = initial_ui_state(gpu, width, height)
    while true do
      render(ui)
      local event, a, b, c, d = os.pullEvent()
      if ctx.process_manager and ctx.process_manager.dispatch then ctx.process_manager.dispatch(event, a, b, c, d) end
      if event == "rednet_message" then ctx.net_service.handleMessage(a, b, c)
      elseif event == "key" and a == keys.q then return { ok = true }
      else
        local mapped, button, x, y = pixel_event(event, a, b, c, d)
        if mapped == "mouse_click" then
          ui.selecting = nil
          handle_action(ui, hit_at(ui, x, y), button, x, y)
        elseif mapped == "mouse_drag" then
          if ui.dragging_window then
            for _, window in ipairs(ui.windows) do
              if window.id == ui.dragging_window.id then
                window.x = math.max(1, math.min(ui.width - window.w + 1, x - ui.dragging_window.dx))
                window.y = math.max(8, math.min(ui.height - window.h - 26, y - ui.dragging_window.dy))
              end
            end
          elseif ui.selecting then
            ui.selecting.x2, ui.selecting.y2 = x, y
          end
        elseif mapped == "mouse_up" then
          if ui.dragging_dock and ui.dock_metrics then
            local dock = ui.dock_metrics
            local inside_dock = x >= dock.x and x <= dock.x + dock.w - 1 and y >= dock.y and y <= dock.y + dock.h - 1
            if inside_dock and x < dock.divider_x then
              set_pinned(ui, ui.dragging_dock.app_id, true)
            elseif inside_dock and x > dock.divider_x + 6 then
              set_pinned(ui, ui.dragging_dock.app_id, false)
            end
          end
          ui.dragging_dock = nil
          if ui.dragging_window then ctx.window_service.save() end
          ui.dragging_window = nil
          ui.selecting = nil
        elseif mapped == "peripheral" or mapped == "peripheral_detach" then
          ctx.device_service.scan()
        end
      end
    end
  end

  local function run_terminal_fallback()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    print("DockOS Paralimni 0.0.1")
    print("No bitmap GPU detected. Use dock help for commands.")
    service.printHelp()
    return { ok = true }
  end

  function service.runDesktop()
    ctx.app_service.scanApps()
    ctx.device_service.scan()
    local _, gpu = tom.findGPU()
    if gpu then
      if gpu.refreshSize then pcall(gpu.refreshSize) end
      if gpu.setSize then pcall(gpu.setSize, 64) end
      sleep(0)
      local width, height = 384, 192
      if gpu.getSize then
        local ok, w, h = pcall(gpu.getSize)
        if ok and type(w) == "number" and type(h) == "number" then width, height = w, h end
      end
      return run_graphical(gpu, width, height)
    end
    return run_terminal_fallback()
  end

  return service
end

return M
