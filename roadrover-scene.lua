local PALETTE = {
  [1] = "#FFF0F0F0", [2] = "#FFF2B233", [4] = "#FFE57FD8", [8] = "#FF99B2F2",
  [16] = "#FFDED83D", [32] = "#FF7FCC19", [64] = "#FFF2B2CC", [128] = "#FF4C4C4C",
  [256] = "#FF999999", [512] = "#FF4C99B2", [1024] = "#FFB266E5", [2048] = "#FF3366CC",
  [4096] = "#FF7F664C", [8192] = "#FF57A64E", [16384] = "#FFCC4C4C", [32768] = "#FF111111"
}
local BLIT = "0123456789abcdef"

local function clamp(value, minimum, maximum)
  value = tonumber(value) or minimum
  if value < minimum then return minimum end
  if value > maximum then return maximum end
  return value
end

local function atan2(y, x)
  if math.atan2 then return math.atan2(y, x) end
  return math.atan(y, x)
end

local function argb(red, green, blue, alpha)
  return string.format("#%02X%02X%02X%02X",
    clamp(math.floor(alpha or 255), 0, 255),
    clamp(math.floor(red or 0), 0, 255),
    clamp(math.floor(green or 0), 0, 255),
    clamp(math.floor(blue or 0), 0, 255))
end

local function tokenColor(token, fallback)
  return PALETTE[tonumber(token)] or fallback or "#FF111111"
end

local function blitColor(value, fallback)
  local index = BLIT:find(tostring(value or ""):lower(), 1, true)
  return index and PALETTE[2 ^ (index - 1)] or fallback or "#FF111111"
end

local function parseColor(value)
  value = tostring(value or "#FF111111"):gsub("#", "")
  if #value == 6 then value = "FF" .. value end
  local alpha = tonumber(value:sub(1, 2), 16) or 255
  local red = tonumber(value:sub(3, 4), 16) or 17
  local green = tonumber(value:sub(5, 6), 16) or 17
  local blue = tonumber(value:sub(7, 8), 16) or 17
  return red, green, blue, alpha
end

local function mix(first, second, progress)
  progress = clamp(progress, 0, 1)
  local r1, g1, b1, a1 = parseColor(first)
  local r2, g2, b2, a2 = parseColor(second)
  return argb(
    r1 + (r2 - r1) * progress,
    g1 + (g2 - g1) * progress,
    b1 + (b2 - b1) * progress,
    a1 + (a2 - a1) * progress
  )
end

