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
    cellHeight = 9,
    fontHeight = 8,
    fontSize = 8,
    offsetX = 1,
    offsetY = 1,
    lines = {},
    renderedLines = {},
    dirty = true
  }
  local gpuTerminal
  local compactFont
  local hdOverlays = {}
  local lastOverlaySignature = ""
  local nativeMap
  local nativeDashboard
  local lastNativeFrame = ""

  local function configuredDensity()
    local direct = tonumber(_G.ROADROVER_HD_DENSITY)
    if direct then return direct end
    local base = tostring(context.scriptDir or "")
    local path = fs.combine(base ~= "" and base or ".", "system/display-density.txt")
    if not fs.exists(path) or fs.isDir(path) then return 1080 end
    local handle = fs.open(path, "r")
    if not handle then return 1080 end
    local value = tonumber(handle.readAll())
    handle.close()
    if not value or value <= 256 then return 1080 end
    return value
  end

  do
    local base = tostring(context.scriptDir or "")
    local path = base ~= "" and fs.combine(base, "roadrover-font.lua") or "roadrover-font.lua"
    if fs.exists(path) then
      local loaded, library = pcall(dofile, path)
      if loaded and type(library) == "table" and type(library.drawText) == "function" then compactFont = library end
    end
  end

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
    if compactFont and type(compactFont.measure) == "function" then return compactFont.measure(text) end
    return #text * terminalState.cellWidth
  end

  local function drawTextPixels(x, y, text, rgb, maxWidth)
    local gpu = car.devices.gpu
    if not gpu or type(gpu.drawText) ~= "function" then return false end
    x = math.floor(tonumber(x) or 1)
    y = math.floor(tonumber(y) or 1)
    if x < 1 or y < 1 or x > (tonumber(car.hd.width) or 0) or y + terminalState.fontHeight - 1 > (tonumber(car.hd.height) or 0) then
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
    if ok then return true end
    if compactFont then return compactFont.drawText(fillPixels, x, y, text, rgb, maxWidth) end
    car.hd.error = tostring(err)
    return false
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

  local function fillRoundedPixels(x, y, width, height, radius, rgb, clipWidth)
    width = math.floor(tonumber(width) or 0)
    height = math.floor(tonumber(height) or 0)
    if width <= 0 or height <= 0 then return false end
    radius = clip(tonumber(radius) or 0, 0, math.floor(math.min(width, height) / 2))
    local clipRight = x + width - 1
    if clipWidth ~= nil then
      clipRight = math.min(clipRight, x + math.max(0, math.floor(clipWidth)) - 1)
    end
    if clipRight < x then return true end

    local function span(spanX, spanY, spanWidth, spanHeight)
      spanWidth = math.min(spanWidth, clipRight - spanX + 1)
      if spanWidth <= 0 or spanHeight <= 0 then return true end
      return fillPixels(spanX, spanY, spanWidth, spanHeight, rgb)
    end

    if radius < 2 or width < 5 or height < 3 then
      return span(x, y, width, height)
    end

    local ok = span(x + radius, y, width - radius * 2, 1)
    if height > 2 then ok = span(x + 1, y + 1, width - 2, height - 2) and ok end
    if height > radius * 2 then ok = span(x, y + radius, width, height - radius * 2) and ok end
    ok = span(x + radius, y + height - 1, width - radius * 2, 1) and ok
    return ok
  end

  local function overlaySignature()
    local parts = {}
    for index = 1, #hdOverlays do
      local overlay = hdOverlays[index]
      parts[#parts + 1] = table.concat({
        overlay.x, overlay.y, overlay.width, overlay.height,
        overlay.line1 or "", overlay.line2 or "",
        string.format("%.3f", tonumber(overlay.progress) or 0),
        overlay.activeBg, overlay.inactiveBg, overlay.activeFg, overlay.inactiveFg
      }, ":")
    end
    return table.concat(parts, "|")
  end

  local function renderRoundedButton(overlay)
    local pixelX = cellPixelX(overlay.x) + 1
    local pixelY = cellPixelY(overlay.y)
    local pixelWidth = overlay.width * terminalState.cellWidth - 2
    local pixelHeight = overlay.height * terminalState.cellHeight - 1
    if pixelWidth <= 0 or pixelHeight <= 0 then return true end

    local radius = math.min(4, math.floor(pixelHeight / 2), math.floor(pixelWidth / 2))
    local progress = math.max(0, math.min(1, tonumber(overlay.progress) or 0))
    local ok = fillRoundedPixels(pixelX, pixelY, pixelWidth, pixelHeight, radius, colorRGB(overlay.inactiveBg))
    if progress > 0 then
      ok = fillRoundedPixels(pixelX, pixelY, pixelWidth, pixelHeight, radius, colorRGB(overlay.activeBg),
        math.floor(pixelWidth * progress + 0.5)) and ok
    end

    local textRGB = colorRGB(progress >= 0.5 and overlay.activeFg or overlay.inactiveFg)
    local labels = {}
    if overlay.line1 and overlay.line1 ~= "" then labels[#labels + 1] = overlay.line1 end
    if overlay.line2 and overlay.line2 ~= "" then labels[#labels + 1] = overlay.line2 end
    local totalHeight = #labels * terminalState.fontHeight
    local textY = pixelY + math.max(0, math.floor((pixelHeight - totalHeight) / 2))
    for index = 1, #labels do
      local label = labels[index]
      local width = textLength(label)
      local textX = pixelX + math.max(0, math.floor((pixelWidth - width) / 2))
      ok = drawTextPixels(textX, textY + (index - 1) * terminalState.fontHeight, label, textRGB,
        math.max(1, pixelWidth - (textX - pixelX))) and ok
    end
    return ok
  end

  local function renderOverlays()
    local ok = true
    for index = 1, #hdOverlays do
      ok = renderRoundedButton(hdOverlays[index]) and ok
    end
    return ok
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
    if not terminalState.dirty then return true, false end
    local changed = false
    for y = 1, terminalState.height do
      local line = terminalState.lines[y] or blankLine()
      local previous = terminalState.renderedLines[y]
      if not previous or previous[1] ~= line[1] or previous[2] ~= line[2] or previous[3] ~= line[3] then
        changed = true
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
        terminalState.renderedLines[y] = { line[1], line[2], line[3] }
      end
    end
    terminalState.dirty = false
    return car.hd.error == nil, changed
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
    local hdProfile
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
      if type(gpu.getHDProfile) == "function" then
        local profileOK, profile = pcall(gpu.getHDProfile)
        if profileOK and type(profile) == "table" then hdProfile = profile end
      end
      local requestedDensity = configuredDensity()
      local maximumDensity = hdProfile and tonumber(hdProfile.maximumPixelDensity) or requestedDensity
      local targetDensity = math.floor(math.max(64, math.min(requestedDensity, maximumDensity or requestedDensity)))
      if type(gpu.setSize) == "function" then
        local candidates = { targetDensity, 160, 128, 96, 64 }
        local applied = false
        for index = 1, #candidates do
          local density = candidates[index]
          if density <= targetDensity or index == 1 then
            local densityOK, result = pcall(gpu.setSize, density)
            if densityOK and result ~= false then
              applied = true
              break
            end
          end
        end
        if not applied then error("GPU rejected every HD density", 0) end
      end
      if type(gpu.setFont) == "function" then pcall(gpu.setFont, "ascii") end
      if sleep then sleep(0.2) end
      if type(gpu.getSize) == "function" then
        local width, height = gpu.getSize()
        width, height = tonumber(width), tonumber(height)
        if width and height and width > 0 and height > 0 then
          detectedWidth, detectedHeight = width, height
        end
      end
      if type(gpu.getHDProfile) == "function" then
        local profileOK, profile = pcall(gpu.getHDProfile)
        if profileOK and type(profile) == "table" then hdProfile = profile end
      end
    end)
    if not ok then
      car.hd.ready = false
      car.hd.error = tostring(setupError)
      return false
    end
    car.hd.width = math.floor(detectedWidth)
    car.hd.height = math.floor(detectedHeight)
    car.hd.profile = hdProfile
    car.hd.pixelDensity = hdProfile and tonumber(hdProfile.pixelDensity) or nil
    car.hd.font = "ascii"
    local density = tonumber(car.hd.pixelDensity) or 192
    local uiScale = math.max(1, density / 192)
    terminalState.cellWidth = math.max(6, math.floor(6 * uiScale + 0.5))
    terminalState.cellHeight = math.max(9, math.floor(9 * uiScale + 0.5))
    terminalState.fontHeight = math.max(8, math.floor(7 * uiScale + 0.5))
    terminalState.fontSize = terminalState.fontHeight
    terminalState.width = math.max(1, math.floor(car.hd.width / terminalState.cellWidth))
    terminalState.height = math.max(1, math.floor(car.hd.height / terminalState.cellHeight))
    terminalState.offsetX = math.floor((car.hd.width - terminalState.width * terminalState.cellWidth) / 2) + 1
    terminalState.offsetY = math.floor((car.hd.height - terminalState.height * terminalState.cellHeight) / 2) + 1
    terminalState.cursorX = 1
    terminalState.cursorY = 1
    terminalState.renderedLines = {}
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

  function car.clearHDOverlays()
    hdOverlays = {}
    nativeMap = nil
    nativeDashboard = nil
  end

  function car.queueHDDashboard(data)
    if not car.hd.ready or type(data) ~= "table" then return false end
    local gpu = car.devices.gpu
    if not gpu or type(gpu.renderRoadRoverFrame) ~= "function" then return false end
    nativeDashboard = data
    return true
  end

  function car.queueHDMap(win, x, y, width, height, data)
    if not car.hd.ready or type(data) ~= "table" then return false end
    local gpu = car.devices.gpu
    if not gpu or type(gpu.renderRoadRoverFrame) ~= "function" then return false end
    local originX, originY = 1, 1
    if win and type(win.getPosition) == "function" then
      local positionOK, windowX, windowY = pcall(win.getPosition)
      if positionOK and tonumber(windowX) and tonumber(windowY) then
        originX, originY = math.floor(windowX), math.floor(windowY)
      end
    end
    local globalX = originX + math.floor(tonumber(x) or 1) - 1
    local globalY = originY + math.floor(tonumber(y) or 1) - 1
    nativeMap = data
    nativeMap.x = cellPixelX(globalX) - 1
    nativeMap.y = cellPixelY(globalY) - 1
    nativeMap.width = math.max(1, math.min(
      math.floor(tonumber(width) or 1) * terminalState.cellWidth,
      car.hd.width - nativeMap.x
    ))
    nativeMap.height = math.max(1, math.min(
      math.floor(tonumber(height) or 1) * terminalState.cellHeight,
      car.hd.height - nativeMap.y
    ))
    return true
  end

  function car.queueHDRoundedButton(win, x, y, width, height, line1, line2, progress,
      activeBg, inactiveBg, activeFg, inactiveFg)
    if not car.hd.ready then return false end
    local originX, originY = 1, 1
    if win and type(win.getPosition) == "function" then
      local positionOK, windowX, windowY = pcall(win.getPosition)
      if positionOK and tonumber(windowX) and tonumber(windowY) then
        originX, originY = math.floor(windowX), math.floor(windowY)
      end
    end
    x = math.floor(tonumber(x) or 1)
    y = math.floor(tonumber(y) or 1)
    width = math.floor(tonumber(width) or 0)
    height = math.floor(tonumber(height) or 0)
    if width < 1 or height < 1 then return false end
    hdOverlays[#hdOverlays + 1] = {
      x = originX + x - 1,
      y = originY + y - 1,
      width = width,
      height = height,
      line1 = tostring(line1 or ""),
      line2 = line2 and tostring(line2) or nil,
      progress = tonumber(progress) or 0,
      activeBg = tonumber(activeBg) or colors.white,
      inactiveBg = tonumber(inactiveBg) or colors.black,
      activeFg = tonumber(activeFg) or colors.black,
      inactiveFg = tonumber(inactiveFg) or colors.white
    }
    return true
  end

  local function buildNativeFrame()
    local lines = {}
    for y = 1, terminalState.height do
      local line = terminalState.lines[y] or blankLine()
      lines[y] = { text = line[1], foreground = line[2], background = line[3] }
    end
    local buttons = {}
    for index = 1, #hdOverlays do
      local overlay = hdOverlays[index]
      buttons[index] = {
        x = cellPixelX(overlay.x),
        y = cellPixelY(overlay.y) - 1,
        width = math.max(1, overlay.width * terminalState.cellWidth - 2),
        height = math.max(1, overlay.height * terminalState.cellHeight - 1),
        line1 = overlay.line1,
        line2 = overlay.line2,
        progress = overlay.progress,
        activeBg = overlay.activeBg,
        inactiveBg = overlay.inactiveBg,
        activeFg = overlay.activeFg,
        inactiveFg = overlay.inactiveFg
      }
    end
    return {
      cellWidth = terminalState.cellWidth,
      cellHeight = terminalState.cellHeight,
      fontSize = terminalState.fontSize,
      offsetX = terminalState.offsetX,
      offsetY = terminalState.offsetY,
      lines = lines,
      map = nativeMap,
      dashboard = nativeDashboard,
      buttons = buttons
    }
  end

  function car.flushHD()
    if not car.hd.ready or not car.devices.gpu then return false end
    car.hd.error = nil
    if type(car.devices.gpu.renderRoadRoverFrame) == "function"
      and textutils and type(textutils.serializeJSON) == "function" then
      local serializedOK, frame = pcall(textutils.serializeJSON, buildNativeFrame())
      if serializedOK and type(frame) == "string" then
        if frame == lastNativeFrame then
          hdOverlays = {}
          nativeMap = nil
          nativeDashboard = nil
          return true
        end
        local renderOK, result = pcall(car.devices.gpu.renderRoadRoverFrame, frame)
        if renderOK and result ~= false then
          lastNativeFrame = frame
          terminalState.dirty = false
          hdOverlays = {}
          nativeMap = nil
          nativeDashboard = nil
          return true
        end
        car.hd.error = tostring(result)
      elseif not serializedOK then
        car.hd.error = tostring(frame)
      end
    end
    local signature = overlaySignature()
    local overlaysChanged = signature ~= lastOverlaySignature
    if overlaysChanged then
      terminalState.renderedLines = {}
      terminalState.dirty = true
    end
    local rendered, changed = renderBuffer()
    if not rendered then return false end
    if changed or overlaysChanged then
      if not renderOverlays() then return false end
    end
    hdOverlays = {}
    nativeDashboard = nil
    lastOverlaySignature = signature
    if not changed and not overlaysChanged then return true end
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

  function car.hdMouseToTermPoint(a, b, c, d)
    if type(a) == "string" and type(b) == "number" and type(c) == "number" then
      return car.hdToTermPoint(b, c)
    end
    if type(a) == "number" and type(b) == "number" and type(c) == "number" then
      return car.hdToTermPoint(b, c)
    end
    return car.hdToTermPoint(a, b, c, d)
  end

  function car.drawHDError(message)
    if not car.devices.gpu or not car.hd.width or not car.hd.height then return false end
    fillPixels(1, 1, car.hd.width, car.hd.height, 0xF0F0F0)
    local text = tostring(message or car.hd.error or "Display error"):gsub("\r", "")
    local title = "ROADROVER OS"
    local titleWidth = textLength(title)
    drawTextPixels(math.max(1, math.floor((car.hd.width - titleWidth) / 2) + 1), math.max(1, math.floor(car.hd.height / 2) - 12), title, 0x111111, titleWidth)
    local maxWidth = math.max(8, car.hd.width - 12)
    local maxChars = math.max(8, math.floor(maxWidth / math.max(1, terminalState.cellWidth)))
    local lines = {}
    for sourceLine in (text .. "\n"):gmatch("(.-)\n") do
      local offset = 1
      repeat
        lines[#lines + 1] = sourceLine:sub(offset, offset + maxChars - 1)
        offset = offset + maxChars
      until offset > #sourceLine or #lines >= 6
      if #lines >= 6 then break end
    end
    local startY = math.max(1, math.floor(car.hd.height / 2) + 4)
    for index = 1, #lines do
      drawTextPixels(7, startY + (index - 1) * terminalState.cellHeight, lines[index], 0xCC4C4C, maxWidth)
    end
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
