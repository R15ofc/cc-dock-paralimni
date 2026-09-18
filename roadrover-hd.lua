return function(car, context)
  function car.hdColor(color)
    color = math.floor(tonumber(color) or 0)
    if color >= 0 and color <= 16777215 then color = 4278190080 + color end
    if color > 2147483647 then color = color - 4294967296 end
    return color
  end

  function car.setupHD(force)
    local gpu = car.devices.gpu
    if not gpu then
      car.hd.ready = false
      car.hd.gpuName = nil
      return false
    end
    if not force and car.hd.ready and car.hd.gpuName == car.devices.gpuName then return true end
    local ok = pcall(function()
      if gpu.refreshSize then gpu.refreshSize() end
      if gpu.setSize then gpu.setSize(64) end
    end)
    if not ok then
      car.hd.ready = false
      return false
    end
    if sleep then pcall(sleep, force and 0.25 or 0) end
    if gpu.getSize then
      local sizeOK, width, height = pcall(gpu.getSize)
      if sizeOK and tonumber(width) and tonumber(height) then
        car.hd.width = math.max(160, math.floor(width))
        car.hd.height = math.max(96, math.floor(height))
      end
    end
    car.hd.gpuName = car.devices.gpuName
    car.hd.ready = type(gpu.filledRectangle) == "function" and type(gpu.drawText) == "function"
    return car.hd.ready
  end
  
  function car.hdFill(x, y, width, height, color)
    local gpu = car.devices.gpu
    if not gpu or not gpu.filledRectangle then return false end
    x = math.max(0, math.floor(tonumber(x) or 0))
    y = math.max(0, math.floor(tonumber(y) or 0))
    width = math.min(math.floor(tonumber(width) or 0), car.hd.width - x)
    height = math.min(math.floor(tonumber(height) or 0), car.hd.height - y)
    if width <= 0 or height <= 0 then return false end
    local ok, result = pcall(gpu.filledRectangle, x, y, width, height, car.hdColor(color))
    if not ok then car.hd.error = tostring(result) end
    return ok
  end
  
  function car.hdRound(x, y, width, height, radius, color)
    radius = math.max(0, math.min(math.floor(radius or 0), math.floor(math.min(width, height) / 2)))
    if radius <= 1 then return car.hdFill(x, y, width, height, color) end
    car.hdFill(x + radius, y, width - radius * 2, height, color)
    car.hdFill(x, y + radius, width, height - radius * 2, color)
    for offset = 0, radius - 1 do
      local inset = math.floor((radius - offset) * 0.58)
      car.hdFill(x + inset, y + offset, width - inset * 2, 1, color)
      car.hdFill(x + inset, y + height - offset - 1, width - inset * 2, 1, color)
    end
  end
  
  function car.hdOutline(x, y, width, height, color)
    car.hdFill(x + 4, y, width - 8, 1, color)
    car.hdFill(x + 4, y + height - 1, width - 8, 1, color)
    car.hdFill(x, y + 4, 1, height - 8, color)
    car.hdFill(x + width - 1, y + 4, 1, height - 8, color)
    car.hdFill(x + 1, y + 2, 2, 1, color)
    car.hdFill(x + width - 3, y + 2, 2, 1, color)
    car.hdFill(x + 1, y + height - 3, 2, 1, color)
    car.hdFill(x + width - 3, y + height - 3, 2, 1, color)
  end
  
  function car.hdText(x, y, text, color, scale, background)
    local gpu = car.devices.gpu
    if not gpu or not gpu.drawText then return false end
    text = tostring(text or "")
    scale = math.max(1, math.floor(tonumber(scale) or 1))
    local foreground = car.hdColor(color or car.palette.text)
    local backdrop = background == nil and -1 or car.hdColor(background)
    local ok, result = pcall(gpu.drawText, math.floor(x), math.floor(y), text, foreground, backdrop, scale, 0)
    if not ok then ok, result = pcall(gpu.drawText, math.floor(x), math.floor(y), text, foreground, backdrop, scale) end
    if not ok then ok, result = pcall(gpu.drawText, math.floor(x), math.floor(y), text, foreground, backdrop) end
    if not ok then car.hd.error = tostring(result) end
    return ok
  end
  
  function car.hdTextWidth(text, scale)
    return #tostring(text or "") * 6 * math.max(1, math.floor(tonumber(scale) or 1))
  end
  
  function car.hdCenteredText(x, y, width, text, color, scale)
    car.hdText(x + math.floor((width - car.hdTextWidth(text, scale)) / 2), y, text, color, scale)
  end
  
  function car.hdHit(id, x, y, width, height)
    car.hd.hits[#car.hd.hits + 1] = { id = id, x = x, y = y, w = width, h = height }
  end
  
  function car.hdButton(id, x, y, width, height, label, sublabel, active, accent)
    accent = accent or car.palette.blue
    local background = active and accent or car.palette.surfaceRaised
    car.hdRound(x, y, width, height, 5, background)
    if not active then car.hdOutline(x, y, width, height, car.palette.border) end
    local labelY = sublabel and (y + math.max(4, math.floor(height / 2) - 8)) or (y + math.floor((height - 9) / 2))
    car.hdCenteredText(x, labelY, width, tostring(label or ""), active and car.palette.background or car.palette.text, 1)
    if sublabel then
      car.hdCenteredText(x, labelY + 10, width, tostring(sublabel), active and car.palette.background or car.palette.muted, 1)
    end
    if id then car.hdHit(id, x, y, width, height) end
  end
  
  function car.hdModeButton(id, x, y, width, height, label, active)
    local background = active and 0x000000 or car.palette.surfaceRaised
    car.hdRound(x, y, width, height, 5, background)
    car.hdOutline(x, y, width, height, active and car.palette.text or car.palette.border)
    car.hdCenteredText(x, y + math.floor((height - 9) / 2), width, label, car.palette.text, 1)
    car.hdHit(id, x, y, width, height)
  end
  
  function car.hdSpeed()
    local kmh = context.getSpeed() * 3.6
    if context.settings.units == "MP/H" then return kmh * 0.621371, "MPH" end
    if context.settings.units == "B/S" then return context.getSpeed(), "B/S" end
    return kmh, "KM/H"
  end
  
  function car.drawHDNav(navX, top, width, height)
    local items = {
      { "HOME", "home" },
      { "STATS", "stats" },
      { "SET", "settings" },
      { "ABOUT", "about" }
    }
    local gap = 4
    local itemH = math.floor((height - gap * (#items - 1)) / #items)
    for i = 1, #items do
      local y = top + (i - 1) * (itemH + gap)
      local selected = context.tabs[context.getActiveTab()] and context.tabs[context.getActiveTab()].id == items[i][2]
      car.hdButton("tabid:" .. items[i][2], navX, y, width, itemH, items[i][1], nil, selected, car.palette.blue)
    end
  end
  
  function car.drawHDHome(x, y, width, height)
    local speedW = math.max(86, math.floor(width * 0.30))
    local gap = 6
    local modeW = 34
    local modeX = x + speedW + gap
    local actionX = modeX + modeW + gap
    local actionW = width - speedW - modeW - gap * 2
    car.hdRound(x, y, speedW, height, 7, car.palette.surface)
    car.hdText(x + 10, y + 9, "SPEED", car.palette.muted, 1)
    local speed, unit = car.hdSpeed()
    local speedText = tostring(math.floor(speed + 0.5))
    local speedScale = #speedText <= 2 and 4 or 3
    car.hdCenteredText(x, y + 42, speedW, speedText, car.palette.text, speedScale)
    car.hdCenteredText(x, y + 84, speedW, unit, car.palette.muted, 1)
    local signalText = car.state.lighting == "left" and "LEFT" or (car.state.lighting == "right" and "RIGHT" or (car.state.lighting == "hazard" and "HAZARD" or ""))
    if signalText ~= "" then car.hdCenteredText(x, y + 98, speedW, signalText, car.palette.yellow, 1) end
    local gear = car.state.reverse and "R" or (car.state.clutch and "D" or "P")
    car.hdCenteredText(x, y + height - 41, speedW, gear, car.state.reverse and car.palette.orange or car.palette.green, 3)
  
    local modeGap = 5
    local modeH = math.floor((height - modeGap * 2) / 3)
    car.hdModeButton("control:standard", modeX, y, modeW, modeH, "ST", car.state.mode == "standard")
    car.hdModeButton("control:sport", modeX, y + modeH + modeGap, modeW, modeH, "S", car.state.mode == "sport")
    car.hdModeButton("control:sport_plus", modeX, y + (modeH + modeGap) * 2, modeW, height - (modeH + modeGap) * 2, "S+", car.state.mode == "sport_plus")
  
    local controlsGap = 5
    local controlW = math.floor((actionW - controlsGap * 2) / 3)
    local controlH = math.floor((height - controlsGap * 2) / 3)
    local thirdW = actionW - (controlW + controlsGap) * 2
    car.hdButton("control:work_engine", actionX, y, controlW, controlH, "WORKSHOP", "STOP", car.state.workshopEngineOff, car.palette.red)
    car.hdButton("control:drive_engine", actionX + controlW + controlsGap, y, controlW, controlH, "DRIVE", "STOP", car.state.driveEngineOff, car.palette.red)
    car.hdButton("control:cruise", actionX + (controlW + controlsGap) * 2, y, thirdW, controlH, "CRUISE", car.cruiseOn and "ON" or "OFF", car.cruiseOn, car.palette.green)
  
    local secondY = y + controlH + controlsGap
    car.hdButton("control:front_drive", actionX, secondY, controlW, controlH, "DRIVE", car.state.frontDriveOff and "2WD" or "AWD", not car.state.frontDriveOff, car.palette.blue)
    car.hdButton("control:headlights", actionX + controlW + controlsGap, secondY, controlW, controlH, "LIGHTS", "L", car.state.lighting == "headlights", car.palette.cyan)
    car.hdButton("control:boost", actionX + (controlW + controlsGap) * 2, secondY, thirdW, controlH, "SHOP", "BOOST", car.state.workshopBoost, car.palette.orange)
  
    local thirdY = y + (controlH + controlsGap) * 2
    car.hdButton("control:suspension_up", actionX, thirdY, controlW, height - (thirdY - y), "/\\", "HEIGHT", car.state.suspension == "up", car.palette.green)
    car.hdButton("control:suspension_down", actionX + controlW + controlsGap, thirdY, controlW, height - (thirdY - y), "\\/", "HEIGHT", car.state.suspension == "down", car.palette.orange)
    local steering = car.state.aHeld and not car.state.dHeld and "LEFT" or (car.state.dHeld and not car.state.aHeld and "RIGHT" or "CENTER")
    car.hdButton(nil, actionX + (controlW + controlsGap) * 2, thirdY, thirdW, height - (thirdY - y), "STEER", steering, steering ~= "CENTER", car.palette.blue)
  end
  
  function car.drawHDDrive(x, y, width, height)
    local controls = {
      { "standard", "STANDARD", "MODE", car.state.mode == "standard", car.palette.blue },
      { "sport", "SPORT", "MODE", car.state.mode == "sport", car.palette.orange },
      { "sport_plus", "SPORT+", "MODE", car.state.mode == "sport_plus", car.palette.red },
      { "clutch", "CLUTCH", "W / S", car.state.clutch, car.palette.green },
      { "reverse", "REVERSE", "S", car.state.reverse, car.palette.orange },
      { "front_drive", "FRONT DRIVE", car.state.frontDriveOff and "OFF" or "ON", car.state.frontDriveOff, car.palette.red },
      { "drive_engine", "DRIVE ENGINE", car.state.driveEngineOff and "OFF" or "ON", car.state.driveEngineOff, car.palette.red },
      { "work_engine", "SHOP ENGINE", car.state.workshopEngineOff and "OFF" or "ON", car.state.workshopEngineOff, car.palette.red },
      { "boost", "SHOP BOOST", car.state.workshopBoost and "ON" or "OFF", car.state.workshopBoost, car.palette.orange },
      { "headlights", "HEADLIGHTS", "L", car.state.lighting == "headlights", car.palette.cyan },
      { "left", "LEFT SIGNAL", "Z", car.state.lighting == "left", car.palette.yellow },
      { "right", "RIGHT SIGNAL", "C", car.state.lighting == "right", car.palette.yellow },
      { "hazard", "HAZARD", "X", car.state.lighting == "hazard", car.palette.red },
      { "heading", "PORT HEADING", car.state.portHeading:upper(), false, car.palette.blue },
      { nil, "PORT", car.devices.portName and "CONNECTED" or "MISSING", car.devices.portName ~= nil, car.palette.green }
    }
    local cols, rows, gap = 3, 5, 5
    local buttonW = math.floor((width - gap * (cols - 1)) / cols)
    local buttonH = math.floor((height - gap * (rows - 1)) / rows)
    for i = 1, #controls do
      local col = (i - 1) % cols
      local row = math.floor((i - 1) / cols)
      local control = controls[i]
      car.hdButton(control[1] and ("control:" .. control[1]) or nil, x + col * (buttonW + gap), y + row * (buttonH + gap), col == cols - 1 and width - col * (buttonW + gap) or buttonW, buttonH, control[2], control[3], control[4], control[5])
    end
  end
  
  function car.drawHDStats(x, y, width, height)
    local speed, unit = car.hdSpeed()
    local cards = {
      { "CURRENT SPEED", context.fmt(speed, 1) .. " " .. unit, car.palette.cyan },
      { "MAX SPEED", context.fmt((context.stats.maxBps or 0) * 3.6, 1) .. " KM/H", car.palette.orange },
      { "ODOMETER", context.fmt(context.stats.odometer or 0, 1) .. " BLOCKS", car.palette.green },
      { "DRIVE TIME", context.fmtTime(context.stats.movingTime or 0), car.palette.blue }
    }
    local gap = 8
    local cardW = math.floor((width - gap) / 2)
    local cardH = math.floor((height - gap) / 2)
    for i = 1, #cards do
      local col = (i - 1) % 2
      local row = math.floor((i - 1) / 2)
      local cardX = x + col * (cardW + gap)
      local cardY = y + row * (cardH + gap)
      local actualW = col == 1 and width - cardW - gap or cardW
      car.hdRound(cardX, cardY, actualW, cardH, 7, car.palette.surface)
      car.hdText(cardX + 10, cardY + 10, cards[i][1], car.palette.muted, 1)
      car.hdText(cardX + 10, cardY + 33, cards[i][2], cards[i][3], 2)
    end
  end
  
  function car.drawHDSettings(x, y, width, height)
    local gap = 8
    local rowH = math.floor((height - gap * 3) / 4)
    car.hdButton("setting:units", x, y, width, rowH, "SPEED UNITS", context.settings.units, true, car.palette.blue)
    car.hdButton("setting:smooth", x, y + rowH + gap, width, rowH, "SPEED FILTER", context.settings.smoothEnabled and "ON" or "OFF", context.settings.smoothEnabled, car.palette.green)
    car.hdButton("control:heading", x, y + (rowH + gap) * 2, width, rowH, "PORT HEADING", car.state.portHeading:upper(), true, car.palette.orange)
    local status = (car.devices.keyboardName and "KEYBOARD" or "NO KEYBOARD") .. "  |  " .. (car.devices.portName and "PORT 1" or "NO PORT 1") .. "  |  " .. (car.devices.secondaryPortName and "PORT 2" or "NO PORT 2")
    car.hdButton(nil, x, y + (rowH + gap) * 3, width, height - (rowH + gap) * 3, "HARDWARE", status, car.devices.keyboardName ~= nil and car.devices.portName ~= nil and car.devices.secondaryPortName ~= nil, car.palette.green)
  end
  
  function car.drawHDAbout(x, y, width, height)
    car.hdRound(x, y, width, height, 7, car.palette.surface)
    car.hdCenteredText(x, y + 24, width, "ROADROVER OS", car.palette.text, 3)
    car.hdCenteredText(x, y + 58, width, "VERSION " .. context.version, car.palette.blue, 1)
    car.hdCenteredText(x, y + 82, width, "HD VEHICLE CONTROL SYSTEM", car.palette.muted, 1)
    car.hdCenteredText(x, y + 105, width, tostring(car.hd.width) .. " x " .. tostring(car.hd.height), car.palette.muted, 1)
    car.hdCenteredText(x, y + height - 24, width, context.displayUserName(), car.palette.text, 1)
  end
  
  function car.drawHDError(message)
    local gpu = car.devices.gpu
    if not gpu then return false end
    local width = tonumber(car.hd.width) or 384
    local height = tonumber(car.hd.height) or 192
    local text = tostring(message or car.hd.error or "HD renderer failed"):gsub("[\r\n]+", " ")
    if #text > 58 then text = text:sub(1, 58) end
    if gpu.fill then pcall(gpu.fill, car.hdColor(0x080B10)) end
    if gpu.filledRectangle then
      pcall(gpu.filledRectangle, 0, 0, width, height, car.hdColor(0x080B10))
      pcall(gpu.filledRectangle, 12, math.max(12, math.floor(height / 2) - 30), math.max(1, width - 24), 60, car.hdColor(0x32141A))
    end
    if gpu.drawText then
      pcall(gpu.drawText, 24, math.max(20, math.floor(height / 2) - 17), "ROADROVER DISPLAY ERROR", car.hdColor(0xEF4B5A), -1, 1, 0)
      pcall(gpu.drawText, 24, math.max(34, math.floor(height / 2) + 3), text, car.hdColor(0xF4F7FA), -1, 1, 0)
    end
    if gpu.sync then pcall(gpu.sync) end
    return true
  end

  function car.drawHDFrame()
    local gpu = car.devices.gpu
    local width, height = car.hd.width, car.hd.height
    car.hd.hits = {}
    car.hd.error = nil
    if gpu.fill then
      local cleared, clearError = pcall(gpu.fill, car.hdColor(car.palette.background))
      if not cleared then
        car.hd.error = tostring(clearError)
        if not car.hdFill(0, 0, width, height, car.palette.background) then error(car.hd.error or "GPU clear failed", 0) end
      end
    else
      if not car.hdFill(0, 0, width, height, car.palette.background) then error(car.hd.error or "GPU clear failed", 0) end
    end
    car.hdFill(0, 0, width, 24, car.palette.surface)
    car.hdText(9, 8, "ROADROVER", car.palette.text, 1)
    local modeLabel = car.state.mode == "sport_plus" and "SPORT+" or car.state.mode:upper()
    car.hdText(86, 8, modeLabel, car.state.mode == "standard" and car.palette.blue or car.palette.orange, 1)
    local timeText = os.date("%H:%M")
    if width >= 360 then car.hdText(145, 8, "A/D:STEER Z/C:SIG X:HAZ", car.palette.muted, 1) end
    car.hdText(width - car.hdTextWidth(timeText, 1) - 9, 8, timeText, car.palette.text, 1)
  
    local margin = 8
    local navW = math.max(58, math.floor(width * 0.17))
    local navX = width - navW - margin
    local contentY = 32
    local contentH = height - contentY - margin
    local contentW = navX - margin - 7
    car.drawHDNav(navX, contentY, navW, contentH)
    local tabId = context.tabs[context.getActiveTab()] and context.tabs[context.getActiveTab()].id or "home"
    if tabId == "home" then
      car.drawHDHome(margin, contentY, contentW, contentH)
    elseif tabId == "drive" then
      car.drawHDDrive(margin, contentY, contentW, contentH)
    elseif tabId == "stats" then
      car.drawHDStats(margin, contentY, contentW, contentH)
    elseif tabId == "settings" then
      car.drawHDSettings(margin, contentY, contentW, contentH)
    else
      car.drawHDAbout(margin, contentY, contentW, contentH)
    end
    if car.hd.error then error(car.hd.error, 0) end
    if gpu.sync then
      local synced, syncError = pcall(gpu.sync)
      if not synced then error(tostring(syncError), 0) end
    end
    return true
  end

  function car.drawHD()
    if not car.setupHD(false) then return false end
    local ok, result = xpcall(car.drawHDFrame, debug and debug.traceback or function(message) return message end)
    if ok then return result == true end
    car.hd.error = tostring(result)
    car.drawHDError(car.hd.error)
    return false
  end
  
  function car.handleHDClick(x, y)
    x, y = tonumber(x), tonumber(y)
    if not x or not y then return false end
    for i = #car.hd.hits, 1, -1 do
      local target = car.hd.hits[i]
      if x >= target.x and x <= target.x + target.w - 1 and y >= target.y and y <= target.y + target.h - 1 then
        if target.id:sub(1, 6) == "tabid:" then
          context.selectTab(target.id:sub(7))
        elseif target.id:sub(1, 8) == "control:" then
          car.handleDriveControl(target.id:sub(9))
        elseif target.id == "setting:units" then
          if context.settings.units == "KM/H" then context.settings.units = "MP/H"
          elseif context.settings.units == "MP/H" then context.settings.units = "B/S"
          else context.settings.units = "KM/H" end
          context.saveSettings()
        elseif target.id == "setting:smooth" then
          context.settings.smoothEnabled = not context.settings.smoothEnabled
          context.saveSettings()
        end
        return true
      end
    end
    return false
  end
  
  function car.hdEvent(event, a, b, c, d)
    if event ~= "tm_monitor_mouse_click" and event ~= "tm_monitor_touch" then return false end
    local x, y
    if type(a) == "number" and type(b) == "number" then
      x, y = a, b
    else
      x, y = b, c
    end
    return car.handleHDClick(x, y)
  end
  return true
end
