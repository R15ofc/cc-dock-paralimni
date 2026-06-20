local tom = require("dock.system.tom_adapter")

local M = {}

local function rgb(red, green, blue)
  red = math.max(0, math.min(255, math.floor(red or 0)))
  green = math.max(0, math.min(255, math.floor(green or 0)))
  blue = math.max(0, math.min(255, math.floor(blue or 0)))
  return red * 65536 + green * 256 + blue
end

local WHITE = rgb(255, 255, 255)
local BLACK = rgb(0, 0, 0)
local GRAY = rgb(105, 105, 110)

local function rect(gpu, x, y, width, height, color)
  if not gpu or width <= 0 or height <= 0 then return end
  x, y, width, height = math.floor(x), math.floor(y), math.floor(width), math.floor(height)
  if gpu.filledRectangle and pcall(gpu.filledRectangle, x, y, width, height, color) then return end
  local red = math.floor(color / 65536) % 256
  local green = math.floor(color / 256) % 256
  local blue = color % 256
  if gpu.fillRect then pcall(gpu.fillRect, x, y, width, height, red, green, blue) end
end

local function draw_text(gpu, x, y, text, color)
  if gpu and gpu.drawText then pcall(gpu.drawText, math.floor(x), math.floor(y), tostring(text or ""), color or WHITE, -1, 1, 0) end
end

local function centered_lines(text, max_chars)
  text = tostring(text or "")
  max_chars = math.max(1, tonumber(max_chars) or #text)
  local lines, line = {}, ""
  for word in text:gmatch("%S+") do
    if line == "" then
      line = word
    elseif #line + #word + 1 <= max_chars then
      line = line .. " " .. word
    else
      table.insert(lines, line)
      line = word
    end
  end
  if line ~= "" then table.insert(lines, line) end
  if #lines == 0 then table.insert(lines, text) end
  return lines
end

local function draw_centered_text(gpu, width, y, text, color)
  local max_chars = math.max(1, math.floor((width - 18) / 6))
  for index, line in ipairs(centered_lines(text, max_chars)) do
    local x = math.max(1, math.floor((width - (#line * 6)) / 2))
    draw_text(gpu, x, y + ((index - 1) * 10), line, color)
  end
end

local function gpu_size(gpu)
  local width, height = 384, 192
  if gpu and gpu.refreshSize then pcall(gpu.refreshSize) end
  if gpu and gpu.getSize then
    local ok, w, h = pcall(gpu.getSize)
    if ok and type(w) == "number" and type(h) == "number" then width, height = w, h end
  end
  return width, height
end

local function fallback_terminal(message, percent)
  if not term then return end
  pcall(function()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    print("DockOS")
    if message and message ~= "" then print(message) end
    if percent then print(tostring(math.floor(percent)) .. "%") end
  end)
end

function M.draw(gpu, options)
  options = options or {}
  if not gpu then
    fallback_terminal(options.message, options.progress)
    return
  end
  local width, height = gpu_size(gpu)
  if gpu.fill then pcall(gpu.fill, BLACK) else rect(gpu, 1, 1, width, height, BLACK) end

  local logo = options.logo or "DockOS"
  local logo_width = #logo * 6
  local logo_x = math.max(1, math.floor((width - logo_width) / 2))
  local logo_y = math.max(12, math.floor(height * 0.38))
  draw_text(gpu, logo_x, logo_y, logo, WHITE)

  local bar_width = math.max(58, math.min(190, math.floor(width * 0.42)))
  local bar_height = math.max(2, math.min(5, math.floor(height * 0.018)))
  local bar_x = math.floor((width - bar_width) / 2)
  local bar_y = logo_y + math.max(18, math.floor(height * 0.10))
  rect(gpu, bar_x, bar_y, bar_width, bar_height, GRAY)
  rect(gpu, bar_x, bar_y, math.max(1, math.floor(bar_width * math.max(0, math.min(100, options.progress or 0)) / 100)), bar_height, WHITE)

  if options.message and options.message ~= "" then
    draw_centered_text(gpu, width, bar_y + 14, options.message, WHITE)
  end
  if gpu.sync then pcall(gpu.sync) end
end

function M.show(options)
  options = options or {}
  local _, gpu = tom.findGPU()
  M.draw(gpu, options)
end

function M.sequence(options)
  options = options or {}
  local _, gpu = tom.findGPU()
  local steps = options.steps or { 12, 36, 64, 82, 100 }
  for _, progress in ipairs(steps) do
    M.draw(gpu, { logo = options.logo, message = options.message, progress = progress })
    if sleep then sleep(options.delay or 0.06) end
  end
end

return M
