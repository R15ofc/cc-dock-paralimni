local loading = require("dock.system.loading")

local M = {}

local function ok(data) return { ok = true, data = data } end

local function rgb(red, green, blue)
  red = math.max(0, math.min(255, math.floor(red or 0)))
  green = math.max(0, math.min(255, math.floor(green or 0)))
  blue = math.max(0, math.min(255, math.floor(blue or 0)))
  return red * 65536 + green * 256 + blue
end

local WHITE = rgb(255, 255, 255)
local BLACK = rgb(0, 0, 0)
local RED = rgb(255, 59, 48)
local BLUE = rgb(0, 122, 255)

local function rect(gpu, x, y, width, height, color)
  if not gpu or width <= 0 or height <= 0 then return end
  x, y, width, height = math.floor(x), math.floor(y), math.floor(width), math.floor(height)
  if gpu.filledRectangle and pcall(gpu.filledRectangle, x, y, width, height, color) then return end
  local red = math.floor(color / 65536) % 256
  local green = math.floor(color / 256) % 256
  local blue = color % 256
  if gpu.fillRect then pcall(gpu.fillRect, x, y, width, height, red, green, blue) end
end

local function draw_text(gpu, x, y, text, fg, bg)
  if gpu and gpu.drawText then pcall(gpu.drawText, math.floor(x), math.floor(y), tostring(text or ""), fg or WHITE, bg or -1, 1, 0) end
end

local function draw_arrow(gpu, x, y)
  local points = {
    { 0, 0 }, { 0, 1 }, { 0, 2 }, { 0, 3 }, { 0, 4 }, { 0, 5 }, { 0, 6 }, { 0, 7 },
    { 1, 1 }, { 1, 2 }, { 1, 3 }, { 1, 4 }, { 1, 5 }, { 1, 6 },
    { 2, 2 }, { 2, 3 }, { 2, 4 }, { 2, 5 },
    { 3, 3 }, { 3, 4 }, { 3, 5 },
    { 4, 4 }, { 4, 5 },
    { 5, 5 },
    { 2, 7 }, { 3, 8 }, { 4, 9 },
  }
  for _, point in ipairs(points) do rect(gpu, x + point[1], y + point[2], 1, 1, BLACK) end
  for _, point in ipairs(points) do rect(gpu, x + point[1] + 1, y + point[2], 1, 1, WHITE) end
end

local function draw_denied(gpu, x, y)
  rect(gpu, x + 8, y + 9, 8, 2, RED)
  rect(gpu, x + 7, y + 10, 2, 5, RED)
  rect(gpu, x + 15, y + 10, 2, 5, RED)
  rect(gpu, x + 8, y + 15, 8, 2, RED)
  rect(gpu, x + 9, y + 14, 6, 1, RED)
end

local function draw_drag(gpu, x, y)
  rect(gpu, x + 8, y + 10, 8, 2, BLUE)
  rect(gpu, x + 11, y + 7, 2, 8, BLUE)
  rect(gpu, x + 7, y + 9, 2, 4, BLUE)
  rect(gpu, x + 15, y + 9, 2, 4, BLUE)
end

local function draw_click(gpu, x, y)
  rect(gpu, x + 9, y + 10, 5, 5, BLUE)
  rect(gpu, x + 8, y + 11, 7, 3, BLUE)
  rect(gpu, x + 10, y + 9, 3, 7, BLUE)
end

function M.new()
  local service = {
    x = 8,
    y = 8,
    kind = "default",
    visible = true,
    busy = {},
  }

  local clickable = {
    system_menu = true, about = true, about_close = true, reboot = true, shutdown = true,
    dock_app = true, dock_keep = true,
    explorer_sidebar = true, explorer_row = true, explorer_search = true, explorer_rename = true,
    explorer_back = true, explorer_forward = true, explorer_up = true, explorer_refresh = true,
    explorer_new_folder = true, explorer_new_file = true, explorer_copy = true, explorer_cut = true,
    explorer_paste = true, explorer_trash = true, explorer_scroll_up = true, explorer_scroll_down = true,
    settings_back = true, settings_forward = true, settings_nav = true, settings_sub = true,
    settings_theme = true, settings_update_install = true,
    studio_new = true, studio_save = true, studio_export = true, studio_insert = true, studio_field = true,
    top_menu = true, window_close = true, window_min = true, window_full = true,
  }

  local draggable = { window_drag = true, dock_app = true, studio_splitter = true }
  local denied = { dock_divider = true }

  function service.setPosition(x, y)
    service.x = math.max(1, math.floor(tonumber(x) or service.x or 1))
    service.y = math.max(1, math.floor(tonumber(y) or service.y or 1))
    return ok({ x = service.x, y = service.y })
  end

  function service.setBusy(id, value)
    if value then service.busy[tostring(id)] = true else service.busy[tostring(id)] = nil end
    return ok(service.busy)
  end

  function service.infer(hit, dragging)
    if dragging then return "drag" end
    if hit and hit.payload and type(hit.payload) == "string" and service.busy[hit.payload] then return "loading" end
    if hit and denied[hit.id] then return "denied" end
    if hit and draggable[hit.id] then return "drag" end
    if hit and clickable[hit.id] then return "click" end
    return "default"
  end

  function service.draw(gpu, kind, frame)
    if not service.visible then return ok(false) end
    kind = kind or service.kind or "default"
    local x, y = service.x, service.y
    draw_arrow(gpu, x, y)
    if kind == "click" then draw_click(gpu, x, y)
    elseif kind == "drag" then draw_drag(gpu, x, y)
    elseif kind == "denied" then draw_denied(gpu, x, y)
    elseif kind == "loading" then draw_text(gpu, x + 8, y + 9, loading.spinner(frame), WHITE, BLACK) end
    return ok(kind)
  end

  function service.start() return ok(true) end

  return service
end

return M
