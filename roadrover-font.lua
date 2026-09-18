local font = {
  cellWidth = 4,
  cellHeight = 6
}

local glyphs = {
  [" "] = "000000000000000",
  ["0"] = "111101101101111",
  ["1"] = "010110010010111",
  ["2"] = "110001111100111",
  ["3"] = "110001111001110",
  ["4"] = "101101111001001",
  ["5"] = "111100110001110",
  ["6"] = "011100111101111",
  ["7"] = "111001010010010",
  ["8"] = "111101111101111",
  ["9"] = "111101111001110",
  ["A"] = "010101111101101",
  ["B"] = "110101110101110",
  ["C"] = "011100100100011",
  ["D"] = "110101101101110",
  ["E"] = "111100110100111",
  ["F"] = "111100110100100",
  ["G"] = "011100101101011",
  ["H"] = "101101111101101",
  ["I"] = "111010010010111",
  ["J"] = "001001001101010",
  ["K"] = "101101110101101",
  ["L"] = "100100100100111",
  ["M"] = "101111111101101",
  ["N"] = "101111111111101",
  ["O"] = "010101101101010",
  ["P"] = "110101110100100",
  ["Q"] = "010101101111011",
  ["R"] = "110101110101101",
  ["S"] = "011100010001110",
  ["T"] = "111010010010010",
  ["U"] = "101101101101111",
  ["V"] = "101101101101010",
  ["W"] = "101101111111101",
  ["X"] = "101101010101101",
  ["Y"] = "101101010010010",
  ["Z"] = "111001010100111",
  ["."] = "000000000000010",
  [","] = "000000000010100",
  [":"] = "000010000010000",
  [";"] = "000010000010100",
  ["!"] = "010010010000010",
  ["?"] = "110001010000010",
  ["-"] = "000000111000000",
  ["_"] = "000000000000111",
  ["+"] = "000010111010000",
  ["="] = "000111000111000",
  ["/"] = "001001010100100",
  ["\\"] = "100100010001001",
  ["<"] = "001010100010001",
  [">"] = "100010001010100",
  ["("] = "001010010010001",
  [")"] = "100010010010100",
  ["["] = "011010010010011",
  ["]"] = "110010010010110",
  ["|"] = "010010010010010",
  ["'"] = "010010000000000",
  ['"'] = "101101000000000",
  ["#"] = "101111101111101",
  ["*"] = "000101010101000",
  ["%"] = "101001010100101",
  ["$"] = "010111110011010",
  ["@"]= "111101111100011",
  ["&"] = "010101010101011",
  ["^"] = "010101000000000",
  ["~"] = "000011110000000",
  ["`"] = "100010000000000"
}

font.patterns = glyphs

local function glyphFor(character)
  if character:match("%l") then character = character:upper() end
  return glyphs[character] or glyphs["?"]
end

local function bitSet(value, bit)
  return math.floor(value / (2 ^ bit)) % 2 == 1
end

local function drawSextant(fill, x, y, value, rgb)
  local columnWidth = math.max(1, math.floor(font.cellWidth / 2))
  local rowHeight = math.max(1, math.floor(font.cellHeight / 3))
  for bit = 0, 4 do
    if bitSet(value, bit) then
      local column = bit % 2
      local row = math.floor(bit / 2)
      fill(x + column * columnWidth, y + row * rowHeight, columnWidth, rowHeight, rgb)
    end
  end
end

function font.measure(text)
  return #tostring(text or "") * font.cellWidth
end

function font.drawGlyph(fill, x, y, character, rgb)
  local byte = string.byte(character)
  if byte and byte >= 128 and byte <= 159 then
    drawSextant(fill, x, y, byte - 128, rgb)
    return true
  end

  local pattern = glyphFor(character)
  for row = 0, 4 do
    local line = pattern:sub(row * 3 + 1, row * 3 + 3)
    local column = 1
    while column <= 3 do
      if line:sub(column, column) == "1" then
        local finish = column
        while finish < 3 and line:sub(finish + 1, finish + 1) == "1" do finish = finish + 1 end
        fill(x + column - 1, y + row, finish - column + 1, 1, rgb)
        column = finish + 1
      else
        column = column + 1
      end
    end
  end
  return true
end

function font.drawText(fill, x, y, text, rgb, maxWidth)
  text = tostring(text or "")
  local available = math.max(0, math.floor(tonumber(maxWidth) or 0))
  local count = math.min(#text, math.floor(available / font.cellWidth))
  for index = 1, count do
    font.drawGlyph(fill, x + (index - 1) * font.cellWidth, y, text:sub(index, index), rgb)
  end
  return true
end

return font
