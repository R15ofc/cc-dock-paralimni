local scriptPath = shell and shell.getRunningProgram and shell.getRunningProgram() or ""
local scriptDir = scriptPath ~= "" and fs.getDir(scriptPath) or ""
local fontPath = scriptDir ~= "" and fs.combine(scriptDir, "roadrover-font.lua") or "roadrover-font.lua"
local smallFont = dofile(fontPath)

local bigfont = {
  height = 4
}

local HEX = {
  [colors.white] = "0",
  [colors.orange] = "1",
  [colors.magenta] = "2",
  [colors.lightBlue] = "3",
  [colors.yellow] = "4",
  [colors.lime] = "5",
  [colors.pink] = "6",
  [colors.gray] = "7",
  [colors.lightGray] = "8",
  [colors.cyan] = "9",
  [colors.purple] = "a",
  [colors.blue] = "b",
  [colors.brown] = "c",
  [colors.green] = "d",
  [colors.red] = "e",
  [colors.black] = "f"
}

local function glyph(character)
  if character:match("%l") then character = character:upper() end
  return smallFont.patterns[character] or smallFont.patterns["?"]
end

local function sourcePixel(pattern, pixelX, pixelY)
  if pixelX < 1 or pixelX > 6 or pixelY < 1 or pixelY > 12 then return false end
  local sourceX = math.floor((pixelX - 1) * 4 / 6) + 1
  local sourceY = math.floor((pixelY - 1) * 6 / 12) + 1
  if type(pattern) == "table" then
    local row = pattern[sourceY]
    return type(row) == "string" and row:sub(sourceX, sourceX) == "1"
  end
  if type(pattern) == "string" then
    local index = (sourceY - 1) * 4 + sourceX
    return pattern:sub(index, index) == "1"
  end
  return false
end

local function encodeCell(pattern, cellX, cellY, foreground, background)
  local mask = 0
  local bottomRight = false
  for row = 0, 2 do
    for column = 0, 1 do
      local enabled = sourcePixel(pattern, cellX * 2 + column + 1, cellY * 3 + row + 1)
      local bit = row * 2 + column
      if bit == 5 then
        bottomRight = enabled
      elseif enabled then
        mask = mask + 2 ^ bit
      end
    end
  end
  if bottomRight then
    mask = 31 - mask
    foreground, background = background, foreground
  end
  return string.char(128 + mask), foreground, background
end

local function render(win, text, x, y)
  text = tostring(text or "")
  x = math.floor(tonumber(x) or 1)
  y = math.floor(tonumber(y) or 1)
  local foreground = HEX[win.getTextColor()] or "0"
  local background = HEX[win.getBackgroundColor()] or "f"

  for cellY = 0, bigfont.height - 1 do
    local chars, fronts, backs = {}, {}, {}
    for index = 1, #text do
      local pattern = glyph(text:sub(index, index))
      for cellX = 0, 2 do
        local character, front, back = encodeCell(pattern, cellX, cellY, foreground, background)
        chars[#chars + 1] = character
        fronts[#fronts + 1] = front
        backs[#backs + 1] = back
      end
      if index < #text then
        chars[#chars + 1] = " "
        fronts[#fronts + 1] = foreground
        backs[#backs + 1] = background
      end
    end
    win.setCursorPos(x, y + cellY)
    win.blit(table.concat(chars), table.concat(fronts), table.concat(backs))
  end
end

function bigfont.width(text)
  local length = #tostring(text or "")
  if length == 0 then return 0 end
  return length * 4 - 1
end

function bigfont.writeOn(win, size, text, x, y)
  render(win, text, x, y)
  return bigfont.height
end

function bigfont.bigWrite(text)
  local win = term.current()
  local x, y = win.getCursorPos()
  render(win, text, x, y)
  win.setCursorPos(x + bigfont.width(text), y)
  return bigfont.height
end

return bigfont
