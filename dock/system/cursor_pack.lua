local M = {}

local function rgb(red, green, blue)
  red = math.max(0, math.min(255, math.floor(red or 0)))
  green = math.max(0, math.min(255, math.floor(green or 0)))
  blue = math.max(0, math.min(255, math.floor(blue or 0)))
  return red * 65536 + green * 256 + blue
end

M.colors = {
  outline = rgb(0, 0, 0),
  fill = rgb(255, 255, 255),
  accent = rgb(0, 122, 255),
  danger = rgb(255, 59, 48),
}

local sprites = {
  default = {
    "O...........",
    "OF..........",
    "OFF.........",
    "OFFF........",
    "OFFFF.......",
    "OFFFFF......",
    "OFFFFFF.....",
    "OFFFF.......",
    "OF.OFF......",
    "O..OFF......",
    "....OFF.....",
  },
  click = {
    "O...........",
    "OF..........",
    "OFF.........",
    "OFFF........",
    "OFFFF.......",
    "OFFFFF......",
    "OFFFFFF.....",
    "OFFFF.......",
    "OF.OFF......",
    "O..OFF..A...",
    "....OFFAAA..",
    ".......AAA..",
    "........A...",
  },
  text = {
    "..OOOOO.....",
    "....F.......",
    "....F.......",
    "....F.......",
    "....F.......",
    "....F.......",
    "....F.......",
    "....F.......",
    "....F.......",
    "....F.......",
    "..OOOOO.....",
  },
  drag = {
    "....A.......",
    "....A.......",
    "..AAAAA.....",
    "....A.......",
    "....A.......",
    "A.AAAAA.A...",
    "AA..A..AA...",
    "A...A...A...",
    "....A.......",
    "..AAAAA.....",
    "....A.......",
    "....A.......",
  },
  denied = {
    "...DDDD.....",
    "..D....D....",
    ".D..DD..D...",
    ".D.D..D.D...",
    ".D.D..D.D...",
    ".D..DD..D...",
    "..D....D....",
    "...DDDD.....",
  },
}

local function pixel(gpu, x, y, color)
  if not gpu then return end
  x, y = math.floor(x), math.floor(y)
  if gpu.filledRectangle and pcall(gpu.filledRectangle, x, y, 1, 1, color) then return end
  if gpu.fillRect then
    local red = math.floor(color / 65536) % 256
    local green = math.floor(color / 256) % 256
    local blue = color % 256
    pcall(gpu.fillRect, x, y, 1, 1, red, green, blue)
  end
end

function M.draw(gpu, kind, x, y, frame, spinner)
  kind = kind or "default"
  if kind == "loading" then
    M.draw(gpu, "default", x, y, frame)
    if gpu and gpu.drawText then pcall(gpu.drawText, math.floor(x + 10), math.floor(y + 8), spinner or "|", M.colors.fill, M.colors.outline, 1, 0) end
    return true
  end
  local sprite = sprites[kind] or sprites.default
  local colors = M.colors
  for row_index, row in ipairs(sprite) do
    for col = 1, #row do
      local code = row:sub(col, col)
      if code == "O" then pixel(gpu, x + col - 1, y + row_index - 1, colors.outline)
      elseif code == "F" then pixel(gpu, x + col - 1, y + row_index - 1, colors.fill)
      elseif code == "A" then pixel(gpu, x + col - 1, y + row_index - 1, colors.accent)
      elseif code == "D" then pixel(gpu, x + col - 1, y + row_index - 1, colors.danger) end
    end
  end
  return true
end

function M.kinds()
  return { "default", "click", "text", "drag", "denied", "loading" }
end

return M
