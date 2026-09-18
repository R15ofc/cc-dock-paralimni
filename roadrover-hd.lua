return function(car, context)
  local COLOR_RGB = {
    [1] = 0xF0F0F0,
    [2] = 0xF2B233,
    [4] = 0xE57FD8,
    [8] = 0x99B2F2,
    [16] = 0xDED83D,
    [32] = 0x7FCC19,
    [64] = 0xF2B2CC,
    [128] = 0x4C4C4C,
    [256] = 0x999999,
    [512] = 0x4C99B2,
    [1024] = 0xB266E5,
    [2048] = 0x3366CC,
    [4096] = 0x7F664C,
    [8192] = 0x57A64E,
    [16384] = 0xCC4C4C,
    [32768] = 0x111111
  }
  local HEX = "0123456789abcdef"
  local COLOR_HEX = {}
  for index = 1, #HEX do COLOR_HEX[2 ^ (index - 1)] = HEX:sub(index, index) end
  local terminalState = {
    cursorX = 1,
    cursorY = 1,
    cursorBlink = false,
    textColor = colors.white,
    backgroundColor = colors.black,
    palette = {},
    width = 63,
    height = 24,
    cellWidth = 6,
    cellHeight = 8,
    offsetX = 1,
    offsetY = 1,
    lines = {},
    dirty = true
  }
  local gpuTerminal

  for color, rgb in pairs(COLOR_RGB) do terminalState.palette[color] = rgb end

  local function signedARGB(rgb)
    rgb = math.floor(tonumber(rgb) or 0) % 0x1000000
    local value = 0xFF000000 + rgb
    if value > 0x7FFFFFFF then value = value - 0x100000000 end
    return value
  end

  local function colorRGB(color)
    return terminalState.palette[color] or COLOR_RGB[color] or 0x000000
  end

  local function decodeBlitColor(value, fallback)
    local index = HEX:find(tostring(value or ""):lower(), 1, true)
    if not index then return fallback end
    return 2 ^ (index - 1)
  end

  local function clip(value, minimum, maximum)
    value = math.floor(tonumber(value) or minimum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
  end

  local function fillPixels(x, y, width, height, rgb)
    local gpu = car.devices.gpu
    if not gpu or type(gpu.filledRectangle) ~= "function" then return false end
    x = math.floor(tonumber(x) or 1)
    y = math.floor(tonumber(y) or 1)
    width = math.floor(tonumber(width) or 0)
    height = math.floor(tonumber(height) or 0)
    if x < 1 then width = width - (1 - x); x = 1 end
    if y < 1 then height = height - (1 - y); y = 1 end
    width = math.min(width, (tonumber(car.hd.width) or 0) - x + 1)
    height = math.min(height, (tonumber(car.hd.height) or 0) - y + 1)
    if width <= 0 or height <= 0 then return false end
    local ok, err = pcall(gpu.filledRectangle, x, y, width, height, signedARGB(rgb))
    if not ok then car.hd.error = tostring(err) end
    return ok
  end

  local function textLength(text)
    local gpu = car.devices.gpu
    text = tostring(text or "")
    if gpu and type(gpu.getTextLength) == "function" then
      local ok, width = pcall(gpu.getTextLength, text, 1, 1)
      if ok and tonumber(width) then return math.max(0, math.floor(width)) end
    end
    return #text * terminalState.cellWidth
  end

  local function drawTextPixels(x, y, text, rgb, maxWidth)
    local gpu = car.devices.gpu
    if not gpu or type(gpu.drawText) ~= "function" then return false end
    x = math.floor(tonumber(x) or 1)
    y = math.floor(tonumber(y) or 1)
    if x < 1 or y < 1 or x > (tonumber(car.hd.width) or 0) or y + terminalState.cellHeight - 1 > (tonumber(car.hd.height) or 0) then
      return false
    end
    text = tostring(text or "")
    maxWidth = math.min(
      math.max(0, math.floor(tonumber(maxWidth) or 0)),
      math.max(0, (tonumber(car.hd.width) or 0) - x + 1)
    )
    while #text > 0 and textLength(text) > maxWidth do text = text:sub(1, -2) end
    if text == "" or maxWidth <= 0 then return true end
    local ok, err = pcall(gpu.drawText, x, y, text, signedARGB(rgb), -1, 1, 1)
    if not ok then car.hd.error = tostring(err) end
    return ok
  end

  local function cellPixelX(x)
    return terminalState.offsetX + (x - 1) * terminalState.cellWidth
  end

  local function cellPixelY(y)
    return terminalState.offsetY + (y - 1) * terminalState.cellHeight
  end

  local function clearWith(color)
    fillPixels(1, 1, car.hd.width, car.hd.height, colorRGB(color))
  end

  local function blankLine()
    return {
      (" "):rep(terminalState.width),
      (COLOR_HEX[terminalState.textColor] or "0"):rep(terminalState.width),
      (COLOR_HEX[terminalState.backgroundColor] or "f"):rep(terminalState.width)
    }
  end

  local function resetBuffer()
    terminalState.lines = {}
    for y = 1, terminalState.height do terminalState.lines[y] = blankLine() end
    terminalState.dirty = true
  end

  local function writeBuffer(x, y, text, foreground, background)
    text = tostring(text or "")
    foreground = tostring(foreground or "")
    background = tostring(background or "")
    if text == "" or y < 1 or y > terminalState.height then return end
    local sourceStart = 1
    if x < 1 then
      sourceStart = 2 - x
      x = 1
    end
    if x > terminalState.width or sourceStart > #text then return end
    local count = math.min(#text - sourceStart + 1, terminalState.width - x + 1)
    if count <= 0 then return end
    local sourceEnd = sourceStart + count - 1
    local targetEnd = x + count - 1
    local line = terminalState.lines[y] or blankLine()
    local prefix = x > 1 and line[1]:sub(1, x - 1) or ""
    local suffix = targetEnd < terminalState.width and line[1]:sub(targetEnd + 1) or ""
    line[1] = prefix .. text:sub(sourceStart, sourceEnd) .. suffix
    prefix = x > 1 and line[2]:sub(1, x - 1) or ""
    suffix = targetEnd < terminalState.width and line[2]:sub(targetEnd + 1) or ""
    line[2] = prefix .. foreground:sub(sourceStart, sourceEnd) .. suffix
    prefix = x > 1 and line[3]:sub(1, x - 1) or ""
    suffix = targetEnd < terminalState.width and line[3]:sub(targetEnd + 1) or ""
    line[3] = prefix .. background:sub(sourceStart, sourceEnd) .. suffix
    terminalState.lines[y] = line
    terminalState.dirty = true
  end

  local function renderBuffer()
    if not terminalState.dirty then return true end
    for y = 1, terminalState.height do
      local line = terminalState.lines[y] or blankLine()
      local pixelY = cellPixelY(y)
      local start = 1
      while start <= terminalState.width do
        local bg = line[3]:sub(start, start)
        local finish = start
        while finish < terminalState.width and line[3]:sub(finish + 1, finish + 1) == bg do
          finish = finish + 1
        end
        local pixelX = cellPixelX(start)
        local pixelWidth = (finish - start + 1) * terminalState.cellWidth
        if finish == terminalState.width then pixelWidth = car.hd.width - pixelX + 1 end
        fillPixels(pixelX, pixelY, pixelWidth, terminalState.cellHeight, colorRGB(decodeBlitColor(bg, colors.black)))
        start = finish + 1
      end

      start = 1
      while start <= terminalState.width do
        if line[1]:sub(start, start) == " " then
          start = start + 1
        else
          local fg = line[2]:sub(start, start)
          local finish = start
          while finish < terminalState.width
            and line[1]:sub(finish + 1, finish + 1) ~= " "
            and line[2]:sub(finish + 1, finish + 1) == fg do
            finish = finish + 1
          end
          local text = line[1]:sub(start, finish)
          local pixelX = cellPixelX(start)
          local pixelWidth = (finish - start + 1) * terminalState.cellWidth
          if finish == terminalState.width then pixelWidth = car.hd.width - pixelX + 1 end
          drawTextPixels(pixelX, pixelY, text, colorRGB(decodeBlitColor(fg, colors.white)), pixelWidth)
          start = finish + 1
        end
      end
    end
    terminalState.dirty = false
    return car.hd.error == nil
  end

  local function makeTerminal()
    local object = {}

    function object.write(text)
      text = tostring(text or "")
      writeBuffer(
        terminalState.cursorX,
        terminalState.cursorY,
        text,
        (COLOR_HEX[terminalState.textColor] or "0"):rep(#text),
        (COLOR_HEX[terminalState.backgroundColor] or "f"):rep(#text)
      )
      terminalState.cursorX = terminalState.cursorX + #text
    end

    function object.blit(text, foreground, background)
      text = tostring(text or "")
      foreground = tostring(foreground or "")
      background = tostring(background or "")
      if #foreground < #text then foreground = foreground .. (COLOR_HEX[terminalState.textColor] or "0"):rep(#text - #foreground) end
      if #background < #text then background = background .. (COLOR_HEX[terminalState.backgroundColor] or "f"):rep(#text - #background) end
      writeBuffer(terminalState.cursorX, terminalState.cursorY, text, foreground, background)
      terminalState.cursorX = terminalState.cursorX + #text
    end

    function object.clear()
      resetBuffer()
    end

    function object.clearLine()
      if terminalState.cursorY >= 1 and terminalState.cursorY <= terminalState.height then
        terminalState.lines[terminalState.cursorY] = blankLine()
        terminalState.dirty = true
      end
    end

    function object.getCursorPos()
      return terminalState.cursorX, terminalState.cursorY
    end

    function object.setCursorPos(x, y)
      terminalState.cursorX = math.floor(tonumber(x) or 1)
      terminalState.cursorY = math.floor(tonumber(y) or 1)
    end

    function object.getCursorBlink()
      return terminalState.cursorBlink
    end

    function object.setCursorBlink(value)
      terminalState.cursorBlink = value and true or false
    end

    function object.isColor()
      return true
    end

    object.isColour = object.isColor

    function object.getSize()
      return terminalState.width, terminalState.height
    end

    function object.scroll(offset)
      offset = math.floor(tonumber(offset) or 0)
      if offset > 0 then
        for y = 1, terminalState.height do
          terminalState.lines[y] = terminalState.lines[y + offset] or blankLine()
        end
      elseif offset < 0 then
        for y = terminalState.height, 1, -1 do
          terminalState.lines[y] = terminalState.lines[y + offset] or blankLine()
        end
      end
      terminalState.dirty = true
    end

    function object.setTextColor(color)
      terminalState.textColor = tonumber(color) or colors.white
    end

    object.setTextColour = object.setTextColor

    function object.getTextColor()
      return terminalState.textColor
    end

    object.getTextColour = object.getTextColor

    function object.setBackgroundColor(color)
      terminalState.backgroundColor = tonumber(color) or colors.black
    end

    object.setBackgroundColour = object.setBackgroundColor

    function object.getBackgroundColor()
      return terminalState.backgroundColor
    end

    object.getBackgroundColour = object.getBackgroundColor

    function object.setPaletteColor(color, first, second, third)
      color = tonumber(color)
      if not color then return end
      if second ~= nil and third ~= nil then
        local red = clip((tonumber(first) or 0) * 255, 0, 255)
        local green = clip((tonumber(second) or 0) * 255, 0, 255)
        local blue = clip((tonumber(third) or 0) * 255, 0, 255)
        terminalState.palette[color] = red * 0x10000 + green * 0x100 + blue
      else
        terminalState.palette[color] = math.floor(tonumber(first) or 0) % 0x1000000
      end
    end

    object.setPaletteColour = object.setPaletteColor

    function object.getPaletteColor(color)
      local rgb = colorRGB(tonumber(color))
      return math.floor(rgb / 0x10000) % 0x100 / 255,
        math.floor(rgb / 0x100) % 0x100 / 255,
        rgb % 0x100 / 255
    end

    object.getPaletteColour = object.getPaletteColor

    return object
  end

  function car.setupHD(force)
    local gpu = car.devices.gpu
    if not gpu then
      car.hd.ready = false
      car.hd.gpuName = nil
      car.hd.error = "Tom GPU not found"
      return false
    end
    if not force and car.hd.ready and car.hd.gpuName == car.devices.gpuName then return true end
    local detectedWidth, detectedHeight
    local ok, setupError = pcall(function()
      for _ = 1, 8 do
        if type(gpu.refreshSize) == "function" then gpu.refreshSize() end
        if sleep then sleep(0.15) end
        if type(gpu.getSize) == "function" then
          local width, height = gpu.getSize()
          width, height = tonumber(width), tonumber(height)
          if width and height and width > 0 and height > 0 then
            detectedWidth, detectedHeight = width, height
            break
          end
        end
      end
      if not detectedWidth then error("GPU monitor size is 0x0; check GPU cable and monitor", 0) end
      if type(gpu.setSize) == "function" then gpu.setSize(64) end
      if sleep then sleep(0.2) end
      if type(gpu.getSize) == "function" then
        local width, height = gpu.getSize()
        width, height = tonumber(width), tonumber(height)
        if width and height and width > 0 and height > 0 then
          detectedWidth, detectedHeight = width, height
        end
      end
    end)
    if not ok then
      car.hd.ready = false
      car.hd.error = tostring(setupError)
      return false
    end
    car.hd.width = math.floor(detectedWidth)
    car.hd.height = math.floor(detectedHeight)
    terminalState.cellWidth = 6
    terminalState.cellHeight = 8
    terminalState.width = math.max(1, math.floor(car.hd.width / terminalState.cellWidth))
    terminalState.height = math.max(1, math.floor(car.hd.height / terminalState.cellHeight))
    terminalState.offsetX = math.floor((car.hd.width - terminalState.width * terminalState.cellWidth) / 2) + 1
    terminalState.offsetY = math.floor((car.hd.height - terminalState.height * terminalState.cellHeight) / 2) + 1
    terminalState.cursorX = 1
    terminalState.cursorY = 1
    car.hd.gpuName = car.devices.gpuName
    car.hd.ready = type(gpu.filledRectangle) == "function" and type(gpu.drawText) == "function" and type(gpu.sync) == "function"
    car.hd.error = car.hd.ready and nil or "GPU drawing methods missing"
    if car.hd.ready and not gpuTerminal then gpuTerminal = makeTerminal() end
    if car.hd.ready then resetBuffer() end
    return car.hd.ready
  end

  function car.getHDTerminal()
    if not car.setupHD(false) then return nil end
    return gpuTerminal
  end

  function car.flushHD()
    if not car.hd.ready or not car.devices.gpu then return false end
    car.hd.error = nil
    if not renderBuffer() then return false end
    local ok, err = pcall(car.devices.gpu.sync)
    if not ok then car.hd.error = tostring(err) end
    return ok
  end

  function car.hdToTermPoint(a, b, c, d)
    local pixelX, pixelY
    if type(a) == "number" and type(b) == "number" then
      pixelX, pixelY = a, b
    elseif type(b) == "number" and type(c) == "number" then
      pixelX, pixelY = b, c
    elseif type(c) == "number" and type(d) == "number" then
      pixelX, pixelY = c, d
    end
    if not pixelX or not pixelY then return nil, nil end
    if pixelX < 1 then pixelX = pixelX + 1 end
    if pixelY < 1 then pixelY = pixelY + 1 end
    if pixelX > car.hd.width or pixelY > car.hd.height then return nil, nil end
    local x = math.floor((pixelX - terminalState.offsetX) / terminalState.cellWidth) + 1
    local y = math.floor((pixelY - terminalState.offsetY) / terminalState.cellHeight) + 1
    x = math.min(x, terminalState.width)
    y = math.min(y, terminalState.height)
    if x < 1 or y < 1 then return nil, nil end
    return x, y
  end

  function car.drawHDError(message)
    if not car.devices.gpu or not car.hd.width or not car.hd.height then return false end
    fillPixels(1, 1, car.hd.width, car.hd.height, 0xF0F0F0)
    local text = tostring(message or car.hd.error or "Display error"):gsub("[\r\n]+", " ")
    local title = "ROADROVER OS"
    local titleWidth = textLength(title)
    local bodyWidth = math.min(textLength(text), car.hd.width - 12)
    drawTextPixels(math.max(1, math.floor((car.hd.width - titleWidth) / 2) + 1), math.max(1, math.floor(car.hd.height / 2) - 12), title, 0x111111, titleWidth)
    drawTextPixels(math.max(1, math.floor((car.hd.width - bodyWidth) / 2) + 1), math.max(1, math.floor(car.hd.height / 2) + 4), text, 0xCC4C4C, bodyWidth)
    if car.devices.gpu.sync then pcall(car.devices.gpu.sync) end
    return true
  end

  function car.writeHDError(message)
    if not fs or not fs.open then return false end
    local handle = fs.open("roadrover-hd-error.log", "w")
    if not handle then return false end
    handle.writeLine("RoadRover OS " .. tostring(context.version))
    handle.writeLine("GPU: " .. tostring(car.devices.gpuName or "missing"))
    handle.writeLine("Size: " .. tostring(car.hd.width or "?") .. "x" .. tostring(car.hd.height or "?"))
    handle.writeLine(tostring(message or car.hd.error or "unknown HD error"))
    handle.close()
    return true
  end

  return true
end
