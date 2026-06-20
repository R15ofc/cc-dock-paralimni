local paths = require("dock.system.paths")
local tom = require("dock.system.tom_adapter")
local loading = require("dock.system.loading")
local scrollbar = require("dock.system.scrollbar")

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
  if event == "mouse_scroll" then
    return event, a or 0, ((b or 1) - 1) * CELL_W + 1, ((c or 1) - 1) * CELL_H + 1
  end
  if event == "tm_monitor_mouse_scroll" then
    if type(a) == "string" then return "mouse_scroll", b or 0, c or 1, d or 1 end
    return "mouse_scroll", a or 0, b or 1, c or 1
  end
  if event == "mouse_click" or event == "mouse_drag" or event == "mouse_up" then
    return event, a or 1, ((b or 1) - 1) * CELL_W + 1, ((c or 1) - 1) * CELL_H + 1
  end
  if event == "tm_monitor_mouse_click" or event == "tm_monitor_mouse_drag" or event == "tm_monitor_mouse_up" or event == "tm_monitor_touch" or event == "tm_monitor_mouse_move" then
    local px, py, button
    if type(a) == "number" and type(b) == "number" then
      px, py, button = a, b, c or 1
    else
      px, py, button = b or 1, c or 1, d or 1
    end
    local mapped = event == "tm_monitor_mouse_drag" and "mouse_drag" or (event == "tm_monitor_mouse_up" and "mouse_up" or (event == "tm_monitor_mouse_move" and "mouse_move" or "mouse_click"))
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