local function append(commands, command)
  commands[#commands + 1] = command
  return command
end

local function rect(commands, x, y, width, height, radius, fill)
  return append(commands, {
    type = "rect", x = math.floor(x), y = math.floor(y),
    width = math.max(1, math.floor(width)), height = math.max(1, math.floor(height)),
    radius = math.max(0, math.floor(radius or 0)), fill = fill
  })
end

local function text(commands, x, y, value, size, color, align, vertical, maxWidth)
  return append(commands, {
    type = "text", x = math.floor(x), y = math.floor(y), text = tostring(value or ""),
    size = size, color = color, align = align or "left", vertical = vertical or "baseline",
    maxWidth = maxWidth, fit = maxWidth ~= nil
  })
end

local function polygon(commands, points, fill)
  return append(commands, { type = "polygon", points = points, fill = fill })
end

local function polyline(commands, points, color, width)
  if #points < 4 then return nil end
  return append(commands, {
    type = "polyline", points = points, color = color,
    strokeWidth = width, cap = "round"
  })
end

local function cellBounds(frame, x, y, width, height)
  local cellWidth = tonumber(frame.cellWidth) or 6
  local cellHeight = tonumber(frame.cellHeight) or 9
  local offsetX = tonumber(frame.offsetX) or 1
  local offsetY = tonumber(frame.offsetY) or 1
  return offsetX + (x - 1) * cellWidth, offsetY + (y - 1) * cellHeight,
    width * cellWidth, height * cellHeight
end

local function addNormalizedPolygon(commands, menuX, height, points, color)
  local output = {}
  for index = 1, #points, 2 do
    output[#output + 1] = points[index] * menuX
    output[#output + 1] = points[index + 1] * height
  end
  polygon(commands, output, color)
end

local function projection(map, mapRight, canvasHeight)
  local centerX = tonumber(map.centerX) or 0
  local centerZ = tonumber(map.centerZ) or 0
  local radius = math.max(1, tonumber(map.radius) or 32)
  local rotation = tonumber(map.rotation) or 0
  local left = math.max(0, tonumber(map.x) or 0)
  local top = math.max(0, tonumber(map.y) or 0)
  local width = math.max(1, math.min(mapRight - left, tonumber(map.width) or mapRight - left))
  local height = math.max(1, math.min(canvasHeight - top, tonumber(map.height) or canvasHeight - top))
  local sine, cosine = math.sin(rotation), math.cos(rotation)
  local pixelScale = math.max(0.5, math.min(width, height) / (radius * 2))

  local function project(worldX, worldZ)
    local dx = (tonumber(worldX) or centerX) - centerX
    local dz = (tonumber(worldZ) or centerZ) - centerZ
    local rotatedX = dx * cosine - dz * sine
    local rotatedZ = dx * sine + dz * cosine
    local normalizedY = (rotatedZ + radius) / (radius * 2)
    if normalizedY < 0 or normalizedY > 1 then return nil end
    local scale = 0.52 + 0.76 * (normalizedY ^ 1.15)
    local screenX = left + width / 2 + (rotatedX / radius) * width * 0.5 * scale
    local screenY = top + (normalizedY ^ 1.34) * height
    if screenX < left - 12 or screenX > left + width + 12
      or screenY < top - 12 or screenY > top + height + 12 then return nil end
    return { x = screenX, y = screenY, scale = scale }
  end
  return project, pixelScale, centerX, centerZ
end

local function nearestRoutePose(vehicle, route)
  if not vehicle or #route < 2 then return nil, nil end
  local best, bestAngle, bestDistance
  for index = 2, #route do
    local first, second = route[index - 1], route[index]
    local dx, dy = second.x - first.x, second.y - first.y
    local lengthSquared = dx * dx + dy * dy
    if lengthSquared >= 1 then
      local progress = clamp(((vehicle.x - first.x) * dx + (vehicle.y - first.y) * dy) / lengthSquared, 0, 1)
      local x, y = first.x + dx * progress, first.y + dy * progress
      local distance = (vehicle.x - x) ^ 2 + (vehicle.y - y) ^ 2
      if not bestDistance or distance < bestDistance then
        bestDistance = distance
        best = { x = x, y = y }
        bestAngle = atan2(dy, dx)
      end
    end
  end
  return best, bestAngle
end

local function addMap(commands, map, menuX, width, height)
  local mapRight = math.min(width, menuX + height * 0.08)
  local diagonalGap = math.max(120, height * 0.17)
  local x = -height
  while x < mapRight + height do
    polyline(commands, { x, 0, x - height * 0.52, height }, "#26889284", math.max(1, height / 900))
    x = x + diagonalGap
  end
  local y = -height / 2
  while y < height * 2 do
    polyline(commands, { 0, y, mapRight, y + height * 0.36 }, "#21889284", math.max(1, height / 900))
    y = y + math.max(80, height / 10)
  end

  local green = "#84BFCDB5"
  addNormalizedPolygon(commands, menuX, height, { 0.00,0.05, 0.29,0.08, 0.26,0.31, 0.02,0.29 }, green)
  addNormalizedPolygon(commands, menuX, height, { 0.31,0.00, 0.52,0.00, 0.57,0.30, 0.36,0.34 }, green)
  addNormalizedPolygon(commands, menuX, height, { 0.60,0.02, 0.88,0.04, 0.83,0.33, 0.57,0.29 }, green)
  addNormalizedPolygon(commands, menuX, height, { 0.01,0.48, 0.27,0.40, 0.33,0.84, 0.00,0.94 }, green)
  addNormalizedPolygon(commands, menuX, height, { 0.55,0.47, 0.88,0.37, 0.92,0.76, 0.63,0.91 }, green)
  local building = "#3A979D92"
  addNormalizedPolygon(commands, menuX, height, { 0.06,0.13, 0.18,0.09, 0.20,0.22, 0.08,0.25 }, building)
  addNormalizedPolygon(commands, menuX, height, { 0.20,0.25, 0.31,0.21, 0.33,0.31, 0.22,0.36 }, building)
  addNormalizedPolygon(commands, menuX, height, { 0.61,0.12, 0.74,0.09, 0.76,0.23, 0.63,0.26 }, building)
  addNormalizedPolygon(commands, menuX, height, { 0.66,0.66, 0.80,0.61, 0.82,0.74, 0.68,0.79 }, building)
  if type(map) ~= "table" then return end

  local project, pixelScale, centerX, centerZ = projection(map, mapRight, height)
  local points = {}
  for _, sample in ipairs(type(map.samples) == "table" and map.samples or {}) do
    local point = project(centerX + (tonumber(sample.x) or 0), centerZ + (tonumber(sample.z) or 0))
    if point then
      local color
      if sample.kind == "crosswalk_marker" then color = "#FFEBC73B"
      elseif sample.kind == "crosswalk" then color = "#FFFFFFFF"
      elseif sample.kind == "sidewalk" then color = "#FFB6BAB0"
      elseif sample.tunnel then color = "#FFA0A69E"
      else color = "#FFFFFEFA" end
      points[#points + 1] = {
        x = point.x, y = point.y,
        size = math.max(2, math.ceil((tonumber(sample.step) or 1) * point.scale * pixelScale)),
        color = color
      }
    end
  end
  append(commands, { type = "pointCloud", points = points, shape = "ellipse" })

  local route = {}
  local routeFlat = {}
  for _, item in ipairs(type(map.route) == "table" and map.route or {}) do
    local point = project(item.x, item.z)
    if point then
      route[#route + 1] = point
      routeFlat[#routeFlat + 1], routeFlat[#routeFlat + 2] = point.x, point.y
    end
  end
  if #route > 1 then
    local outer = math.max(10, height * 0.020)
    polyline(commands, routeFlat, "#FFFFFEFA", outer)
    polyline(commands, routeFlat, "#FF111311", outer * 0.50)
    polyline(commands, routeFlat, "#FFD9FF3F", math.max(3, outer * 0.19))
  end

  if type(map.destination) == "table" then
    local point = project(map.destination.x, map.destination.z)
    if point then
      local radius = math.max(8, height * 0.014)
      append(commands, {
        type = "ellipse", x = point.x - radius, y = point.y - radius,
        width = radius * 2, height = radius * 2, fill = "#FFD9FF3F"
      })
    end
  end

  if type(map.vehicle) == "table" then
    local vehicle = project(map.vehicle.x, map.vehicle.z)
    if vehicle then
      local marker, angle = nearestRoutePose(vehicle, route)
      marker = marker or vehicle
      if not angle then
        local forward = project((tonumber(map.vehicle.x) or centerX) + math.cos(tonumber(map.heading) or 0),
          (tonumber(map.vehicle.z) or centerZ) + math.sin(tonumber(map.heading) or 0))
        angle = forward and atan2(forward.y - vehicle.y, forward.x - vehicle.x) or 0
      end
      local halo = math.max(44, height * 0.062)
      append(commands, {
        type = "ellipse", x = marker.x - halo / 2, y = marker.y - halo / 2,
        width = halo, height = halo, fill = "#EEFFFFFC"
      })
      local nose, rear = math.max(18, height * 0.030), math.max(18, height * 0.030) * 0.72
      polygon(commands, {
        marker.x + math.cos(angle) * nose, marker.y + math.sin(angle) * nose,
        marker.x + math.cos(angle + 2.45) * rear, marker.y + math.sin(angle + 2.45) * rear,
        marker.x + math.cos(angle - 2.45) * rear, marker.y + math.sin(angle - 2.45) * rear
      }, "#FF111311")
    end
  end
end

local function addPanel(commands, dashboard, frame, width, height, menuX, menuWidth)
  local topLeft = menuX + height * 0.12
  local bottomLeft = menuX - height * 0.12
  polygon(commands, { topLeft,0, width,0, width,height, bottomLeft,height }, "#F8F8F9F5")

  local startY = tonumber(dashboard.menuStartY) or 1
  local itemHeight = tonumber(dashboard.menuHeight) or 2
  local gap = tonumber(dashboard.menuGap) or 1
  for index, item in ipairs(type(dashboard.menu) == "table" and dashboard.menu or {}) do
    local logicalY = startY + (index - 1) * (itemHeight + gap)
    local x, y, itemWidth, pixelHeight = cellBounds(frame,
      tonumber(dashboard.rightX) or 1, logicalY,
      tonumber(dashboard.rightWidth) or 12, itemHeight)
    local insetX, insetY = math.max(18, height * 0.022), math.max(4, height * 0.008)
    x, y = x + insetX, y + insetY
    itemWidth, pixelHeight = itemWidth - insetX * 2, pixelHeight - insetY * 2
    local progress = clamp(item.progress or 0, 0, 1)
    rect(commands, x, y, itemWidth, pixelHeight, pixelHeight / 2,
      mix("#D0FFFFFC", "#FF111311", progress))
    text(commands, x + itemWidth / 2, y + pixelHeight / 2, item.label,
      math.max(23, math.min(pixelHeight * 0.42, height * 0.038)),
      mix("#FF191B18", "#FFFFFEFA", progress), "center", "middle", itemWidth - 28)
  end
end

local function addHeader(commands, dashboard, width, height, menuX)
  local x = math.max(24, width * 0.018)
  local baseline = height * 0.071
  local timeSize = math.max(28, height * 0.039)
  text(commands, x, baseline, dashboard.time or "", timeSize, "#FF111311")
  local estimatedTimeWidth = #(tostring(dashboard.time or "")) * timeSize * 0.52
  text(commands, x + estimatedTimeWidth + math.max(10, height * 0.011), baseline,
    dashboard.date or "", math.max(17, height * 0.021), "#FF52574F")

  local music = type(dashboard.notification) == "table" and dashboard.notification or nil
  if music then
    local toastWidth = math.min(width * 0.24, height * 0.68)
    local toastHeight = math.max(64, height * 0.075)
    local toastX = math.max(width * 0.34, menuX - toastWidth - height * 0.08)
    local toastY = math.max(16, height * 0.025)
    rect(commands, toastX, toastY, toastWidth, toastHeight, toastHeight / 2, "#EC111311")
    text(commands, toastX + toastHeight * 0.42, toastY + toastHeight * 0.37,
      music.title or "", math.max(20, toastHeight * 0.31), "#FFFFFEFA", "left", "middle",
      toastWidth - toastHeight * 0.65)
    text(commands, toastX + toastHeight * 0.42, toastY + toastHeight * 0.70,
      music.text or "", math.max(15, toastHeight * 0.22), "#FFDADDD6", "left", "middle",
      toastWidth - toastHeight * 0.65)
  end
end

local function addSpeed(commands, dashboard, width, height, menuX)
  local speedWidth = math.min(menuX, width * 0.205)
  local baseline = height * 0.59
  text(commands, speedWidth / 2, baseline, dashboard.speed or "0",
    math.max(180, height * 0.315), "#FF000000", "center", "baseline", speedWidth)
  text(commands, speedWidth / 2, baseline + height * 0.105, dashboard.unit or "kmh",
    math.max(38, height * 0.061), "#FF000000", "center", "baseline", speedWidth)
end

local function addControls(commands, dashboard, frame, height)
  for _, control in ipairs(type(dashboard.controls) == "table" and dashboard.controls or {}) do
    local x, y, width, controlHeight = cellBounds(frame, control.x, control.y, control.width, control.height)
    local inset = math.max(3, height / 240)
    x, y, width, controlHeight = x + inset, y + inset, width - inset * 2, controlHeight - inset * 2
    local progress = clamp(control.progress or (control.active and 1 or 0), 0, 1)
    rect(commands, x, y, width, controlHeight, controlHeight / 2,
      mix("#E0FFFFFC", "#FF111311", progress))
    text(commands, x + width / 2, y + controlHeight / 2, control.label or "",
      math.max(18, controlHeight * 0.30), mix("#FF171917", "#FFFFFEFA", progress),
      "center", "middle", width - 20)
  end

  local modes = type(dashboard.modes) == "table" and dashboard.modes or {}
  if #modes == 0 then return end
  local first, last = modes[1], modes[#modes]
  local x, y, width, modeHeight = cellBounds(frame, first.x, first.y,
    (last.x + last.width) - first.x, first.height)
  local inset = math.max(4, height / 180)
  x, y, width, modeHeight = x + inset, y + inset, width - inset * 2, modeHeight - inset * 2
  rect(commands, x, y, width, modeHeight, modeHeight / 2, "#E1FFFFFC")
  local padding = math.max(5, height * 0.006)
  local innerX, innerY = x + padding, y + padding
  local innerWidth, innerHeight = width - padding * 2, modeHeight - padding * 2
  local segmentWidth = innerWidth / #modes
  local slider = clamp(dashboard.modeSlider or 0, 0, #modes - 1)
  rect(commands, innerX + slider * segmentWidth, innerY, segmentWidth, innerHeight,
    innerHeight / 2, "#FF111311")
  for index, mode in ipairs(modes) do
    local progress = clamp(1 - math.abs(slider - (index - 1)), 0, 1)
    text(commands, innerX + (index - 0.5) * segmentWidth, innerY + innerHeight / 2,
      mode.label or "", math.max(22, innerHeight * 0.46),
      mix("#FF191B18", "#FFFFFEFA", progress), "center", "middle", segmentWidth - 10)
  end
end

local function buttonVisible(page, id)
  if page == "map" then return id:find("^map:") ~= nil end
  if page == "drive" then return id:find("^drive:") ~= nil end
  if page == "vehicle" then
    return id:find("^action:") ~= nil or id:find("^info:") ~= nil or id:find("^actions:") ~= nil
  end
  if page == "music" then return id:find("^music:") ~= nil end
  if page == "settings" then return id:find("^settings:") ~= nil end
  return false
end

local function buildTerminalScene(frame, width, height)
  local commands = {}
  local cellWidth = tonumber(frame.cellWidth) or 6
  local cellHeight = tonumber(frame.cellHeight) or 9
  local offsetX = tonumber(frame.offsetX) or 1
  local offsetY = tonumber(frame.offsetY) or 1
  local fontSize = tonumber(frame.fontSize) or math.max(8, cellHeight * 0.78)
  for row, line in ipairs(type(frame.lines) == "table" and frame.lines or {}) do
    local content = tostring(line.text or "")
    local foreground = tostring(line.foreground or "")
    local background = tostring(line.background or "")
    local y = offsetY + (row - 1) * cellHeight
    local start = 1
    while start <= #content do
      local colorCode = background:sub(start, start)
      local finish = start
      while finish < #content and background:sub(finish + 1, finish + 1) == colorCode do
        finish = finish + 1
      end
      rect(commands, offsetX + (start - 1) * cellWidth, y,
        (finish - start + 1) * cellWidth, cellHeight, 0, blitColor(colorCode, "#FFFFFFFF"))
      start = finish + 1
    end
    for column = 1, #content do
      local character = content:sub(column, column)
      if character ~= " " then
        text(commands, offsetX + (column - 0.5) * cellWidth, y + cellHeight / 2,
          character, fontSize, blitColor(foreground:sub(column, column), "#FF111111"),
          "center", "middle", cellWidth)
      end
    end
  end
  for _, button in ipairs(type(frame.buttons) == "table" and frame.buttons or {}) do
    local x, y = tonumber(button.x) or 0, tonumber(button.y) or 0
    local buttonWidth, buttonHeight = tonumber(button.width) or 1, tonumber(button.height) or 1
    local progress = clamp(button.progress or 0, 0, 1)
    local background = mix(tokenColor(button.inactiveBg, "#FF111111"),
      tokenColor(button.activeBg, "#FFFFFFFF"), progress)
    local foreground = mix(tokenColor(button.inactiveFg, "#FFFFFFFF"),
      tokenColor(button.activeFg, "#FF111111"), progress)
    rect(commands, x, y, buttonWidth, buttonHeight, math.min(8, buttonHeight / 2), background)
    local second = tostring(button.line2 or "")
    if second ~= "" then
      text(commands, x + buttonWidth / 2, y + buttonHeight * 0.37, button.line1 or "",
        fontSize, foreground, "center", "middle", buttonWidth - 6)
      text(commands, x + buttonWidth / 2, y + buttonHeight * 0.68, second,
        fontSize, foreground, "center", "middle", buttonWidth - 6)
    else
      text(commands, x + buttonWidth / 2, y + buttonHeight / 2, button.line1 or "",
        fontSize, foreground, "center", "middle", buttonWidth - 6)
    end
  end
  return { background = "#FF000000", layers = { { id = "terminal", commands = commands } } }
end

local function addPage(commands, dashboard, buttons, width, height, menuX)
  local page = tostring(dashboard.page or "home")
  if page ~= "home" and page ~= "map" then
    local cardX = math.max(width * 0.22, width * 0.205)
    local cardY = height * 0.15
    local cardWidth = math.max(1, menuX - cardX - height * 0.08)
    local cardHeight = height * 0.67
    rect(commands, cardX, cardY, cardWidth, cardHeight, height * 0.065, "#D2FFFFFC")
    text(commands, cardX + height * 0.055, cardY + height * 0.105,
      dashboard.pageTitle or page, math.max(34, height * 0.060), "#FF111311")
  end
  for _, button in ipairs(type(buttons) == "table" and buttons or {}) do
    local id = tostring(button.id or "")
    if buttonVisible(page, id) then
      local x, y = tonumber(button.x) or 0, tonumber(button.y) or 0
      local buttonWidth, buttonHeight = tonumber(button.width) or 1, tonumber(button.height) or 1
      local inset = math.max(3, height / 260)
      x, y = x + inset, y + inset
      buttonWidth, buttonHeight = buttonWidth - inset * 2, buttonHeight - inset * 2
      local progress = clamp(button.progress or 0, 0, 1)
      rect(commands, x, y, buttonWidth, buttonHeight, buttonHeight / 2,
        mix("#E1FFFFFC", "#FF111311", progress))
      local foreground = mix("#FF171917", "#FFFFFEFA", progress)
      local second = tostring(button.line2 or "")
      local size = math.max(17, buttonHeight * (second ~= "" and 0.22 or 0.29))
      local centerX = x + buttonWidth / 2
      if second ~= "" then
        text(commands, centerX, y + buttonHeight * 0.38, button.line1 or "", size,
          foreground, "center", "middle", buttonWidth - 20)
        text(commands, centerX, y + buttonHeight * 0.68, second, size,
          mix("#FF62675F", "#FFE6E8E2", progress), "center", "middle", buttonWidth - 20)
      else
        text(commands, centerX, y + buttonHeight / 2, button.line1 or "", size,
          foreground, "center", "middle", buttonWidth - 20)
      end
    end
  end
  local transition = clamp(dashboard.pageTransition or 1, 0, 1)
  if transition < 0.999 then
    rect(commands, 0, 0, menuX, height, 0, argb(255, 254, 250, (1 - transition) * 158))
  end
end

return function(frame, width, height)
  width, height = math.max(1, tonumber(width) or 3240), math.max(1, tonumber(height) or 1080)
  if type(frame.dashboard) ~= "table" then return buildTerminalScene(frame, width, height) end
  local dashboard = type(frame.dashboard) == "table" and frame.dashboard or {}
  local rightX = tonumber(dashboard.rightX) or math.max(1, math.floor(width / (frame.cellWidth or 6)) - 11)
  local rightWidth = tonumber(dashboard.rightWidth) or 12
  local menuX = (tonumber(frame.offsetX) or 1) + (rightX - 1) * (tonumber(frame.cellWidth) or 6)
  local menuWidth = rightWidth * (tonumber(frame.cellWidth) or 6)
  local commands = {}
  append(commands, {
    type = "gradient", x = 0, y = 0, width = width, height = height,
    direction = "vertical", from = "#FFF7F8F3", to = "#FFE4E7DE"
  })
  addMap(commands, frame.map, menuX, width, height)
  addPanel(commands, dashboard, frame, width, height, menuX, menuWidth)
  addHeader(commands, dashboard, width, height, menuX)
  addSpeed(commands, dashboard, width, height, menuX)
  addControls(commands, dashboard, frame, height)
  addPage(commands, dashboard, frame.buttons, width, height, menuX)
  return {
    background = "#FFF7F8F3",
    layers = {
      { id = "rros", commands = commands }
    }
  }
end