local function ellipsize(text, max_chars)
  text = tostring(text or "")
  max_chars = math.max(1, tonumber(max_chars) or #text)
  if #text <= max_chars then return text end
  if max_chars <= 3 then return text:sub(1, max_chars) end
  return text:sub(1, max_chars - 3) .. "..."
end

local function format_size(size)
  size = tonumber(size) or 0
  if size >= 1024 then return tostring(math.floor(size / 1024)) .. "K" end
  return tostring(size) .. "B"
end

local function draw_file_icon(gpu, x, y, is_folder, selected)
  local color = selected and COLORS.blue or COLORS.white
  if is_folder then
    rect(gpu, x, y + 4, 11, 7, color)
    rect(gpu, x + 1, y + 2, 5, 2, color)
  else
    outline(gpu, x + 2, y + 1, 8, 11, color)
    rect(gpu, x + 7, y + 2, 2, 2, color)
  end
end

function M.new(ctx)
  local service = { ctx = ctx }

  function service.printHelp()
    safe_print("dock about | version | services | ps | devices | apps")
    safe_print("dock time | timezone <offset> | windows")
    safe_print("dock runtime | stop <instance_or_pid>")
    safe_print("dock permissions <app_id> | grant <app_id> <permission> | revoke <app_id> <permission>")
    safe_print("dock ipc send <pid> <type> <text> | ipc inbox <pid>")
    safe_print("dock explorer [go|back|up|search|select|rename|new-folder|new-file|copy|cut|paste|trash]")
    safe_print("dock update [check|status|install]")
    safe_print("dock studio [new|save|export|add <text|button|input|shape|image>]")
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
    elseif command == "runtime" then
      for _, instance in ipairs(ctx.app_runtime_service.list().data) do
        safe_print(tostring(instance.id) .. " pid=" .. tostring(instance.pid) .. " " .. instance.state .. " " .. instance.app_id)
      end
    elseif command == "stop" then
      return print_result(ctx.app_runtime_service.stop(args[2]))
    elseif command == "permissions" then
      local result = ctx.permission_service.list(args[2])
      if args[2] then
        safe_print("requested: " .. table.concat(result.data.requested or {}, ","))
        safe_print("granted: " .. table.concat(result.data.granted or {}, ","))
        safe_print("denied: " .. table.concat(result.data.denied or {}, ","))
      else
        for app_id, record in pairs(result.data or {}) do
          safe_print(app_id .. " granted=" .. tostring(#(record.granted or {})) .. " requested=" .. tostring(#(record.requested or {})))
        end
      end
      return result
    elseif command == "grant" then
      return print_result(ctx.permission_service.grant(args[2], args[3]))
    elseif command == "revoke" then
      return print_result(ctx.permission_service.revoke(args[2], args[3]))
    elseif command == "ipc" and args[2] == "send" then
      return print_result(ctx.ipc_service.send("shell", tonumber(args[3]), args[4] or "message", { text = join_words(args, 5) }))
    elseif command == "ipc" and args[2] == "inbox" then
      local result = ctx.ipc_service.peek(tonumber(args[3]))
      for _, item in ipairs(result.data or {}) do safe_print(tostring(item.id) .. " " .. tostring(item.kind)) end
      return result
    elseif command == "explorer" then
      local action = args[2] or "list"
      local id = "shell"
      local result
      if action == "go" then result = ctx.explorer_service.navigate(id, join_words(args, 3))
      elseif action == "back" then result = ctx.explorer_service.back(id)
      elseif action == "forward" then result = ctx.explorer_service.forward(id)
      elseif action == "up" then result = ctx.explorer_service.up(id)
      elseif action == "search" then result = ctx.explorer_service.setSearch(id, join_words(args, 3))
      elseif action == "select" then result = ctx.explorer_service.select(id, join_words(args, 3))
      elseif action == "rename" then result = ctx.explorer_service.renameSelected(id, join_words(args, 3))
      elseif action == "new-folder" then result = ctx.explorer_service.createFolder(id, join_words(args, 3) ~= "" and join_words(args, 3) or nil)
      elseif action == "new-file" then result = ctx.explorer_service.createFile(id, join_words(args, 3) ~= "" and join_words(args, 3) or nil)
      elseif action == "copy" then result = ctx.explorer_service.copySelected(id)
      elseif action == "cut" then result = ctx.explorer_service.cutSelected(id)
      elseif action == "paste" then result = ctx.explorer_service.paste(id)
      elseif action == "trash" then result = ctx.explorer_service.trashSelected(id)
      else result = ctx.explorer_service.list(id) end
      if not result.ok then return print_result(result) end
      local listed = ctx.explorer_service.list(id)
      safe_print("Explorer: " .. listed.data.state.path)
      for _, row in ipairs(listed.data.rows or {}) do safe_print((row.dir and "[D] " or "[F] ") .. row.name) end
      return result
    elseif command == "update" then
      local action = args[2] or "status"
      local result
      if action == "check" then result = ctx.update_service.beginCheck(); result = ctx.update_service.checkNow()
      elseif action == "install" then result = ctx.update_service.installAvailable()
      else result = ctx.update_service.status() end
      if not result.ok then return print_result(result) end
      safe_print("Update: " .. tostring(result.data.status))
      if result.data.available then safe_print(result.data.available.title) end
      return result
    elseif command == "studio" then
      local action = args[2] or "current"
      local result
      if action == "new" then result = ctx.studio_service.newProject(join_words(args, 3))
      elseif action == "save" then result = ctx.studio_service.save()
      elseif action == "export" then result = ctx.studio_service.exportApp()
      elseif action == "add" then result = ctx.studio_service.addComponent(args[3] or "text")
      else result = ctx.studio_service.current() end
      if not result.ok then return print_result(result) end
      safe_print("Studio: " .. tostring((ctx.studio_service.current().data or {}).name))
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
      text_input = nil,
      dragging_text = nil,
      modifiers = { ctrl = false, shift = false },
      cursor = { x = math.floor(width / 2), y = math.floor(height / 2), kind = "default" },
      settings = { route = "general", history = {}, future = {} },
      frame = 0,
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

  local active_window, active_app_id

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
    local x = 5
    local app_id = active_app_id(ui)
    local menu = ctx.menu_service.menuFor(app_id).data or {}
    table.insert(menu, 1, { id = "system", label = "About" })
    for _, item in ipairs(menu) do
      local label = item.label
      local width = (#label * 6) + 8
      draw_text(ui.gpu, x, 3, label, item.enabled == false and COLORS.gray or COLORS.white, -1)
      add_hit(ui, "top_menu", x - 3, 1, width, 12, { app_id = app_id, action = item.id })
      x = x + width + 2
      if x > ui.width - 72 then break end
    end
    local clock = ctx.time_service and ctx.time_service.clockText() or ""
    draw_text(ui.gpu, ui.width - (#clock * 6) - 5, 3, clock, COLORS.white, -1)
  end

  local function open_window(ui, app_id)
    local geometry = { x = 42, y = 24, w = math.min(220, ui.width - 70), h = math.min(120, ui.height - 58) }
    if app_id == "dock.files" then
      geometry = { x = 24, y = 20, w = math.min(330, ui.width - 38), h = math.min(138, ui.height - 58) }
    elseif app_id == "dock.settings" then
      geometry = { x = 32, y = 20, w = math.min(290, ui.width - 54), h = math.min(136, ui.height - 58) }
    elseif app_id == "dock.studio" then
      geometry = { x = 22, y = 18, w = math.min(340, ui.width - 36), h = math.min(142, ui.height - 56) }
    end
    ctx.window_service.open(app_id, geometry)
    sync_windows(ui)
  end

  function active_window(ui)
    for _, window in ipairs(ui.windows) do if window.id == ui.active and not window.minimized then return window end end
    return nil
  end

  function active_app_id(ui)
    local window = active_window(ui)
    return window and window.app_id or nil
  end

  local function current_settings(ui)
    ui.settings = ui.settings or { route = "general", history = {}, future = {}, scroll = {} }
    ui.settings.route = ui.settings.route or "general"
    ui.settings.history = ui.settings.history or {}
    ui.settings.future = ui.settings.future or {}
    ui.settings.scroll = ui.settings.scroll or {}
    return ui.settings
  end

  local function settings_go(ui, route)
    local settings = current_settings(ui)
    route = tostring(route or "general")
    if settings.route == route then return end
    table.insert(settings.history, settings.route)
    settings.route = route
    settings.future = {}
  end

  local function settings_back(ui)
    local settings = current_settings(ui)
    local previous = table.remove(settings.history)
    if not previous then return end
    table.insert(settings.future, settings.route)
    settings.route = previous
  end

  local function settings_forward(ui)
    local settings = current_settings(ui)
    local next_route = table.remove(settings.future)
    if not next_route then return end
    table.insert(settings.history, settings.route)
    settings.route = next_route
  end

  local function settings_scroll(ui, delta)
    local settings = current_settings(ui)
    local route = settings.route
    settings.scroll[route] = math.max(0, (tonumber(settings.scroll[route]) or 0) + (tonumber(delta) or 0))
  end

  local function settings_title(route)
    local labels = {
      general = "General",
      software_update = "Software Update",
      accessibility = "Accessibility",
      appearance = "Appearance",
      about = "About",
      storage = "Storage",
    }
    return labels[route] or "Settings"
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
    elseif icon == "studio" then
      rect(ui.gpu, x + 4, y + 4, 8, 2, COLORS.white)
      rect(ui.gpu, x + 4, y + 7, 8, 1, COLORS.white)
      rect(ui.gpu, x + 4, y + 10, 6, 1, COLORS.white)
      rect(ui.gpu, x + 12, y + 10, 2, 3, COLORS.white)
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
    draw_text(ui.gpu, math.max(dock_x + 10, ui.width - 86), dock_y + 8, "DockOS " .. ctx.version.version, COLORS.white, -1)
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
    draw_text(ui.gpu, x + 10, y + 24, "Edition: " .. tostring(ctx.version.edition or "Basic"), COLORS.white, -1)
    draw_text(ui.gpu, x + 10, y + 36, "Monitor Size: " .. block_size(ui.width, ui.height) .. " (" .. ui.width .. "x" .. ui.height .. ")", COLORS.white, -1)
    draw_text(ui.gpu, x + 10, y + 48, "DockOS: " .. ctx.version.codename .. " " .. ctx.version.version, COLORS.white, -1)
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

  local function input_id(kind, window_id)
    return tostring(kind) .. ":" .. tostring(window_id or "main")
  end

  local function focused_input(ui, kind, window_id)
    return ui.text_input and ui.text_input.kind == kind and ui.text_input.window_id == window_id
  end

  local function input_view(id, fallback)
    local current = ctx.text_input_service.view(id).data
    if not current or current.value == nil then return { value = fallback or "", cursor = #(fallback or "") } end
    return current
  end

  local function sync_text_input(ui)
    if not ui.text_input then return end
    local view = ctx.text_input_service.view(ui.text_input.input_id).data
    if not view then return end
    if ui.text_input.kind == "explorer_search" then
      ctx.explorer_service.setSearch(ui.text_input.window_id, view.value)
    elseif ui.text_input.kind == "explorer_rename" then
      ctx.explorer_service.setRenameText(ui.text_input.window_id, view.value)
    end
  end

  local function focus_text_input(ui, kind, window_id, value, cursor)
    local id = input_id(kind, window_id)
    ctx.text_input_service.focus(id, value or "", cursor)
    ui.text_input = { kind = kind, window_id = window_id, input_id = id }
    sync_text_input(ui)
    return id
  end

  local function draw_text_editor(ui, x, y, width, value, active, input_id_value, text_color, bg_color)
    value = tostring(value or "")
    local view = active and input_view(input_id_value, value) or { value = value, cursor = #value }
    local chars = math.max(1, math.floor(width / 6))
    local shown = ellipsize(view.value, chars)
    if active and view.selection_start and view.selection_end then
      local left = math.min(view.selection_start, view.selection_end)
      local right = math.max(view.selection_start, view.selection_end)
      local sx = x + math.min(left, chars) * 6
      local sw = math.max(1, (math.min(right, chars) - math.min(left, chars)) * 6)
      rect(ui.gpu, sx, y - 2, sw, 11, COLORS.blue)
    end
    draw_text(ui.gpu, x, y, shown, text_color or COLORS.white, bg_color or -1)
    if active then
      local cursor_x = x + math.min(view.cursor or 0, chars) * 6
      rect(ui.gpu, cursor_x, y - 2, 1, 12, text_color or COLORS.white)
      rect(ui.gpu, cursor_x - 2, y - 3, 5, 1, text_color or COLORS.white)
      rect(ui.gpu, cursor_x - 2, y + 10, 5, 1, text_color or COLORS.white)
    end
  end

  local function draw_explorer(ui, window, x, y, w, h)
    local explorer = ctx.explorer_service.list(window.id)
    if not explorer.ok then
      draw_text(ui.gpu, x + 10, y + 24, explorer.error, COLORS.red, -1)
      return
    end
    local data = explorer.data
    local state = data.state
    local content_x, content_y = x + 6, y + 21
    local content_w, content_h = w - 12, h - 28
    local sidebar_w = math.max(50, math.min(76, math.floor(content_w * 0.28)))
    local main_x = content_x + sidebar_w + 5
    local main_w = content_w - sidebar_w - 5

    rect(ui.gpu, content_x, content_y, content_w, content_h, rgb(28, 31, 36))
    rect(ui.gpu, content_x, content_y, sidebar_w, content_h, rgb(35, 39, 45))
    rect(ui.gpu, main_x, content_y, main_w, content_h, rgb(18, 21, 25))

    local toolbar_y = content_y + 4
    local tx = main_x + 4
    local buttons = {
      { id = "explorer_back", text = "<" },
      { id = "explorer_forward", text = ">" },
      { id = "explorer_up", text = "^" },
      { id = "explorer_refresh", text = "R" },
      { id = "explorer_new_folder", text = "+D" },
      { id = "explorer_new_file", text = "+F" },
      { id = "explorer_copy", text = "C" },
      { id = "explorer_cut", text = "X" },
      { id = "explorer_paste", text = "P" },
      { id = "explorer_trash", text = "T" },
    }
    for _, button in ipairs(buttons) do
      local bw = #button.text > 1 and 15 or 11
      small_round(ui.gpu, tx, toolbar_y, bw, 10, rgb(55, 61, 70))
      draw_text(ui.gpu, tx + 3, toolbar_y + 2, button.text, COLORS.white, -1)
      add_hit(ui, button.id, tx, toolbar_y, bw, 11, window.id)
      tx = tx + bw + 3
      if tx > main_x + main_w - 50 then break end
    end

    local search_w = math.max(42, math.min(80, main_w - 8))
    local search_x = main_x + main_w - search_w - 4
    small_round(ui.gpu, search_x, toolbar_y, search_w, 10, rgb(43, 48, 56))
    local search_active = focused_input(ui, "explorer_search", window.id)
    local search_key = input_id("explorer_search", window.id)
    local search_text = state.search ~= "" and state.search or (search_active and "" or "Search")
    draw_text_editor(ui, search_x + 5, toolbar_y + 2, search_w - 8, search_text, search_active, search_key, COLORS.white, -1)
    add_hit(ui, "explorer_search", search_x, toolbar_y, search_w, 11, { window_id = window.id, text_x = search_x + 5 })

    local path_y = toolbar_y + 14
    draw_text(ui.gpu, main_x + 5, path_y, ellipsize(state.path, math.floor((main_w - 8) / 6)), COLORS.white, -1)

    local side_y = content_y + 8
    for _, item in ipairs(data.sidebar or {}) do
      local selected = state.path == item.path
      if selected then rect(ui.gpu, content_x + 3, side_y - 2, sidebar_w - 6, 11, rgb(64, 78, 96)) end
      draw_file_icon(ui.gpu, content_x + 7, side_y - 1, true, selected)
      draw_text(ui.gpu, content_x + 22, side_y, ellipsize(item.name, math.floor((sidebar_w - 24) / 6)), COLORS.white, -1)
      add_hit(ui, "explorer_sidebar", content_x + 3, side_y - 3, sidebar_w - 6, 12, { window_id = window.id, path = item.path })
      side_y = side_y + 13
      if side_y > content_y + content_h - 8 then break end
    end

    local list_y = path_y + 14
    local row_h = 13
    local visible_rows = math.max(1, math.floor((content_y + content_h - list_y - 15) / row_h))
    local max_start = math.max(1, #data.rows - visible_rows + 1)
    local start_index = math.min(max_start, math.max(1, (state.scroll or 0) + 1))
    for index = start_index, math.min(#data.rows, start_index + visible_rows - 1) do
      local row = data.rows[index]
      local row_y = list_y + ((index - start_index) * row_h)
      if row.selected then rect(ui.gpu, main_x + 3, row_y - 2, main_w - 6, row_h, rgb(0, 92, 180)) end
      draw_file_icon(ui.gpu, main_x + 8, row_y - 2, row.dir, row.selected)
      local renaming = data.rename and data.rename.path == row.path
      local name_x = main_x + 23
      if renaming then
        local extension = data.rename.extension or ""
        local extension_w = extension ~= "" and (#extension * 6 + 5) or 0
        local available_w = math.max(36, main_w - 76 - extension_w)
        local input_w = math.max(32, math.min(available_w, (#tostring(data.rename.value or "") * 6) + 14))
        rect(ui.gpu, name_x - 3, row_y - 3, input_w, 11, rgb(236, 241, 247))
        outline(ui.gpu, name_x - 3, row_y - 3, input_w, 11, COLORS.blue)
        local rename_key = input_id("explorer_rename", window.id)
        draw_text_editor(ui, name_x + 1, row_y, input_w - 7, tostring(data.rename.value or ""), focused_input(ui, "explorer_rename", window.id), rename_key, COLORS.black, -1)
        if extension ~= "" then draw_text(ui.gpu, name_x + input_w + 1, row_y, extension, COLORS.white, -1) end
        add_hit(ui, "explorer_rename", name_x - 4, row_y - 4, input_w + extension_w + 4, 13, { window_id = window.id, text_x = name_x + 1 })
      else
        draw_text(ui.gpu, name_x, row_y, ellipsize(row.name, math.floor((main_w - 80) / 6)), COLORS.white, -1)
      end
      local meta = row.dir and "folder" or format_size(row.size)
      draw_text(ui.gpu, main_x + main_w - 45, row_y, meta, COLORS.white, -1)
      add_hit(ui, "explorer_row", main_x + 3, row_y - 3, main_w - 6, row_h, { window_id = window.id, path = row.path })
      if renaming then
        local extension = data.rename.extension or ""
        local extension_w = extension ~= "" and (#extension * 6 + 5) or 0
        local available_w = math.max(36, main_w - 76 - extension_w)
        local input_w = math.max(32, math.min(available_w, (#tostring(data.rename.value or "") * 6) + 14))
        add_hit(ui, "explorer_rename", name_x - 4, row_y - 4, input_w + extension_w + 4, 13, { window_id = window.id, text_x = name_x + 1 })
      end
    end
    if #data.rows > visible_rows then
      small_round(ui.gpu, main_x + main_w - 13, list_y - 1, 9, 9, rgb(48, 54, 63))
      draw_text(ui.gpu, main_x + main_w - 11, list_y + 1, "^", COLORS.white, -1)
      add_hit(ui, "explorer_scroll_up", main_x + main_w - 14, list_y - 2, 11, 11, window.id)
      local down_y = content_y + content_h - 22
      small_round(ui.gpu, main_x + main_w - 13, down_y, 9, 9, rgb(48, 54, 63))
      draw_text(ui.gpu, main_x + main_w - 11, down_y + 1, "v", COLORS.white, -1)
      add_hit(ui, "explorer_scroll_down", main_x + main_w - 14, down_y - 1, 11, 11, window.id)
    end
    if #data.rows == 0 then
      draw_text(ui.gpu, main_x + 8, list_y, state.search ~= "" and "No results" or "Empty folder", COLORS.white, -1)
    end
    local status_y = content_y + content_h - 10
    rect(ui.gpu, main_x, status_y - 2, main_w, 10, rgb(24, 28, 33))
    if data.selected then
      local status = data.selected.name .. " | " .. (data.selected.dir and "folder" or format_size(data.selected.size)) .. " | " .. tostring(data.selected.type)
      draw_text(ui.gpu, main_x + 5, status_y, ellipsize(status, math.floor((main_w - 10) / 6)), COLORS.white, -1)
    elseif data.clipboard then
      draw_text(ui.gpu, main_x + 5, status_y, "Clipboard: " .. data.clipboard.action .. " " .. data.clipboard.name, COLORS.white, -1)
    else
      draw_text(ui.gpu, main_x + 5, status_y, tostring(#data.rows) .. " items", COLORS.white, -1)
    end
  end

  local function draw_settings_row(ui, label, value, x, y, width, separator)
    local value_x = x + math.max(54, math.floor(width * 0.45))
    local value_chars = math.max(1, math.floor((width - (value_x - x)) / 6))
    draw_text(ui.gpu, x, y, label, rgb(84, 88, 94), -1)
    draw_text(ui.gpu, value_x, y, ellipsize(value, value_chars), COLORS.black, -1)
    if separator ~= false then rect(ui.gpu, x, y + 10, width, 1, rgb(219, 223, 230)) end
  end

  local function draw_settings_card(ui, x, y, width, height)
    small_round(ui.gpu, x, y, width, height, rgb(250, 250, 252))
  end

  local function draw_settings_button(ui, id, x, y, width, height, label, payload, color, text_color)
    small_round(ui.gpu, x, y, width, height, color or rgb(226, 231, 238))
    draw_text(ui.gpu, x + 8, y + math.max(3, math.floor((height - 8) / 2)), ellipsize(label, math.floor((width - 16) / 6)), text_color or COLORS.black, -1)
    add_hit(ui, id, x, y, width, height, payload)
  end

  local function draw_settings(ui, window, x, y, w, h)
    local content_x, content_y = x + 6, y + 21
    local content_w, content_h = w - 12, h - 28
    local settings = current_settings(ui)
    local route = settings.route
    local rail_w = math.max(54, math.min(96, math.floor(content_w * 0.34)))
    rail_w = math.min(rail_w, math.max(50, content_w - 70))
    local rail_x = content_x
    local main_x = content_x + rail_w + 5
    local main_w = content_w - rail_w - 5
    rect(ui.gpu, content_x, content_y, content_w, content_h, rgb(238, 241, 245))
    rect(ui.gpu, rail_x, content_y, rail_w, content_h, rgb(31, 34, 40))

    local top_y = content_y + 5
    draw_settings_button(ui, "settings_back", main_x + 6, top_y, 18, 12, "<", nil, #settings.history > 0 and rgb(210, 216, 224) or rgb(196, 200, 206))
    draw_settings_button(ui, "settings_forward", main_x + 28, top_y, 18, 12, ">", nil, #settings.future > 0 and rgb(210, 216, 224) or rgb(196, 200, 206))
    draw_text(ui.gpu, main_x + 54, top_y + 2, settings_title(route), COLORS.black, -1)

    local sections = {
      { id = "general", label = "General" },
      { id = "accessibility", label = "Accessibility" },
      { id = "appearance", label = "Appearance" },
      { id = "about", label = "About" },
      { id = "storage", label = "Storage" },
    }
    local tab_y = content_y + 10
    for _, tab in ipairs(sections) do
      local selected = route == tab.id or (tab.id == "general" and route == "software_update")
      if selected then small_round(ui.gpu, rail_x + 6, tab_y - 4, rail_w - 12, 14, rgb(70, 78, 92)) end
      draw_text(ui.gpu, rail_x + 14, tab_y, ellipsize(tab.label, math.floor((rail_w - 20) / 6)), COLORS.white, -1)
      add_hit(ui, "settings_nav", rail_x + 5, tab_y - 5, rail_w - 10, 16, tab.id)
      tab_y = tab_y + 18
    end

    local body_x, body_y = main_x + 10, content_y + 24
    local body_w = main_w - 20
    if route == "general" then
      draw_text(ui.gpu, body_x, body_y, "Categories", rgb(84, 88, 94), -1)
      draw_settings_button(ui, "settings_sub", body_x, body_y + 15, body_w, 17, "Software Update", "software_update", rgb(250, 250, 252))
      return
    elseif route == "appearance" then
      local themes = { "Blue", "Red", "Green", "White", "Dark" }
      local columns = body_w >= 126 and 2 or 1
      local gap = 8
      local tile_w = math.floor((body_w - ((columns - 1) * gap)) / columns)
      local colors_by_theme = {
        Blue = COLORS.blue,
        Red = COLORS.red,
        Green = COLORS.green,
        White = rgb(245, 245, 245),
        Dark = rgb(28, 31, 36),
      }
      for index, theme in ipairs(themes) do
        local col = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        local tile_x = body_x + col * (tile_w + gap)
        local tile_y = body_y + row * 21
        if tile_y + 16 <= content_y + content_h - 5 then
          draw_settings_button(ui, "settings_theme", tile_x, tile_y, tile_w, 16, theme, theme:lower(), colors_by_theme[theme] or rgb(226, 231, 238), theme == "Dark" and COLORS.white or COLORS.black)
        end
      end
      return
    end

    if route == "software_update" then
      local update = ctx.update_service.poll().data
      draw_text(ui.gpu, body_x, body_y, "DockOS " .. ctx.version.codename .. " " .. ctx.version.version, rgb(88, 92, 98), -1)
      local card_x, card_y = body_x, body_y + 16
      local card_w, card_h = body_w, math.max(48, content_y + content_h - card_y - 6)
      draw_settings_card(ui, card_x, card_y, card_w, card_h)
      if update.status == "checking" then
        draw_text(ui.gpu, card_x + 12, card_y + 14, loading.text("Fetching Updates", ui.frame), rgb(116, 121, 128), -1)
      elseif update.status == "available" and update.available then
        draw_text(ui.gpu, card_x + 12, card_y + 9, ellipsize(update.available.title, math.floor((card_w - 24) / 6)), COLORS.black, -1)
        draw_text(ui.gpu, card_x + 12, card_y + 23, ellipsize(update.available.changelog, math.floor((card_w - 24) / 6)), rgb(84, 88, 94), -1)
        draw_text(ui.gpu, card_x + 12, card_y + 37, "Install time: " .. update.available.eta, rgb(84, 88, 94), -1)
        draw_settings_button(ui, "settings_update_install", card_x + card_w - 62, card_y + card_h - 19, 50, 14, "Update", nil, COLORS.blue, COLORS.white)
      elseif update.status == "installing" then
        draw_text(ui.gpu, card_x + 12, card_y + 14, loading.text("Installing Update", ui.frame), rgb(116, 121, 128), -1)
      elseif update.status == "installed" then
        draw_text(ui.gpu, card_x + 12, card_y + 14, "Update installed. Reboot required.", rgb(60, 64, 70), -1)
      else
        draw_text(ui.gpu, card_x + 12, card_y + 14, "No updates", rgb(116, 121, 128), -1)
      end
    elseif route == "about" then
      local card_h = 49
      draw_settings_card(ui, body_x, body_y, body_w, card_h)
      draw_text(ui.gpu, body_x + 10, body_y + 6, "Computer Info", COLORS.black, -1)
      draw_settings_row(ui, "Edition", tostring(ctx.version.edition or "Basic"), body_x + 10, body_y + 18, body_w - 20)
      draw_settings_row(ui, "Memory", "-", body_x + 10, body_y + 29, body_w - 20)
      draw_settings_row(ui, "Storage", "-", body_x + 10, body_y + 40, body_w - 20, false)
      local dock_card_y = body_y + card_h + 6
      if dock_card_y + 27 <= content_y + content_h then
        draw_settings_card(ui, body_x, dock_card_y, body_w, 27)
        draw_text(ui.gpu, body_x + 10, dock_card_y + 5, "DockOS", COLORS.black, -1)
        draw_text(ui.gpu, body_x + 10, dock_card_y + 17, "DockOS " .. ctx.version.codename .. " " .. ctx.version.version, rgb(84, 88, 94), -1)
      end
    elseif route == "storage" then
      local free = fs.getFreeSpace and fs.getFreeSpace("/") or nil
      local used_label = "-"
      local free_label = type(free) == "number" and format_size(free) or tostring(free or "-")
      draw_settings_card(ui, body_x, body_y, body_w, 48)
      draw_text(ui.gpu, body_x + 10, body_y + 8, "Storage", COLORS.black, -1)
      draw_settings_row(ui, "Used", used_label, body_x + 10, body_y + 23, body_w - 20)
      draw_settings_row(ui, "Available", free_label, body_x + 10, body_y + 36, body_w - 20)
    elseif route == "accessibility" then
      local options = {
        { label = "Text Size", value = tostring(ctx.settings_service.get("user.accessibility.text_size", "Normal").data) },
        { label = "Cursor Size", value = tostring(ctx.settings_service.get("user.accessibility.cursor_size", "Normal").data) },
        { label = "Contrast", value = tostring(ctx.settings_service.get("user.accessibility.contrast", "Standard").data) },
        { label = "Reduce Motion", value = tostring(ctx.settings_service.get("user.accessibility.reduce_motion", "Off").data) },
        { label = "Reduce Transparency", value = tostring(ctx.settings_service.get("user.accessibility.reduce_transparency", "Off").data) },
        { label = "Button Labels", value = tostring(ctx.settings_service.get("user.accessibility.button_labels", "On").data) },
        { label = "Sound Feedback", value = tostring(ctx.settings_service.get("user.accessibility.sound_feedback", "Off").data) },
      }
      local visible = math.max(1, math.floor((content_y + content_h - body_y - 6) / 17))
      local scroll = math.min(tonumber(settings.scroll.accessibility) or 0, math.max(0, #options - visible))
      settings.scroll.accessibility = scroll
      for index = 1, math.min(visible, #options) do
        local option = options[index + scroll]
        local row_y = body_y + ((index - 1) * 17)
        draw_settings_card(ui, body_x, row_y, body_w - 8, 14)
        draw_text(ui.gpu, body_x + 8, row_y + 4, ellipsize(option.label, math.floor((body_w - 68) / 6)), COLORS.black, -1)
        draw_text(ui.gpu, body_x + body_w - 58, row_y + 4, ellipsize(option.value, 8), rgb(84, 88, 94), -1)
      end
      local metrics = scrollbar.metrics(#options, visible, scroll, body_x + body_w - 5, body_y, math.max(14, visible * 17 - 3))
      scrollbar.draw(ui.gpu, metrics, { track = rgb(220, 224, 230), thumb = rgb(110, 118, 128) })
      if metrics.enabled then add_hit(ui, "settings_scrollbar", metrics.x - 3, metrics.y, 10, metrics.h, { route = "accessibility", metrics = metrics }) end
    else
      draw_text(ui.gpu, body_x, body_y, "Section unavailable", rgb(84, 88, 94), -1)
    end
  end

  local function draw_studio(ui, window, x, y, w, h)
    local project = ctx.studio_service.current().data
    local content_x, content_y = x + 6, y + 21
    local content_w, content_h = w - 12, h - 28
    rect(ui.gpu, content_x, content_y, content_w, content_h, rgb(19, 22, 27))

    local toolbar_h = 18
    rect(ui.gpu, content_x, content_y, content_w, toolbar_h, rgb(36, 40, 48))
    local bx = content_x + 6
    local buttons = {
      { id = "studio_new", label = "New" },
      { id = "studio_save", label = "Save" },
      { id = "studio_export", label = "Export" },
      { id = "studio_insert", label = "Text", payload = "text" },
      { id = "studio_insert", label = "Button", payload = "button" },
      { id = "studio_insert", label = "Input", payload = "input" },
      { id = "studio_insert", label = "Shape", payload = "shape" },
    }
    for _, button in ipairs(buttons) do
      local bw = math.max(30, #button.label * 6 + 12)
      if bx + bw < content_x + content_w - 4 then
        small_round(ui.gpu, bx, content_y + 4, bw, 11, button.id == "studio_export" and COLORS.blue or rgb(66, 72, 84))
        draw_text(ui.gpu, bx + 6, content_y + 6, button.label, COLORS.white, -1)
        add_hit(ui, button.id, bx, content_y + 3, bw, 13, button.payload)
        bx = bx + bw + 5
      end
    end

    local body_y = content_y + toolbar_h + 5
    local body_h = content_h - toolbar_h - 9
    local code_w = math.max(94, math.floor(content_w * 0.43))
    local preview_x = content_x + code_w + 6
    local preview_w = content_w - code_w - 6
    rect(ui.gpu, content_x, body_y, code_w, body_h, rgb(12, 14, 18))
    rect(ui.gpu, preview_x, body_y, preview_w, body_h, rgb(242, 244, 248))
    draw_text(ui.gpu, content_x + 8, body_y + 6, "Code", COLORS.white, -1)
    draw_text(ui.gpu, preview_x + 8, body_y + 6, "Preview", COLORS.black, -1)
    draw_text(ui.gpu, preview_x + 8, body_y + 20, ellipsize(project.name, math.floor((preview_w - 16) / 6)), COLORS.black, -1)

    local code_lines = {
      "app " .. project.id,
      "name " .. project.name,
      "components " .. tostring(#(project.components or {})),
      "export -> user Apps",
    }
    local line_y = body_y + 22
    for _, line in ipairs(code_lines) do
      draw_text(ui.gpu, content_x + 8, line_y, ellipsize(line, math.floor((code_w - 16) / 6)), rgb(186, 220, 255), -1)
      line_y = line_y + 12
    end

    local canvas_x, canvas_y = preview_x + 8, body_y + 35
    local canvas_w, canvas_h = preview_w - 16, body_h - 43
    rect(ui.gpu, canvas_x, canvas_y, canvas_w, canvas_h, COLORS.white)
    outline(ui.gpu, canvas_x, canvas_y, canvas_w, canvas_h, rgb(205, 211, 220))
    for index, component in ipairs(project.components or {}) do
      local cx = canvas_x + math.min(canvas_w - 20, math.max(2, component.x or 2))
      local cy = canvas_y + math.min(canvas_h - 12, math.max(2, component.y or 2))
      local cw = math.min(canvas_w - (cx - canvas_x) - 2, component.w or 50)
      local ch = math.min(canvas_h - (cy - canvas_y) - 2, component.h or 14)
      if component.kind == "text" then
        draw_text(ui.gpu, cx, cy, ellipsize(component.text or "Text", math.floor(cw / 6)), COLORS.black, -1)
      elseif component.kind == "input" then
        rect(ui.gpu, cx, cy, cw, ch, rgb(236, 240, 246)); outline(ui.gpu, cx, cy, cw, ch, rgb(160, 168, 180))
        draw_text(ui.gpu, cx + 5, cy + 4, ellipsize(component.label or "Input", math.floor((cw - 10) / 6)), rgb(84, 88, 94), -1)
      elseif component.kind == "shape" then
        rect(ui.gpu, cx, cy, cw, ch, rgb(218, 225, 238)); outline(ui.gpu, cx, cy, cw, ch, COLORS.blue)
      else
        small_round(ui.gpu, cx, cy, cw, ch, COLORS.blue)
        draw_text(ui.gpu, cx + 6, cy + 4, ellipsize(component.label or "Button", math.floor((cw - 12) / 6)), COLORS.white, -1)
      end
      if index == project.selected then outline(ui.gpu, cx - 2, cy - 2, cw + 4, ch + 4, COLORS.red) end
    end
    local status = project.dirty and "Unsaved" or "Saved"
    draw_text(ui.gpu, content_x + content_w - (#status * 6) - 8, content_y + 6, status, COLORS.white, -1)
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
      draw_explorer(ui, window, x, y, w, h)
    elseif app_id == "dock.settings" then
      draw_settings(ui, window, x, y, w, h)
    elseif app_id == "dock.studio" then
      draw_studio(ui, window, x, y, w, h)
    elseif app_id == "dock.terminal" then
      draw_text(ui.gpu, content_x, content_y, "Terminal", COLORS.white, -1)
      draw_text(ui.gpu, content_x, content_y + 14, "Use dock commands from CraftOS.", COLORS.white, -1)
    else
      draw_text(ui.gpu, content_x, content_y, window.app.manifest.name, COLORS.white, -1)
    end
  end

  local function render(ui)
    ui.frame = (ui.frame or 0) + 1
    ui.hits = {}
    local update_status = ctx.update_service and ctx.update_service.status().data.status or "idle"
    if ctx.cursor_service then ctx.cursor_service.setBusy("dock.settings", update_status == "checking" or update_status == "installing") end
    draw_wallpaper(ui)
    draw_top(ui)
    for _, window in ipairs(ui.windows) do draw_window(ui, window) end
    draw_selection(ui)
    draw_dock(ui)
    draw_menu(ui)
    draw_context(ui)
    draw_about(ui)
    if ctx.cursor_service then
      local hover = hit_at(ui, ui.cursor.x, ui.cursor.y)
      local kind = ctx.cursor_service.infer(hover, ui.dragging_window or ui.dragging_dock or ui.dragging_text)
      ctx.cursor_service.draw(ui.gpu, kind, ui.frame)
    end
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

  local function finish_text_input(ui, commit)
    if not ui.text_input then return end
    sync_text_input(ui)
    local input = ui.text_input
    if input.kind == "explorer_rename" then
      if commit then ctx.explorer_service.commitRename(input.window_id) else ctx.explorer_service.cancelRename(input.window_id) end
    end
    ui.text_input = nil
  end

  local function handle_action(ui, hit, button, x, y)
    if not hit then
      ui.menu, ui.context = false, nil
      finish_text_input(ui, true)
      if button == 1 then ui.selecting = { x1 = x, y1 = y, x2 = x, y2 = y } end
      return
    end
    if ui.text_input and ui.text_input.kind == "explorer_rename" and hit.id ~= "explorer_rename" then
      finish_text_input(ui, true)
    elseif ui.text_input and ui.text_input.kind == "explorer_search" and hit.id ~= "explorer_search" then
      finish_text_input(ui, true)
    end
    if hit.id == "system_menu" then ui.menu = not ui.menu; ui.context = nil
    elseif hit.id == "top_menu" then
      if hit.payload and hit.payload.action == "system" then ui.menu = not ui.menu; ui.context = nil else ctx.menu_service.dispatch(hit.payload and hit.payload.app_id, hit.payload and hit.payload.action, {}) end
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
    elseif hit.id == "explorer_sidebar" then ctx.explorer_service.navigate(hit.payload.window_id, hit.payload.path)
    elseif hit.id == "explorer_row" then ctx.explorer_service.select(hit.payload.window_id, hit.payload.path)
    elseif hit.id == "explorer_search" then
      local window_id = hit.payload.window_id
      local state = ctx.explorer_service.state(window_id).data
      local id = focus_text_input(ui, "explorer_search", window_id, state.search or "", #tostring(state.search or ""))
      ctx.text_input_service.cursorFromX(id, x, hit.payload.text_x, 6, false)
      sync_text_input(ui)
      ui.dragging_text = { input_id = id, kind = "explorer_search", window_id = window_id, text_x = hit.payload.text_x }
    elseif hit.id == "explorer_rename" then
      local window_id = hit.payload.window_id
      local listed = ctx.explorer_service.list(window_id)
      local rename = listed.ok and listed.data.rename or nil
      if not rename then
        local started = ctx.explorer_service.startRename(window_id)
        rename = started.ok and started.data or { value = "" }
      end
      local id = focus_text_input(ui, "explorer_rename", window_id, rename.value or "", #tostring(rename.value or ""))
      ctx.text_input_service.cursorFromX(id, x, hit.payload.text_x, 6, false)
      sync_text_input(ui)
      ui.dragging_text = { input_id = id, kind = "explorer_rename", window_id = window_id, text_x = hit.payload.text_x }
    elseif hit.id == "explorer_back" then ctx.explorer_service.back(hit.payload)
    elseif hit.id == "explorer_forward" then ctx.explorer_service.forward(hit.payload)
    elseif hit.id == "explorer_up" then ctx.explorer_service.up(hit.payload)
    elseif hit.id == "explorer_refresh" then ctx.explorer_service.state(hit.payload)
    elseif hit.id == "explorer_new_folder" then ctx.explorer_service.createFolder(hit.payload)
    elseif hit.id == "explorer_new_file" then ctx.explorer_service.createFile(hit.payload)
    elseif hit.id == "explorer_copy" then ctx.explorer_service.copySelected(hit.payload)
    elseif hit.id == "explorer_cut" then ctx.explorer_service.cutSelected(hit.payload)
    elseif hit.id == "explorer_paste" then ctx.explorer_service.paste(hit.payload)
    elseif hit.id == "explorer_trash" then ctx.explorer_service.trashSelected(hit.payload)
    elseif hit.id == "explorer_scroll_up" then ctx.explorer_service.scroll(hit.payload, -1)
    elseif hit.id == "explorer_scroll_down" then ctx.explorer_service.scroll(hit.payload, 1)
    elseif hit.id == "settings_back" then settings_back(ui)
    elseif hit.id == "settings_forward" then settings_forward(ui)
    elseif hit.id == "settings_nav" then settings_go(ui, hit.payload)
    elseif hit.id == "settings_sub" then settings_go(ui, hit.payload)
    elseif hit.id == "settings_scrollbar" then
      local settings = current_settings(ui)
      settings.scroll[hit.payload.route] = scrollbar.offsetFromY(hit.payload.metrics, y)
    elseif hit.id == "settings_theme" then ctx.settings_service.set("user.theme", hit.payload)
    elseif hit.id == "settings_update_install" then ctx.update_service.installAvailable()
    elseif hit.id == "studio_new" then ctx.studio_service.newProject()
    elseif hit.id == "studio_save" then ctx.studio_service.save()
    elseif hit.id == "studio_export" then ctx.studio_service.exportApp()
    elseif hit.id == "studio_insert" then ctx.studio_service.addComponent(hit.payload)
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

  local function handle_text_input(ui, event, a, b)
    if not ui.text_input then return false end
    local input = ui.text_input
    local id = input.input_id or input_id(input.kind, input.window_id)
    if event == "char" then
      ctx.text_input_service.insert(id, a)
      sync_text_input(ui)
      return true
    elseif event == "paste" then
      ctx.text_input_service.insert(id, a)
      sync_text_input(ui)
      return true
    elseif event == "tm_keyboard_char" then
      ctx.text_input_service.insert(id, b or a)
      sync_text_input(ui)
      return true
    elseif event == "tm_keyboard_paste" then
      ctx.text_input_service.insert(id, b or a)
      sync_text_input(ui)
      return true
    elseif event == "key" then
      if ui.modifiers.ctrl and keys and a == keys.c then ctx.text_input_service.copy(id); return true end
      if ui.modifiers.ctrl and keys and a == keys.x then ctx.text_input_service.cut(id); sync_text_input(ui); return true end
      if ui.modifiers.ctrl and keys and a == keys.v then ctx.text_input_service.paste(id); sync_text_input(ui); return true end
      if ui.modifiers.ctrl and keys and a == keys.a then ctx.text_input_service.selectAll(id); return true end
      if keys and a == keys.backspace then ctx.text_input_service.backspace(id); sync_text_input(ui); return true end
      if keys and a == keys.delete then ctx.text_input_service.delete(id); sync_text_input(ui); return true end
      if keys and a == keys.left then ctx.text_input_service.move(id, -1, ui.modifiers.shift); return true end
      if keys and a == keys.right then ctx.text_input_service.move(id, 1, ui.modifiers.shift); return true end
      if keys and a == keys.home then ctx.text_input_service.set(id, ctx.text_input_service.view(id).data.value, 0); return true end
      if keys and a == keys["end"] then local view = ctx.text_input_service.view(id).data; ctx.text_input_service.set(id, view.value, #view.value); return true end
      if keys and (a == keys.enter or a == keys.numPadEnter) then finish_text_input(ui, true); return true end
      if keys and a == keys.escape then finish_text_input(ui, false); return true end
    elseif event == "tm_keyboard_key" then
      local key = b or a
      if ui.modifiers.ctrl and keys and key == keys.c then ctx.text_input_service.copy(id); return true end
      if ui.modifiers.ctrl and keys and key == keys.x then ctx.text_input_service.cut(id); sync_text_input(ui); return true end
      if ui.modifiers.ctrl and keys and key == keys.v then ctx.text_input_service.paste(id); sync_text_input(ui); return true end
      if ui.modifiers.ctrl and keys and key == keys.a then ctx.text_input_service.selectAll(id); return true end
      if keys and key == keys.backspace then ctx.text_input_service.backspace(id); sync_text_input(ui); return true end
      if keys and key == keys.delete then ctx.text_input_service.delete(id); sync_text_input(ui); return true end
      if keys and key == keys.left then ctx.text_input_service.move(id, -1, ui.modifiers.shift); return true end
      if keys and key == keys.right then ctx.text_input_service.move(id, 1, ui.modifiers.shift); return true end
      if keys and key == keys.home then ctx.text_input_service.set(id, ctx.text_input_service.view(id).data.value, 0); return true end
      if keys and key == keys["end"] then local view = ctx.text_input_service.view(id).data; ctx.text_input_service.set(id, view.value, #view.value); return true end
      if keys and (key == keys.enter or key == keys.numPadEnter) then finish_text_input(ui, true); return true end
      if keys and key == keys.escape then finish_text_input(ui, false); return true end
    end
    return false
  end

  local function handle_global_key(ui, event, a, b)
    local key = event == "tm_keyboard_key" and (b or a) or a
    if not keys or not key then return false end
    if key == keys.enter or key == keys.numPadEnter then
      local window = active_window(ui)
      if window and window.app_id == "dock.files" then
        local started = ctx.explorer_service.startRename(window.id)
        if started.ok then focus_text_input(ui, "explorer_rename", window.id, started.data.value or "", #tostring(started.data.value or "")); return true end
      end
    end
    return false
  end

  local function handle_modifier_key(ui, event, a, b)
    if not keys then return false end
    local key = event == "tm_keyboard_key" and (b or a) or a
    if event == "key" or event == "tm_keyboard_key" then
      if key == keys.leftCtrl or key == keys.rightCtrl then ui.modifiers.ctrl = true; return true end
      if key == keys.leftShift or key == keys.rightShift then ui.modifiers.shift = true; return true end
    elseif event == "key_up" or event == "tm_keyboard_key_up" then
      if key == keys.leftCtrl or key == keys.rightCtrl then ui.modifiers.ctrl = false; return true end
      if key == keys.leftShift or key == keys.rightShift then ui.modifiers.shift = false; return true end
    end
    return false
  end

  local function needs_animation(ui)
    local update = ctx.update_service and ctx.update_service.status().data
    local update_status = update and update.status or "idle"
    return ui.text_input ~= nil or update_status == "checking" or update_status == "installing"
  end

  local function run_graphical(gpu, width, height)
    local ui = initial_ui_state(gpu, width, height)
    while true do
      render(ui)
      if needs_animation(ui) and os.startTimer then os.startTimer(0.25) end
      local event, a, b, c, d = os.pullEvent()
      if ctx.process_manager and ctx.process_manager.dispatch then ctx.process_manager.dispatch(event, a, b, c, d) end
      if handle_modifier_key(ui, event, a, b) then
      elseif handle_text_input(ui, event, a, b) then
      elseif not ui.text_input and (event == "key" or event == "tm_keyboard_key") and handle_global_key(ui, event, a, b) then
      elseif event == "rednet_message" then ctx.net_service.handleMessage(a, b, c)
      elseif event == "key" and not ui.text_input and keys and a == keys.q then return { ok = true }
      else
        local mapped, button, x, y = pixel_event(event, a, b, c, d)
        if (mapped == "mouse_click" or mapped == "mouse_drag" or mapped == "mouse_up" or mapped == "mouse_move" or mapped == "mouse_scroll") and ctx.cursor_service then
          ctx.cursor_service.setPosition(x, y)
          ui.cursor.x, ui.cursor.y = x, y
        end
        if mapped == "mouse_click" then
          ui.selecting = nil
          handle_action(ui, hit_at(ui, x, y), button, x, y)
        elseif mapped == "mouse_drag" then
          if ui.dragging_text then
            ctx.text_input_service.cursorFromX(ui.dragging_text.input_id, x, ui.dragging_text.text_x, 6, true)
            sync_text_input(ui)
          elseif ui.dragging_window then
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
          ui.dragging_text = nil
          ui.selecting = nil
        elseif mapped == "mouse_scroll" then
          local window = active_window(ui)
          if window and window.app_id == "dock.settings" then settings_scroll(ui, button) end
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
    print("DockOS " .. ctx.version.codename .. " " .. ctx.version.version)
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
