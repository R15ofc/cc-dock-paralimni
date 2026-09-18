local TICK = 0.12
local function getScriptDir()
  if shell and type(shell.getRunningProgram) == "function" then
    local p = shell.getRunningProgram()
    if p and p ~= "" then return fs.getDir(p) end
  end
  return ""
end

local SCRIPT_DIR = getScriptDir()
local BASE_DIR = _G.ROADROVER_BASE_DIR or (SCRIPT_DIR ~= "" and SCRIPT_DIR or ".")
local RRID_FILE = fs.combine(BASE_DIR, "system/rrid.txt")
local BASE_ENGINE_SIDE = _G.ENGINE_SIDE or "bottom"
local BASE_DRIVE_SIDE = _G.DRIVE_SIDE or "left"
local ENGINE_SIDE = BASE_ENGINE_SIDE
local DRIVE_SIDE = BASE_DRIVE_SIDE
local BIGFONT_ID = "3LfWxRWh"
local BIGFONT_URL = "https://pastebin.com/raw/" .. BIGFONT_ID
local TEXT_SCALE = 0.5
local PULSE_SEC = 0.18
local VERSION = _G.ROADROVER_VERSION or "2.3.0"
local RRID_MIN = 3
local RRID_MAX = 10
local SPEED_Y_OFFSET = 2
local UNIT_Y_OFFSET = -1
local ENGINE_CLICK_COOLDOWN = tonumber(_G.ENGINE_CLICK_COOLDOWN) or 0.5
local lastEngineClick = tonumber(_G.lastEngineClick) or -1e9
local DEBUG = (_G.ROADROVER_DEBUG == true or _G.ROADROVER_DEBUG == 1 or _G.ROADROVER_DEBUG == "1")
local USE_GPS = (_G.ROADROVER_USE_GPS == true or _G.ROADROVER_USE_GPS == 1 or _G.ROADROVER_USE_GPS == "1")
local BASE_COLORS = {
  bg = colors.white,
  fg = colors.black,
  panel = colors.black,
  panelText = colors.white,
  activeBg = colors.white,
  activeText = colors.black,
  timeBg = colors.black,
  timeText = colors.white
}
local COLORS = {}
local NIGHT_MODE = false

local function themeColor(c)
  if not NIGHT_MODE then return c end
  if c == colors.black then return colors.white end
  if c == colors.white then return colors.black end
  return c
end

local function applyNightMode()
  for k, v in pairs(BASE_COLORS) do
    COLORS[k] = NIGHT_MODE and themeColor(v) or v
  end
end
applyNightMode()
local bigfont = nil
local bigfontTried = false
local debugInfo = { reason = "init", posFn = "none", dt = 0, d = 0 }

local function clamp(n, a, b) if n < a then return a end if n > b then return b end return n end
local function safe(s) s = tostring(s or ""); s = s:gsub("\n", " "):gsub("\r", " "); s = s:gsub("^%s+", ""):gsub("%s+$", ""); return s end
local function trim(s, w) s = tostring(s or ""); w = tonumber(w) or #s; if #s <= w then return s end return s:sub(1, w) end
local function fmt(n, p) n = tonumber(n) or 0; p = tonumber(p) or 0; return string.format("%." .. p .. "f", n) end
local function fmtTime(sec)
  sec = tonumber(sec) or 0
  if sec < 0 then sec = 0 end
  sec = math.floor(sec + 0.5)
  local h = math.floor(sec / 3600)
  local m = math.floor((sec % 3600) / 60)
  local s = sec % 60
  return string.format("%02d:%02d:%02d", h, m, s)
end

local function ordinal(n)
  n = tonumber(n) or 0
  local n100 = n % 100
  if n100 >= 11 and n100 <= 13 then return tostring(n) .. "th" end
  local n10 = n % 10
  if n10 == 1 then return tostring(n) .. "st" end
  if n10 == 2 then return tostring(n) .. "nd" end
  if n10 == 3 then return tostring(n) .. "rd" end
  return tostring(n) .. "th"
end

local function safeName(s)
  s = safe(s):gsub("[^%w_%-]", "_")
  if s == "" then s = "default" end
  return s
end

local function mkdirp(p) if not fs.exists(p) then fs.makeDir(p) end end

local sanitizeRRIDInput
local rridKey
local displayRRID
local isValidRRIDDisplay
local isValidRRIDKey
local userDirKey
local redraw
local resetSpeedState
local car = {
  state = nil,
  devices = {
    portName = nil,
    port = nil,
    keyboardName = nil,
    keyboard = nil,
    gpuName = nil,
    gpu = nil,
    lastScan = -1e9,
    error = nil
  },
  headingOrder = { "north", "east", "south", "west" },
  headingValid = { north = true, east = true, south = true, west = true },
  driveBoxes = {},
  outputCache = { chassis = {}, port = {} },
  blinkPeriod = 0.55,
  lastBlink = os.clock(),
  engineOn = false,
  pulseTimer = nil,
  cruiseOn = false,
  driveMode = "normal",
  hd = {
    ready = false,
    width = 384,
    height = 192,
    hits = {},
    gpuName = nil
  },
  palette = {
    background = 0x080B10,
    surface = 0x121821,
    surfaceRaised = 0x1B2430,
    border = 0x344252,
    text = 0xF4F7FA,
    muted = 0x8C9AA8,
    blue = 0x2F81F7,
    cyan = 0x31C6E7,
    green = 0x36C978,
    yellow = 0xF4C44E,
    orange = 0xF38B3C,
    red = 0xEF4B5A
  }
}
local timerResetRequested = false

local DEFAULT_TEXT_SCALE = tonumber(_G.ROADROVER_TEXT_SCALE) or TEXT_SCALE
local DEFAULT_UNITS = tostring(_G.ROADROVER_UNITS or "KM/H")
local DEFAULT_SMOOTH = tonumber(_G.ROADROVER_SMOOTH) or 4
local DEFAULT_SMOOTH_ENABLED = (_G.ROADROVER_SMOOTH_ENABLED ~= 0 and _G.ROADROVER_SMOOTH_ENABLED ~= "0" and _G.ROADROVER_SMOOTH_ENABLED ~= false)
local DEFAULT_DEBUG = DEBUG
local DEFAULT_NIGHT_MODE = (_G.ROADROVER_NIGHT_MODE == true or _G.ROADROVER_NIGHT_MODE == 1 or _G.ROADROVER_NIGHT_MODE == "1")
local DEFAULT_PORT_HEADING = tostring(_G.ROADROVER_PORT_HEADING or "north"):lower()

local function displayUserName()
  return displayRRID(USER_NAME, RRID_MAX)
end

local settings = {
  textScale = DEFAULT_TEXT_SCALE,
  units = DEFAULT_UNITS,
  speedSmooth = DEFAULT_SMOOTH,
  smoothEnabled = DEFAULT_SMOOTH_ENABLED,
  nightMode = DEFAULT_NIGHT_MODE,
  portHeading = DEFAULT_PORT_HEADING
}

local function sanitizeSettings()
  if settings.textScale ~= 0.5 and settings.textScale ~= 1.0 then settings.textScale = 0.5 end
  if settings.units ~= "KM/H" and settings.units ~= "MP/H" and settings.units ~= "B/S" then settings.units = "KM/H" end
  local ok = { [0] = true, [3] = true, [6] = true, [9] = true }
  if not ok[tonumber(settings.speedSmooth) or 0] then settings.speedSmooth = 4 end
  if settings.smoothEnabled ~= true and settings.smoothEnabled ~= false then settings.smoothEnabled = true end
  if settings.nightMode ~= true and settings.nightMode ~= false then settings.nightMode = false end
  if settings.portHeading ~= "north" and settings.portHeading ~= "east" and settings.portHeading ~= "south" and settings.portHeading ~= "west" then settings.portHeading = "north" end
end
sanitizeSettings()

local function applyDefaultSettings()
  settings.textScale = DEFAULT_TEXT_SCALE
  settings.units = DEFAULT_UNITS
  settings.speedSmooth = DEFAULT_SMOOTH
  settings.smoothEnabled = DEFAULT_SMOOTH_ENABLED
  settings.nightMode = DEFAULT_NIGHT_MODE
  settings.portHeading = DEFAULT_PORT_HEADING
  DEBUG = DEFAULT_DEBUG and true or false
  _G.ROADROVER_DEBUG = DEBUG and 1 or 0
  sanitizeSettings()
  NIGHT_MODE = settings.nightMode and true or false
  _G.ROADROVER_NIGHT_MODE = NIGHT_MODE and 1 or 0
  applyNightMode()
end

local function getUserName()
  local u = _G.USER or _G.USERNAME
  if not u or u == "" then
    if os and os.getComputerLabel then u = os.getComputerLabel() end
  end
  if not u or u == "" then
    if os and os.getComputerID then u = "user" .. tostring(os.getComputerID()) end
  end
  return safeName(u)
end

local function ensureBaseDirs()
  mkdirp(BASE_DIR)

  local system = fs.combine(BASE_DIR, "system")
  mkdirp(system)
  mkdirp(fs.combine(system, "update"))
  mkdirp(fs.combine(system, "logs"))

  local shared = fs.combine(BASE_DIR, "shared")
  mkdirp(shared)
  mkdirp(fs.combine(shared, "assets"))
  mkdirp(fs.combine(shared, "themes"))

  local backups = fs.combine(BASE_DIR, "backups")
  mkdirp(backups)
  mkdirp(fs.combine(backups, "daily"))

  return system
end

local function ensureUserDirs(user)
  ensureBaseDirs()

  local users = fs.combine(BASE_DIR, "users")
  mkdirp(users)

  user = safeName(user)
  local uroot = fs.combine(users, user)
  mkdirp(uroot)

  local data = fs.combine(uroot, "data")
  mkdirp(data)

  local caches = fs.combine(uroot, "caches")
  mkdirp(caches)
  mkdirp(fs.combine(caches, "fonts"))
  mkdirp(fs.combine(caches, "daily"))

  mkdirp(fs.combine(uroot, "logs"))

  return uroot
end

local USER_NAME = nil
local USER_ROOT = nil
local FONT_CACHE = nil
local BIGFONT_FILE = nil

local function ensureDailyCache()
  if not USER_ROOT then return end
  local daily = fs.combine(USER_ROOT, "caches/daily")
  mkdirp(daily)
  local today = os.date("%Y-%m-%d")
  mkdirp(fs.combine(daily, today))
  local keep = 7
  local entries = fs.list(daily)
  local dates = {}
  for i = 1, #entries do
    local name = entries[i]
    if name:match("^%d%d%d%d%-%d%d%-%d%d$") then
      dates[#dates + 1] = name
    end
  end
  table.sort(dates)
  if #dates > keep then
    for i = 1, #dates - keep do
      pcall(function() fs.delete(fs.combine(daily, dates[i])) end)
    end
  end
end

local stats = { odometer = 0, totalTime = 0, movingTime = 0, maxBps = 0 }
local lastStatsSave = 0

local function resetStats()
  stats.odometer = 0
  stats.totalTime = 0
  stats.movingTime = 0
  stats.maxBps = 0
end

local function readJson(path)
  if not path or not fs.exists(path) then return nil end
  local h = fs.open(path, "r")
  if not h then return nil end
  local raw = h.readAll() or ""
  h.close()
  if raw == "" then return nil end
  if textutils and textutils.unserializeJSON then
    local ok, t = pcall(function() return textutils.unserializeJSON(raw) end)
    if ok and type(t) == "table" then return t end
  end
  return nil
end

local function writeJson(path, data)
  if not path or not textutils or not textutils.serializeJSON then return false end
  local ok, raw = pcall(function() return textutils.serializeJSON(data) end)
  if not ok or type(raw) ~= "string" then return false end
  local h = fs.open(path, "w")
  if not h then return false end
  h.write(raw)
  h.close()
  return true
end

local function settingsPath()
  if not USER_ROOT then return nil end
  return fs.combine(USER_ROOT, "data/settings.json")
end

local function statsPath()
  if not USER_ROOT then return nil end
  return fs.combine(USER_ROOT, "data/stats.json")
end

local function profilePath(root)
  if not root then return nil end
  return fs.combine(root, "data/profile.json")
end

local function loadProfileDisplay(root)
  local data = readJson(profilePath(root))
  if type(data) == "table" and type(data.display) == "string" then
    return data.display
  end
  return nil
end

local function saveProfileDisplay(root, display)
  local path = profilePath(root)
  if not path then return false end
  local data = { display = display }
  return writeJson(path, data)
end

local function loadUserSettings()
  local data = readJson(settingsPath())
  if type(data) ~= "table" then return false end
  applyDefaultSettings()
  if data.textScale ~= nil then settings.textScale = tonumber(data.textScale) or settings.textScale end
  if type(data.units) == "string" then settings.units = data.units end
  if data.speedSmooth ~= nil then settings.speedSmooth = tonumber(data.speedSmooth) or settings.speedSmooth end
  if data.smoothEnabled ~= nil then settings.smoothEnabled = data.smoothEnabled and true or false end
  if data.nightMode ~= nil then settings.nightMode = data.nightMode and true or false end
  if type(data.portHeading) == "string" then settings.portHeading = data.portHeading:lower() end
  if data.debug ~= nil then
    DEBUG = data.debug and true or false
    _G.ROADROVER_DEBUG = DEBUG and 1 or 0
  end
  sanitizeSettings()
  NIGHT_MODE = settings.nightMode and true or false
  _G.ROADROVER_NIGHT_MODE = NIGHT_MODE and 1 or 0
  applyNightMode()
  if car.state then car.state.portHeading = settings.portHeading end
  return true
end

local function saveUserSettings()
  local path = settingsPath()
  if not path then return false end
  local data = {
    textScale = settings.textScale,
    units = settings.units,
    speedSmooth = settings.speedSmooth,
    smoothEnabled = settings.smoothEnabled and true or false,
    nightMode = settings.nightMode and true or false,
    portHeading = settings.portHeading,
    debug = DEBUG and true or false
  }
  return writeJson(path, data)
end

local function loadUserStats()
  local data = readJson(statsPath())
  if type(data) ~= "table" then return false end
  stats.odometer = tonumber(data.odometer) or 0
  stats.totalTime = tonumber(data.totalTime) or 0
  stats.movingTime = tonumber(data.movingTime) or 0
  stats.maxBps = tonumber(data.maxBps) or 0
  return true
end

local function saveUserStats()
  local path = statsPath()
  if not path then return false end
  local data = {
    odometer = tonumber(stats.odometer) or 0,
    totalTime = tonumber(stats.totalTime) or 0,
    movingTime = tonumber(stats.movingTime) or 0,
    maxBps = tonumber(stats.maxBps) or 0
  }
  return writeJson(path, data)
end

local function loadRRID()
  ensureBaseDirs()
  if not fs.exists(RRID_FILE) then return nil end
  local h = fs.open(RRID_FILE, "r")
  if not h then return nil end
  local raw = h.readAll() or ""
  h.close()
  raw = safe(raw)
  raw = sanitizeRRIDInput(raw)
  if raw == "" or not isValidRRIDDisplay(raw, RRID_MIN) then return nil end
  return raw
end

local function saveRRID(rrid)
  ensureBaseDirs()
  rrid = sanitizeRRIDInput(rrid)
  if rrid == "" or not isValidRRIDDisplay(rrid, RRID_MIN) then return false end
  local h = fs.open(RRID_FILE, "w")
  if not h then return false end
  h.write(tostring(rrid or ""))
  h.close()
  return true
end

local function setCurrentUser(rrid)
  rrid = sanitizeRRIDInput(rrid)
  if rrid == "" or not isValidRRIDDisplay(rrid, RRID_MIN) then return false end
  if USER_ROOT and USER_NAME and sanitizeRRIDInput(USER_NAME) ~= rrid then
    saveUserSettings()
    saveUserStats()
  end
  USER_NAME = rrid
  USER_ROOT = ensureUserDirs(userDirKey(rrid))
  FONT_CACHE = fs.combine(USER_ROOT, "caches/fonts")
  BIGFONT_FILE = fs.combine(FONT_CACHE, "bigfont.lua")
  bigfont = nil
  bigfontTried = false
  applyDefaultSettings()
  if not loadUserSettings() then saveUserSettings() end
  resetStats()
  if not loadUserStats() then saveUserStats() end
  saveProfileDisplay(USER_ROOT, rrid)
  ensureDailyCache()
  return true
end

local function ensureUserReady()
  if USER_ROOT then return true end
  local rrid = loadRRID()
  if rrid and rrid ~= "" then
    return setCurrentUser(rrid)
  end
  return false
end

local function clearCaches()
  if not USER_ROOT then return end
  local caches = fs.combine(USER_ROOT, "caches")
  if fs.exists(caches) then
    pcall(function() fs.delete(caches) end)
  end
  mkdirp(caches)
  mkdirp(fs.combine(caches, "fonts"))
  mkdirp(fs.combine(caches, "daily"))
  bigfont = nil
  bigfontTried = false
  ensureDailyCache()
  if resetSpeedState then resetSpeedState(true) end
end

local VEHICLE_INFO_PATH = (SCRIPT_DIR ~= "" and fs.combine(SCRIPT_DIR, "VehicleInfo.json")) or "VehicleInfo.json"

local function loadVehicleInfo()
  if not fs.exists(VEHICLE_INFO_PATH) then return {} end
  local h = fs.open(VEHICLE_INFO_PATH, "r")
  if not h then return {} end
  local raw = h.readAll() or ""
  h.close()
  if raw == "" then return {} end
  if textutils and textutils.unserializeJSON then
    local ok, t = pcall(function() return textutils.unserializeJSON(raw) end)
    if ok and type(t) == "table" then return t end
  end
  return {}
end

local vehicleInfo = loadVehicleInfo()
local engineType = tostring(vehicleInfo.engineType or "Diesel")
local isDiesel = (engineType:lower() == "diesel")
local isSedan = (vehicleInfo.sedan == true)
if isSedan then
  ENGINE_SIDE = "right"
  DRIVE_SIDE = "left"
end

local function loadBigFont()
  if bigfontTried then return bigfont end
  if not ensureUserReady() then return nil end
  bigfontTried = true

  if fs.exists(BIGFONT_FILE) then
    local ok, lib = pcall(dofile, BIGFONT_FILE)
    if ok and type(lib) == "table" then bigfont = lib; return lib end
  end

  if http and http.get then
    local ok, res = pcall(function() return http.get(BIGFONT_URL) end)
    if ok and res then
      local code = res.readAll()
      res.close()
      if type(code) == "string" and #code > 0 then
        local h = fs.open(BIGFONT_FILE, "w")
        if h then h.write(code); h.close() end
        local ok2, lib = pcall(load, code, "bigfont", "t", _ENV)
        if ok2 and type(lib) == "table" then bigfont = lib; return lib end
        local ok3, lib2 = pcall(dofile, BIGFONT_FILE)
        if ok3 and type(lib2) == "table" then bigfont = lib2; return lib2 end
      end
    end
  end

  return nil
end

local function bigTextWidth(text)
  local n = #tostring(text or "")
  if n <= 0 then return 0 end
  return n * 4 - 1
end

local function isLight(c)
  return c == colors.white or c == colors.lightGray or c == colors.yellow or c == colors.lime or c == colors.orange
end

local function bestFg(bg) return isLight(bg) and colors.black or colors.white end

local function anyGet(v, k) local ok, val = pcall(function() return v[k] end) if ok then return val end end
local function vecXYZ(v)
  if not v then return nil end
  local x = anyGet(v, "x") or (type(v) == "table" and v[1])
  local y = anyGet(v, "y") or (type(v) == "table" and v[2])
  local z = anyGet(v, "z") or (type(v) == "table" and v[3])
  x = tonumber(x); y = tonumber(y); z = tonumber(z)
  if not x or not y or not z then return nil end
  return { x = x, y = y, z = z }
end

local function vecXYZ3(x, y, z)
  x = tonumber(x); y = tonumber(y); z = tonumber(z)
  if not x or not y or not z then return nil end
  return { x = x, y = y, z = z }
end

local function dist(a, b)
  local dx = a.x - b.x
  local dy = a.y - b.y
  local dz = a.z - b.z
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function resolveShip()
  if ship and type(ship) == "table" then return ship end
  if not peripheral or not peripheral.getNames then return nil end
  local ok, names = pcall(peripheral.getNames)
  if not ok or type(names) ~= "table" then return nil end
  for _, name in ipairs(names) do
    local ok2, typ = pcall(peripheral.getType, name)
    if ok2 and type(typ) == "string" then
      local low = typ:lower()
      if low:find("ship") then
        local s = peripheral.wrap(name)
        if s then
          ship = s
          return s
        end
      end
    end
  end
  return nil
end

local function listShipFns()
  if not ship or type(ship) ~= "table" then resolveShip() end
  if not ship or type(ship) ~= "table" then return {} end
  local out = {}
  for k, v in pairs(ship) do
    if type(k) == "string" and type(v) == "function" then out[#out + 1] = k end
  end
  table.sort(out)
  return out
end

local function pickPosGetter()
  if not ship or type(ship) ~= "table" then resolveShip() end
  if not ship or type(ship) ~= "table" then
    if USE_GPS and gps and gps.locate then
      local function gpsPos()
        local ok, x, y, z = pcall(gps.locate, 1.5)
        if ok and x and y and z then return { x = x, y = y, z = z } end
        return nil
      end
      local p = gpsPos()
      if p then return gpsPos, "gps.locate" end
    end
    return nil, nil
  end
  local candidates = {}
  local pref = {"getWorldspacePosition", "getWorldPosition", "getPosition", "getShipyardPosition", "getPos", "position"}
  for _, name in ipairs(pref) do
    if type(ship[name]) == "function" then candidates[#candidates + 1] = name end
  end
  for _, name in ipairs(listShipFns()) do
    local low = name:lower()
    if (low:find("pos") or low:find("position")) and not low:find("vel") then
      local exists = false
      for i = 1, #candidates do if candidates[i] == name then exists = true break end end
      if not exists then candidates[#candidates + 1] = name end
    end
  end
  for _, name in ipairs(candidates) do
    local fn = ship[name]
    local function makeGetter(selfArg)
      return function()
        local ok, a, b, c = pcall(fn, selfArg)
        if not ok then return nil end
        return vecXYZ(a) or vecXYZ3(a, b, c)
      end
    end

    local getter1 = makeGetter(ship)
    local p1 = getter1()
    if p1 then return getter1, name end

    local getter2 = makeGetter(nil)
    local p2 = getter2()
    if p2 then return getter2, name end
  end
  return nil, nil
end

local getPos, posFnName = pickPosGetter()
local lastRescan = 0

local function rescan(force)
  local t = os.clock()
  if not force and (t - lastRescan) < 1.0 then return end
  lastRescan = t
  local f, name = pickPosGetter()
  if f then getPos = f; posFnName = name end
end

car.state = {
  mode = "standard",
  clutch = false,
  reverse = false,
  frontDriveOff = false,
  workshopEngineOff = false,
  driveEngineOff = true,
  workshopBoost = false,
  lighting = "none",
  blink = false,
  wHeld = false,
  sHeld = false,
  portHeading = tostring(vehicleInfo.portHeading or settings.portHeading or "north"):lower()
}

if not car.headingValid[car.state.portHeading] then car.state.portHeading = "north" end

function car.peripheralType(name)
  if not peripheral or not peripheral.getType then return "" end
  local ok, kind = pcall(peripheral.getType, name)
  if not ok then return "" end
  if type(kind) == "table" then return table.concat(kind, ","):lower() end
  return tostring(kind or ""):lower()
end

function car.hasMethod(name, wanted)
  if not peripheral or not peripheral.getMethods then return false end
  local ok, methods = pcall(peripheral.getMethods, name)
  if not ok or type(methods) ~= "table" then return false end
  for i = 1, #methods do
    if methods[i] == wanted then return true end
  end
  return false
end

function car.scanDevices(force)
  local now = os.clock()
  if not force and now - car.devices.lastScan < 2 then return end
  car.devices.lastScan = now
  local previousPortName = car.devices.portName
  car.devices.portName, car.devices.port = nil, nil
  car.devices.keyboardName, car.devices.keyboard = nil, nil
  car.devices.gpuName, car.devices.gpu = nil, nil
  if not peripheral or not peripheral.getNames then return end
  local ok, names = pcall(peripheral.getNames)
  if not ok or type(names) ~= "table" then return end
  for i = 1, #names do
    local name = names[i]
    local kind = car.peripheralType(name)
    local device = peripheral.wrap(name)
    if device then
      if not car.devices.port and (kind:find("tm_rsport", 1, true) or (car.hasMethod(name, "getSides") and type(device.setAnalogOutput) == "function")) then
        car.devices.portName, car.devices.port = name, device
      end
      if not car.devices.keyboard and (kind:find("tm_keyboard", 1, true) or type(device.setFireNativeEvents) == "function") then
        car.devices.keyboardName, car.devices.keyboard = name, device
      end
      if not car.devices.gpu and (kind:find("tm_gpu", 1, true) or (type(device.getSize) == "function" and type(device.sync) == "function" and type(device.filledRectangle) == "function")) then
        car.devices.gpuName, car.devices.gpu = name, device
      end
    end
  end
  if car.devices.keyboard and car.devices.keyboard.setFireNativeEvents then
    pcall(car.devices.keyboard.setFireNativeEvents, true)
  end
  if force or previousPortName ~= car.devices.portName then
    car.outputCache.port = {}
  end
end

function car.horizontalPortMap()
  if car.state.portHeading == "east" then
    return { front = "east", right = "south", back = "west", left = "north" }
  elseif car.state.portHeading == "south" then
    return { front = "south", right = "west", back = "north", left = "east" }
  elseif car.state.portHeading == "west" then
    return { front = "west", right = "north", back = "east", left = "south" }
  end
  return { front = "north", right = "east", back = "south", left = "west" }
end

function car.getPortSide(side)
  if side == "top" then return "up" end
  if side == "bottom" then return "down" end
  return car.horizontalPortMap()[side]
end

function car.chassisOutput(side, enabled)
  if not redstone then return false end
  enabled = enabled and true or false
  if car.outputCache.chassis[side] == enabled then return true end
  local ok, err
  if redstone.setAnalogOutput then
    ok, err = pcall(redstone.setAnalogOutput, side, enabled and 15 or 0)
  elseif redstone.setOutput then
    ok, err = pcall(redstone.setOutput, side, enabled and true or false)
  end
  if ok then
    car.outputCache.chassis[side] = enabled
  else
    car.devices.error = tostring(err or "computer output failed")
  end
  return ok == true
end

function car.portOutput(side, enabled)
  local port = car.devices.port
  if not port then return false end
  local worldSide = car.getPortSide(side)
  enabled = enabled and true or false
  if car.outputCache.port[worldSide] == enabled then return true end
  local ok, err
  if port.setAnalogOutput then
    ok, err = pcall(port.setAnalogOutput, worldSide, enabled and 15 or 0)
  elseif port.setAnalogueOutput then
    ok, err = pcall(port.setAnalogueOutput, worldSide, enabled and 15 or 0)
  elseif port.setOutput then
    ok, err = pcall(port.setOutput, worldSide, enabled and true or false)
  end
  if ok then
    car.outputCache.port[worldSide] = enabled
  else
    car.devices.error = tostring(err or "port output failed")
  end
  return ok == true
end

function car.clearPortOutputs()
  local port = car.devices.port
  if not port then return end
  local sides = { "up", "down", "north", "east", "south", "west" }
  for i = 1, #sides do
    if port.setAnalogOutput then
      pcall(port.setAnalogOutput, sides[i], 0)
    elseif port.setAnalogueOutput then
      pcall(port.setAnalogueOutput, sides[i], 0)
    elseif port.setOutput then
      pcall(port.setOutput, sides[i], false)
    end
  end
  car.outputCache.port = {}
end

function car.applyOutputs()
  car.devices.error = nil
  car.chassisOutput("top", car.state.mode == "sport" or car.state.mode == "sport_plus")
  car.chassisOutput("right", car.state.mode == "sport_plus")
  car.chassisOutput("back", car.state.reverse)
  car.chassisOutput("left", car.state.frontDriveOff)
  car.chassisOutput("front", car.state.workshopEngineOff)
  car.chassisOutput("bottom", car.state.driveEngineOff)
  car.portOutput("top", car.state.clutch)
  car.portOutput("left", car.state.workshopBoost)
  car.portOutput("right", (car.state.lighting == "right" or car.state.lighting == "hazard") and car.state.blink)
  car.portOutput("back", (car.state.lighting == "left" or car.state.lighting == "hazard") and car.state.blink)
  car.portOutput("bottom", car.state.lighting == "headlights")
end

function car.setLighting(mode)
  if car.state.lighting == mode then mode = "none" end
  car.state.lighting = mode
  car.state.blink = mode ~= "none" and mode ~= "headlights"
  car.lastBlink = os.clock()
  car.applyOutputs()
end

function car.toggleIndicator()
  car.setLighting("right")
end

function car.cyclePortHeading()
  local current = 1
  for i = 1, #car.headingOrder do
    if car.headingOrder[i] == car.state.portHeading then current = i break end
  end
  car.clearPortOutputs()
  car.state.portHeading = car.headingOrder[(current % #car.headingOrder) + 1]
  settings.portHeading = car.state.portHeading
  saveUserSettings()
  car.applyOutputs()
end

function car.engineOutput(side, val)
  car.state.driveEngineOff = not (val and true or false)
  car.applyOutputs()
end

function car.driveOutput(side, val)
  car.state.clutch = (val and true or false) or car.state.wHeld or car.state.sHeld
  car.applyOutputs()
end

function car.canToggleEngine()
  local now = os.clock()
  if (now - lastEngineClick) < ENGINE_CLICK_COOLDOWN then return false end
  lastEngineClick = now
  _G.lastEngineClick = lastEngineClick
  return true
end

function car.startPulse()
  car.engineOutput(ENGINE_SIDE, car.engineOn)
end

function car.stopPulse()
  car.pulseTimer = nil
end

function car.setEngine(state)
  if not isDiesel then return end
  if type(ENGINE_SIDE) ~= "string" or ENGINE_SIDE == "" then return end
  state = state and true or false
  if state == car.engineOn then return end
  car.engineOn = state
  car.startPulse()
  if not car.engineOn and car.cruiseOn then
    car.cruiseOn = false
    car.driveOutput(DRIVE_SIDE, false)
  end
end

function car.toggleEngine()
  car.setEngine(not car.engineOn)
end

function car.setDriveMode(mode)
  if mode ~= "normal" and mode ~= "sport" and mode ~= "sport_plus" then return end
  car.driveMode = mode
  car.state.mode = mode == "normal" and "standard" or mode
  car.applyOutputs()
end

car.scanDevices(true)
car.engineOutput(ENGINE_SIDE, not isDiesel)
car.setDriveMode(car.driveMode)
car.driveOutput(DRIVE_SIDE, false)

local speedBuf = {}
local function smoothBps(v)
  local n = tonumber(settings.speedSmooth) or 4
  if n <= 1 then
    speedBuf[1] = v
    for i = 2, #speedBuf do speedBuf[i] = nil end
    return v
  end
  speedBuf[#speedBuf + 1] = v
  while #speedBuf > n do table.remove(speedBuf, 1) end
  local s = 0
  for i = 1, #speedBuf do s = s + speedBuf[i] end
  return s / math.max(1, #speedBuf)
end

local speedBps = 0
local curPos = nil
local prevPos = nil
local lastT = nil
local noPosStreak = 0
local lastRawBps = nil
local MAX_ACCEL = tonumber(_G.ROADROVER_MAX_ACCEL) or 80

resetSpeedState = function(keepPos)
  speedBuf = {}
  speedBps = 0
  curPos = nil
  prevPos = nil
  lastT = nil
  noPosStreak = 0
  lastRawBps = nil
  if not keepPos then
    ship = nil
    getPos = nil
    posFnName = nil
    lastRescan = 0
  end
end

local function clampSpeedSpike(raw, dt)
  if not lastRawBps then
    lastRawBps = raw
    return raw
  end
  local maxDelta = MAX_ACCEL * dt
  if maxDelta < 2 then maxDelta = 2 end
  local lo = lastRawBps - maxDelta
  local hi = lastRawBps + maxDelta
  if raw < lo then raw = lo
  elseif raw > hi then raw = hi end
  lastRawBps = raw
  return raw
end

local function tick()
  if not getPos then rescan(true) else rescan(false) end
  debugInfo.posFn = posFnName or "none"

  local t = os.clock()
  local p = getPos and getPos() or nil
  if not p then
    noPosStreak = noPosStreak + 1
    if noPosStreak >= 5 then
      ship = nil
      getPos = nil
      posFnName = nil
      rescan(true)
      noPosStreak = 0
    end
    speedBps = settings.smoothEnabled and smoothBps(0) or 0
    curPos = nil; prevPos = nil; lastT = nil
    if not getPos then
      debugInfo.reason = "no position fn"
    else
      debugInfo.reason = "no position"
    end
    return
  end
  noPosStreak = 0

  curPos = p
  if not prevPos or not lastT then
    prevPos = curPos
    lastT = t
    speedBps = settings.smoothEnabled and smoothBps(0) or 0
    debugInfo.reason = "init"
    return
  end

  local dt = t - lastT
  lastT = t
  if dt <= 0 or dt > 1.2 then
    prevPos = curPos
    debugInfo.reason = "dt " .. fmt(dt, 2)
    debugInfo.dt = dt
    return
  end

  local d = dist(curPos, prevPos)
  prevPos = curPos
  if d < 0 or d > 120 then
    debugInfo.reason = "d " .. fmt(d, 1)
    debugInfo.d = d
    return
  end

  local rawBps = d / dt
  if rawBps < 0 then rawBps = 0 end
  if rawBps > 999 then rawBps = 999 end
  rawBps = clampSpeedSpike(rawBps, dt)

  stats.odometer = (stats.odometer or 0) + d
  stats.totalTime = (stats.totalTime or 0) + dt
  if rawBps > 0.05 then
    stats.movingTime = (stats.movingTime or 0) + dt
  end
  if rawBps > (stats.maxBps or 0) then
    stats.maxBps = rawBps
  end
  if (t - lastStatsSave) > 5 then
    saveUserStats()
    lastStatsSave = t
  end

  if settings.smoothEnabled then
    speedBps = smoothBps(rawBps)
  else
    speedBps = rawBps
  end
  debugInfo.reason = "ok"
  debugInfo.dt = dt
  debugInfo.d = d
end

local ui = term.current()
local leftWin, centerWin, rightWin
local layout = {}

local function getPrimaryMonitor()
  if not peripheral or not peripheral.getNames then return nil end
  local ok, names = pcall(peripheral.getNames)
  if not ok or type(names) ~= "table" then return nil end
  for _, name in ipairs(names) do
    local ok2, typ = pcall(peripheral.getType, name)
    if ok2 and typ == "monitor" then
      local m = peripheral.wrap(name)
      if m then return m end
    end
  end
  return nil
end

local function rebuildUI()
  local mon = getPrimaryMonitor()
  if mon then
    ui = mon
    if mon.setTextScale then pcall(function() mon.setTextScale(settings.textScale) end) end
  else
    ui = term.current()
  end
  term.redirect(ui)

  local w, h = term.getSize()
  local monW = math.floor(w / 3)
  local leftW = monW
  local rightMonitorW = math.max(1, w - (2 * monW))
  local rightW = clamp(math.floor(rightMonitorW * 0.22), 6, math.min(10, rightMonitorW))
  local centerW = w - leftW - rightW

  local leftX = 1
  local centerX = leftX + leftW
  local rightX = w - rightW + 1

  leftWin = window.create(ui, leftX, 1, leftW, h)
  centerWin = window.create(ui, centerX, 1, centerW, h)
  rightWin = window.create(ui, rightX, 1, rightW, h)

  layout = {
    w = w, h = h,
    leftX = leftX, centerX = centerX, rightX = rightX,
    leftW = leftW, centerW = centerW, rightW = rightW,
    monW = monW, rightMonitorW = rightMonitorW
  }
end

local function writeAt(win, x, y, s, fg, bg)
  win.setCursorPos(x, y)
  win.setBackgroundColor(bg or COLORS.bg)
  win.setTextColor(fg or COLORS.fg)
  win.write(s)
end

local function clearWin(win, bg, fg)
  win.setBackgroundColor(bg or COLORS.bg)
  win.setTextColor(fg or COLORS.fg)
  win.clear()
end

local function fillRect(win, x, y, w, h, bg)
  bg = bg or COLORS.bg
  if paintutils and paintutils.drawFilledBox then
    local prev = term.current()
    term.redirect(win)
    paintutils.drawFilledBox(x, y, x + w - 1, y + h - 1, bg)
    term.redirect(prev)
    return
  end
  for yy = y, y + h - 1 do
    win.setCursorPos(x, yy)
    win.setBackgroundColor(bg)
    win.write((" "):rep(w))
  end
end

sanitizeRRIDInput = function(s)
  s = tostring(s or ""):upper()
  s = s:gsub("[^A-Z0-9 _-]", "")
  s = s:gsub("%s+", " ")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  if #s > RRID_MAX then s = s:sub(1, RRID_MAX) end
  return s
end

rridKey = function(s)
  s = sanitizeRRIDInput(s)
  if s == "" then return "" end
  s = safeName(s:upper())
  if #s > RRID_MAX then s = s:sub(1, RRID_MAX) end
  return s
end

displayRRID = function(s, maxLen)
  s = tostring(s or "")
  s = safe(s)
  local n = tonumber(maxLen) or RRID_MAX
  if #s > n then s = s:sub(1, n) end
  return s
end

local function encodeDirName(display)
  display = sanitizeRRIDInput(display)
  local out = {}
  for i = 1, #display do
    local ch = display:sub(i, i)
    if ch == "_" then
      out[#out + 1] = "__"
    elseif ch == " " then
      out[#out + 1] = "_S"
    elseif ch == "-" then
      out[#out + 1] = "_D"
    else
      out[#out + 1] = ch
    end
  end
  return table.concat(out)
end

local function decodeDirName(dir)
  local out = {}
  local i = 1
  while i <= #dir do
    local ch = dir:sub(i, i)
    if ch == "_" then
      local nxt = dir:sub(i + 1, i + 1)
      if nxt == "_" then
        out[#out + 1] = "_"
        i = i + 2
      elseif nxt == "S" then
        out[#out + 1] = " "
        i = i + 2
      elseif nxt == "D" then
        out[#out + 1] = "-"
        i = i + 2
      else
        out[#out + 1] = "_"
        i = i + 1
      end
    else
      out[#out + 1] = ch
      i = i + 1
    end
  end
  return table.concat(out)
end

userDirKey = function(display)
  local base = rridKey(display)
  if base == "" then return "" end
  local encoded = encodeDirName(display)
  local usersDir = fs.combine(BASE_DIR, "users")
  local encodedPath = fs.combine(usersDir, encoded)
  if fs.exists(encodedPath) then return encoded end
  local legacyPath = fs.combine(usersDir, base)
  if fs.exists(legacyPath) then
    local legacyDisplay = loadProfileDisplay(legacyPath)
    if legacyDisplay then
      if sanitizeRRIDInput(legacyDisplay) == sanitizeRRIDInput(display) then
        return base
      end
      return encoded
    end
    return base
  end
  return encoded
end

isValidRRIDDisplay = function(s, minLen)
  local out = sanitizeRRIDInput(s)
  local need = tonumber(minLen) or RRID_MIN
  if need < 1 then need = 1 end
  return #out >= need
end

isValidRRIDKey = function(s)
  s = tostring(s or "")
  local n = #s
  if n < RRID_MIN or n > RRID_MAX then return false end
  if not s:match("^[A-Z0-9_-]+$") then return false end
  return true
end

local function promptRRID(title, allowCancel)
  local prev = term.current()
  term.redirect(ui)
  timerResetRequested = true
  local w, h = term.getSize()
  local input = ""
  local maxLen = math.max(1, math.min(RRID_MAX, w - 4))
  local minLen = math.min(RRID_MIN, maxLen)
  local boxes = {}

  local function addBox(id, x, y, bw, bh)
    boxes[#boxes + 1] = { id = id, x1 = x, y1 = y, x2 = x + bw - 1, y2 = y + bh - 1 }
  end

  local function hitBox(b, x, y)
    return b and x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2
  end

  local function pickKeySize()
    local keyW, gap = 3, 1
    local rowW = 10 * keyW + 9 * gap
    if rowW > w - 2 then
      keyW, gap = 2, 1
      rowW = 10 * keyW + 9 * gap
    end
    if rowW > w - 2 then
      keyW, gap = 1, 0
    end
    return keyW, gap
  end

  local function draw()
    term.setBackgroundColor(COLORS.bg)
    term.setTextColor(COLORS.fg)
    term.clear()

    local prompt = "Enter RoadRover ID"
    local py = 1
    local px = math.max(1, math.floor((w - #prompt) / 2) + 1)
    writeAt(ui, px, py, prompt, COLORS.fg, COLORS.bg)

    local keyW, gap = pickKeySize()
    gap = 0
    local keyH = 1
    local rowGap = 1
    local rows = { "1234567890", "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM" }
    local spaceW = keyW * 5
    local delW = keyW * 3
    local createW = keyW * 5
    local cancelW = keyW * 5
    local specialGap = 1
    local total = spaceW + delW + createW + (allowCancel and cancelW or 0) + specialGap * (allowCancel and 3 or 2)
    if total > w - 2 then
      spaceW = keyW * 4
      delW = keyW * 2
      createW = keyW * 4
      cancelW = keyW * 4
      total = spaceW + delW + createW + (allowCancel and cancelW or 0) + specialGap * (allowCancel and 3 or 2)
    end
    if total > w - 2 then specialGap = 0 end
    total = spaceW + delW + createW + (allowCancel and cancelW or 0) + specialGap * (allowCancel and 3 or 2)

    local maxRowW = 0
    for r = 1, #rows do
      local rowW = #rows[r] * keyW + (#rows[r] - 1) * gap
      if rowW > maxRowW then maxRowW = rowW end
    end
    local panelW = math.min(w - 2, math.max(maxRowW, total))
    local panelX = math.max(1, math.floor((w - panelW) / 2) + 1)

    local boxW = math.min(w - 2, math.max(maxLen + 2, panelW))
    local boxX = math.max(1, math.floor((w - boxW) / 2) + 1)
    local boxY = py + 1
    fillRect(ui, boxX, boxY, boxW, 1, colors.gray)
    writeAt(ui, boxX + 1, boxY, trim(input, boxW - 2), themeColor(colors.white), colors.gray)

    boxes = {}

    local startY = boxY + 2
    local keyboardH = #rows * keyH + (#rows - 1) * rowGap + keyH + rowGap
    if startY + keyboardH - 1 > h then rowGap = 0 end
    keyboardH = #rows * keyH + (#rows - 1) * rowGap + keyH + rowGap

    local panelY = startY - 1
    local panelH = keyboardH + 2
    local frameX = (panelX > 1) and (panelX - 1) or panelX
    local frameW = panelW + (panelX > 1 and 2 or 1)
    fillRect(ui, frameX, panelY, frameW, panelH, COLORS.bg)

    for r = 1, #rows do
      local row = rows[r]
      local rowW = #row * keyW + (#row - 1) * gap
      local rowX = panelX + math.floor((panelW - rowW) / 2)
      local y = startY + (r - 1) * (keyH + rowGap)
      for i = 1, #row do
        local ch = row:sub(i, i)
        local x = rowX + (i - 1) * (keyW + gap)
        fillRect(ui, x, y, keyW, keyH, COLORS.panel)
        local cx = x + math.floor((keyW - 1) / 2)
        writeAt(ui, cx, y, ch, COLORS.panelText, COLORS.panel)
        addBox(ch, x, y, keyW, keyH)
      end
    end

    local specialY = startY + (#rows) * (keyH + rowGap) + 1
    local sx = panelX + math.floor((panelW - total) / 2)
    local y = specialY

    fillRect(ui, sx, y, spaceW, keyH, COLORS.panel)
    writeAt(ui, sx + math.floor((spaceW - 5) / 2), y, "SPACE", COLORS.panelText, COLORS.panel)
    addBox("SPACE", sx, y, spaceW, keyH)
    sx = sx + spaceW + specialGap

    fillRect(ui, sx, y, delW, keyH, COLORS.panel)
    writeAt(ui, sx + math.floor((delW - 3) / 2), y, "DEL", COLORS.panelText, COLORS.panel)
    addBox("DEL", sx, y, delW, keyH)
    sx = sx + delW + specialGap

    fillRect(ui, sx, y, createW, keyH, COLORS.panel)
    writeAt(ui, sx + math.floor((createW - 6) / 2), y, "CREATE", COLORS.panelText, COLORS.panel)
    addBox("CREATE", sx, y, createW, keyH)
    sx = sx + createW + specialGap

    if allowCancel then
      fillRect(ui, sx, y, cancelW, keyH, COLORS.panel)
      writeAt(ui, sx + math.floor((cancelW - 6) / 2), y, "CANCEL", COLORS.panelText, COLORS.panel)
      addBox("CANCEL", sx, y, cancelW, keyH)
    end
  end

  local function applyInputAdd(ch)
    if #input >= maxLen then return end
    input = sanitizeRRIDInput(input .. ch)
  end

  local function applyInputDel()
    input = input:sub(1, -2)
    input = sanitizeRRIDInput(input)
  end

  draw()

  while true do
    local ev, a, b, c = os.pullEvent()
    if ev == "monitor_touch" or ev == "mouse_click" then
      local mx, my = b, c
      for i = 1, #boxes do
        local b2 = boxes[i]
        if hitBox(b2, mx, my) then
          local id = b2.id
          if id == "DEL" then
            applyInputDel()
          elseif id == "SPACE" then
            applyInputAdd(" ")
          elseif id == "CREATE" then
            local out = sanitizeRRIDInput(input)
            if isValidRRIDDisplay(out, minLen) then
              term.redirect(prev)
              return out
            end
          elseif id == "CANCEL" then
            term.redirect(prev)
            return nil
          else
            applyInputAdd(id)
          end
          draw()
          break
        end
      end
    elseif ev == "char" then
      local ch = a
      if ch == " " then
        applyInputAdd(" ")
      elseif ch:match("%a") or ch:match("%d") then
        applyInputAdd(ch:upper())
      end
      draw()
    elseif ev == "key" and keys then
      if a == keys.backspace then
        applyInputDel()
        draw()
      elseif a == keys.enter then
        local out = sanitizeRRIDInput(input)
        if isValidRRIDDisplay(out, minLen) then
          term.redirect(prev)
          return out
        end
      elseif a == keys.escape and allowCancel then
        term.redirect(prev)
        return nil
      end
    end
  end
end

local addRRID

local function changeRRID()
  return addRRID()
end

local function ensureProfile()
  local rrid = loadRRID()
  if rrid and rrid ~= "" then
    return setCurrentUser(rrid)
  end
  while true do
    local created = promptRRID("RoadRover Setup", false)
    if created and created ~= "" then
      saveRRID(created)
      return setCurrentUser(created)
    end
  end
end

local function listExistingUsers()
  ensureBaseDirs()
  local usersDir = fs.combine(BASE_DIR, "users")
  if not fs.exists(usersDir) or not fs.isDir(usersDir) then return {} end
  local entries = fs.list(usersDir)
  local out = {}
  local seen = {}
  for i = 1, #entries do
    local name = entries[i]
    local p = fs.combine(usersDir, name)
    if fs.isDir(p) then
      local disp = loadProfileDisplay(p) or decodeDirName(name)
      disp = sanitizeRRIDInput(disp)
      if disp ~= "" and isValidRRIDDisplay(disp, RRID_MIN) and not seen[disp] then
        seen[disp] = true
        out[#out + 1] = disp
      end
    end
  end
  table.sort(out)
  return out
end

local function promptSelectRRID(list)
  local prev = term.current()
  term.redirect(ui)
  timerResetRequested = true
  local w, h = term.getSize()
  local offset = 1
  local itemBoxes = {}
  local upBox, downBox, createBox, closeBox = nil, nil, nil, nil

  local popupW = clamp(math.floor(w * 0.45), 18, math.min(26, w - 4))
  local popupH = math.min(h - 4, popupW + 4)
  if popupH < 8 then popupH = math.min(h - 2, 8) end

  local popupX = math.max(1, math.floor((w - popupW) / 2) + 1)
  local popupY = math.max(1, math.floor((h - popupH) / 2) + 1)

  local listX = popupX + 1
  local listY = popupY + 3
  local listW = popupW - 2
  local listH = math.max(1, popupH - 4)

  local function maxOffset()
    return math.max(1, #list - listH + 1)
  end

  local function draw()
    redraw()
    term.setBackgroundColor(COLORS.bg)
    term.setTextColor(COLORS.fg)

    fillRect(ui, popupX, popupY, popupW, popupH, COLORS.bg)
    local shadowX = popupX + popupW
    if shadowX <= w then
      for yy = popupY + 1, popupY + popupH do
        writeAt(ui, shadowX, yy, " ", COLORS.fg, colors.lightGray)
      end
    end
    local shadowY = popupY + popupH
    if shadowY <= h then
      local sw = math.min(popupW, w - popupX + 1)
      fillRect(ui, popupX + 1, shadowY, sw, 1, colors.lightGray)
    end

    local topLabel = "CREATE RRID"
    fillRect(ui, popupX + 1, popupY + 1, popupW - 2, 1, COLORS.panel)
    local tx = popupX + 1 + math.floor((popupW - 2 - #topLabel) / 2)
    writeAt(ui, tx, popupY + 1, topLabel, COLORS.panelText, COLORS.panel)
    createBox = { x1 = popupX + 1, y1 = popupY + 1, x2 = popupX + popupW - 2, y2 = popupY + 1 }

    writeAt(ui, popupX + 1, popupY + 2, ("-"):rep(popupW - 2), COLORS.fg, COLORS.bg)

    local closeX = popupX + popupW - 1
    writeAt(ui, closeX, popupY, "X", COLORS.panelText, COLORS.panel)
    closeBox = { x1 = closeX, y1 = popupY, x2 = closeX, y2 = popupY }

    local navX = math.max(1, popupX - 3)
    local navY = listY
    local navUp = "/\\"
    local navDn = "\\/"
    writeAt(ui, navX, navY, navUp, COLORS.panelText, COLORS.panel)
    writeAt(ui, navX, navY + 2, navDn, COLORS.panelText, COLORS.panel)
    upBox = { x1 = navX, y1 = navY, x2 = navX + #navUp - 1, y2 = navY }
    downBox = { x1 = navX, y1 = navY + 2, x2 = navX + #navDn - 1, y2 = navY + 2 }

    itemBoxes = {}
    fillRect(ui, listX, listY, listW, listH, colors.lightGray)
    for i = 1, listH do
      local idx = offset + i - 1
      if idx > #list then break end
      local name = displayRRID(list[idx], listW - 2)
      local y = listY + i - 1
      local active = (sanitizeRRIDInput(list[idx]) == sanitizeRRIDInput(USER_NAME))
      local itemBg = active and themeColor(colors.black) or themeColor(colors.white)
      local itemFg = active and themeColor(colors.white) or themeColor(colors.black)
      fillRect(ui, listX, y, listW, 1, itemBg)
      local nx = listX + math.floor((listW - #name) / 2)
      writeAt(ui, nx, y, name, itemFg, itemBg)
      itemBoxes[#itemBoxes + 1] = {
        id = list[idx],
        x1 = listX,
        y1 = y,
        x2 = listX + listW - 1,
        y2 = y
      }
    end
  end

  local function hitBox(b, x, y)
    return b and x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2
  end

  draw()

  while true do
    local ev, a, b, c = os.pullEvent()
    if ev == "monitor_touch" or ev == "mouse_click" then
      local mx, my = b, c
      if hitBox(closeBox, mx, my) then
        term.redirect(prev)
        return nil
      end
      if hitBox(createBox, mx, my) then
        term.redirect(prev)
        return "__create__"
      end
      if hitBox(upBox, mx, my) then
        offset = offset - 1
        if offset < 1 then offset = maxOffset() end
        draw()
      elseif hitBox(downBox, mx, my) then
        offset = offset + 1
        if offset > maxOffset() then offset = 1 end
        draw()
      else
        for i = 1, #itemBoxes do
          if hitBox(itemBoxes[i], mx, my) then
            term.redirect(prev)
            return itemBoxes[i].id
          end
        end
      end
    elseif ev == "key" and keys then
      if a == keys.up then
        offset = offset - 1
        if offset < 1 then offset = maxOffset() end
        draw()
      elseif a == keys.down then
        offset = offset + 1
        if offset > maxOffset() then offset = 1 end
        draw()
      elseif a == keys.enter then
        term.redirect(prev)
        return "__create__"
      elseif a == keys.escape then
        term.redirect(prev)
        return nil
      end
    end
  end
end

addRRID = function()
  local users = listExistingUsers()
  if #users > 0 then
    local choice = promptSelectRRID(users)
    if choice == "__create__" then
      local rrid = promptRRID("Create RRID", true)
      if rrid and rrid ~= "" then
        saveRRID(rrid)
        if setCurrentUser(rrid) then rebuildUI() end
        return true
      end
      return false
    elseif choice and choice ~= "" then
      saveRRID(choice)
      if setCurrentUser(choice) then rebuildUI() end
      return true
    end
    return false
  end

  local rrid = promptRRID("Create RRID", true)
  if rrid and rrid ~= "" then
    saveRRID(rrid)
    if setCurrentUser(rrid) then rebuildUI() end
    return true
  end
  return false
end

local function wrap2(label, w)
  label = safe(label)
  w = math.max(1, math.floor(w or #label))
  local words = {}
  for s in label:gmatch("%S+") do words[#words + 1] = s end
  if #words >= 2 then
    local l1 = words[1]
    local i = 2
    while i <= #words and (#l1 + 1 + #words[i]) <= w do l1 = l1 .. " " .. words[i]; i = i + 1 end
    local l2 = table.concat(words, " ", i)
    if l2 == "" then l2 = nil end
    return trim(l1, w), l2 and trim(l2, w) or nil
  end
  if #label <= w then return label, nil end
  return trim(label:sub(1, w), w), trim(label:sub(w + 1, w + w), w)
end

local tabs = {
  { id = "home", title = "Home", label = "Home", page = 1 },
  { id = "drive", title = "Drive Controls", label = "Drive", page = 1 },
  { id = "settings", title = "Settings", label = "Set", page = 1 },
  { id = "stats", title = "Statistics", label = "Stats", page = 1 },
  { id = "map", title = "Map", label = "Map", page = 2 },
  { id = "about", title = "About", label = "About", page = 2 },
  { id = "actions", title = "Quick Actions", label = "Actions", page = 2 },
}
local activeTab = 1
local tabPage = (tabs[activeTab] and tabs[activeTab].page) or 1
local tabBoxes = {}
local pageBox = nil
local engineBox = nil
local cruiseBox = nil
local quickBox = nil
local quickMapBox = nil
local quickSettingsBox = nil
local modeStandardBox = nil
local modeSportBox = nil
local actionBoxes = {}
local settingsBoxes = {}
local actionViews = { "actions", "info" }
local actionViewIndex = 1
local settingsViewIndex = 1

local function drawHeader(win, text, w)
  local label = safe(text or "")
  if label == "" then
    return 0
  end

  -- Normal header (slightly emphasized by centering)
  local t = trim(label, w)
  local x = math.max(1, math.floor((w - #t) / 2) + 1)
  writeAt(win, x, 1, t, COLORS.fg, COLORS.bg)
  return 1
end

local function drawSpeedBig(win, x, y, num, bf)
  bf = bf or loadBigFont()
  if not (bf and type(bf.bigWrite) == "function") then
    writeAt(win, x, y, num, COLORS.fg, COLORS.bg)
    return 1
  end

  if type(bf.writeOn) == "function" then
    bf.writeOn(win, 1, num, x, y)
  else
    local prev = term.current()
    term.redirect(win)
    term.setCursorPos(x, y)
    term.setBackgroundColor(COLORS.bg)
    term.setTextColor(COLORS.fg)
    bf.bigWrite(num)
    term.redirect(prev)
  end

  return 5
end

local function drawBigLabel(win, x, y, text, bg, fg, bf)
  local prev = term.current()
  term.redirect(win)
  term.setCursorPos(x, y)
  term.setBackgroundColor(bg)
  term.setTextColor(fg)
  bf.bigWrite(text)
  term.redirect(prev)
end

local function drawQuickActionsBlock(bigX, bigY, bigW, bigH)
  if bigH < 2 then return nil end
  fillRect(centerWin, bigX, bigY, bigW, bigH, COLORS.panel)
  local l1 = "Quick"
  local l2 = "Actions"
  local bf = loadBigFont()
  local canBig = bf and type(bf.bigWrite) == "function"
    and bigTextWidth(l1) <= bigW and bigTextWidth(l2) <= bigW
    and bigH >= 10
  if canBig then
    local totalH = 10
    local ty = bigY + math.floor((bigH - totalH) / 2)
    local x1 = bigX + math.floor((bigW - bigTextWidth(l1)) / 2)
    local x2 = bigX + math.floor((bigW - bigTextWidth(l2)) / 2)
    drawBigLabel(centerWin, x1, ty, l1, COLORS.panel, COLORS.panelText, bf)
    drawBigLabel(centerWin, x2, ty + 5, l2, COLORS.panel, COLORS.panelText, bf)
  else
    local ty = bigY + math.floor((bigH - 2) / 2)
    writeAt(centerWin, bigX + math.floor((bigW - #l1) / 2), ty, l1, COLORS.panelText, COLORS.panel)
    writeAt(centerWin, bigX + math.floor((bigW - #l2) / 2), ty + 1, l2, COLORS.panelText, COLORS.panel)
  end
  return {
    x1 = layout.centerX + bigX - 1,
    y1 = bigY,
    x2 = layout.centerX + bigX + bigW - 2,
    y2 = bigY + bigH - 1
  }
end

local function computeHomeLayout(y0)
  local btnH = 2
  local margin = 1
  local gap = 1
  local availableW = layout.centerW - margin
  local btnW = math.floor((availableW - 3 * gap) / 4)
  if btnW < 2 then
    gap = 0
    btnW = math.max(1, math.floor(availableW / 4))
  end
  if btnW < 1 then btnW = 1 end

  local blockW = btnW * 4 + gap * 3
  local blockX = math.max(1, layout.centerW - blockW - margin + 1)
  local mapX = blockX
  local settingsX = mapX + btnW + gap
  local cruiseX = settingsX + btnW + gap
  local engineX = cruiseX + btnW + gap
  if engineX + btnW - 1 > layout.centerW then
    engineX = layout.centerW - btnW + 1
    cruiseX = engineX - gap - btnW
    settingsX = cruiseX - gap - btnW
    mapX = settingsX - gap - btnW
  end

  local btnY = layout.h - btnH + 1
  local cruiseY = btnY

  local bigX = cruiseX
  local bigW = (engineX + btnW - 1) - cruiseX + 1
  local bigY = math.max(2, y0 + 1)
  local bigBottom = cruiseY - 2
  if bigBottom < bigY then bigBottom = bigY end
  local bigH = bigBottom - bigY + 1

  local colW = btnW
  local colY = bigY
  local colH = (btnY + btnH - 1) - colY + 1

  return {
    btnH = btnH,
    btnW = btnW,
    btnY = btnY,
    cruiseY = cruiseY,
    bigX = bigX,
    bigY = bigY,
    bigW = bigW,
    bigH = bigH,
    mapX = mapX,
    settingsX = settingsX,
    cruiseX = cruiseX,
    engineX = engineX,
    colW = colW,
    colY = colY,
    colH = colH
  }
end

local drawVerticalLabel

local function drawHomeQuickColumns(l)
  if l.colH >= 2 and l.mapX >= 1 then
    fillRect(centerWin, l.mapX, l.colY, l.colW, l.colH, COLORS.panel)
    drawVerticalLabel(centerWin, l.mapX, l.colY, l.colW, l.colH, "MAP", COLORS.panelText, COLORS.panel)
    quickMapBox = {
      x1 = layout.centerX + l.mapX - 1,
      y1 = l.colY,
      x2 = layout.centerX + l.mapX + l.colW - 2,
      y2 = l.colY + l.colH - 1
    }
  end
  if l.colH >= 2 and l.settingsX >= 1 then
    fillRect(centerWin, l.settingsX, l.colY, l.colW, l.colH, COLORS.panel)
    drawVerticalLabel(centerWin, l.settingsX, l.colY, l.colW, l.colH, "SETTINGS", COLORS.panelText, COLORS.panel, 2)
    quickSettingsBox = {
      x1 = layout.centerX + l.settingsX - 1,
      y1 = l.colY,
      x2 = layout.centerX + l.settingsX + l.colW - 2,
      y2 = l.colY + l.colH - 1
    }
  end
end

local function drawHomeCruiseAndEngine(l)
  fillRect(centerWin, l.cruiseX, l.cruiseY, l.btnW, l.btnH, COLORS.panel)
  local c1 = "CRUISE"
  local c2 = car.cruiseOn and "ON" or "OFF"
  writeAt(centerWin, l.cruiseX + math.floor((l.btnW - #c1) / 2), l.cruiseY, c1, COLORS.panelText, COLORS.panel)
  writeAt(centerWin, l.cruiseX + math.floor((l.btnW - #c2) / 2), l.cruiseY + 1, c2, COLORS.panelText, COLORS.panel)
  cruiseBox = {
    x1 = layout.centerX + l.cruiseX - 1,
    y1 = l.cruiseY,
    x2 = layout.centerX + l.cruiseX + l.btnW - 2,
    y2 = l.cruiseY + l.btnH - 1
  }

  if isDiesel then
    fillRect(centerWin, l.engineX, l.btnY, l.btnW, l.btnH, COLORS.panel)
    local label1 = "ENGINE"
    local label2 = car.engineOn and "STOP" or "START"
    writeAt(centerWin, l.engineX + math.floor((l.btnW - #label1) / 2), l.btnY, label1, COLORS.panelText, COLORS.panel)
    writeAt(centerWin, l.engineX + math.floor((l.btnW - #label2) / 2), l.btnY + 1, label2, COLORS.panelText, COLORS.panel)

    engineBox = {
      x1 = layout.centerX + l.engineX - 1,
      y1 = l.btnY,
      x2 = layout.centerX + l.engineX + l.btnW - 2,
      y2 = l.btnY + l.btnH - 1
    }
  else
    local stdBg = (car.driveMode == "normal") and COLORS.panel or COLORS.activeBg
    local stdFg = (car.driveMode == "normal") and COLORS.panelText or COLORS.activeText
    local sportBg = (car.driveMode == "sport") and COLORS.panel or COLORS.activeBg
    local sportFg = (car.driveMode == "sport") and COLORS.panelText or COLORS.activeText
    local stdLabel = trim("ECO", l.btnW)
    local sportLabel = trim("SPORT", l.btnW)

    fillRect(centerWin, l.engineX, l.btnY, l.btnW, 1, stdBg)
    writeAt(centerWin, l.engineX + math.floor((l.btnW - #stdLabel) / 2), l.btnY, stdLabel, stdFg, stdBg)
    fillRect(centerWin, l.engineX, l.btnY + 1, l.btnW, 1, sportBg)
    writeAt(centerWin, l.engineX + math.floor((l.btnW - #sportLabel) / 2), l.btnY + 1, sportLabel, sportFg, sportBg)

    modeStandardBox = {
      x1 = layout.centerX + l.engineX - 1,
      y1 = l.btnY,
      x2 = layout.centerX + l.engineX + l.btnW - 2,
      y2 = l.btnY
    }
    modeSportBox = {
      x1 = layout.centerX + l.engineX - 1,
      y1 = l.btnY + 1,
      x2 = layout.centerX + l.engineX + l.btnW - 2,
      y2 = l.btnY + 1
    }
    engineBox = nil
  end
end

local function drawLeft()
  clearWin(leftWin, COLORS.bg, COLORS.fg)

  local dayNum = tonumber(os.date("%d")) or 0
  local dateText = string.format("%s %d %s", os.date("%a"), dayNum, os.date("%b"))
  writeAt(leftWin, 1, 1, trim(dateText, layout.leftW), COLORS.fg, COLORS.bg)

  local kmh = speedBps * 3.6
  local speedVal = kmh
  if settings.units == "MP/H" then
    speedVal = kmh * 0.621371
  elseif settings.units == "B/S" then
    speedVal = speedBps
  end
  local num = tostring(math.floor(speedVal + 0.5))
  local bf = loadBigFont()
  local canBig = bf and type(bf.bigWrite) == "function" and bigTextWidth(num) <= layout.leftW
  local bw = canBig and bigTextWidth(num) or #num
  local bx = math.max(1, math.floor((layout.leftW - bw) / 2) + 1)

  local bigH = canBig and 5 or 1
  local by = math.floor((layout.h - bigH) / 2) + SPEED_Y_OFFSET
  if by < 3 then by = 3 end

  if canBig then
    drawSpeedBig(leftWin, bx, by, num, bf)
  else
    writeAt(leftWin, bx, by, num, COLORS.fg, COLORS.bg)
  end

  local unitText = "kmh"
  if settings.units == "MP/H" then unitText = "mph"
  elseif settings.units == "B/S" then unitText = "bs" end
  local uy = by + bigH + UNIT_Y_OFFSET
  if uy < 1 then uy = 1 end
  if uy <= layout.h then
    local ux = math.max(1, math.floor((layout.leftW - #unitText) / 2) + 1)
    writeAt(leftWin, ux, uy, unitText, COLORS.fg, COLORS.bg)
  end

  if DEBUG then
    local lines = {
      "POS: " .. tostring(debugInfo.posFn or "none"),
      "STATE: " .. tostring(debugInfo.reason or "n/a"),
      "BPS: " .. fmt(speedBps, 2)
    }
    local baseY = layout.h - #lines + 1
    if baseY < 1 then baseY = 1 end
    for i = 1, #lines do
      writeAt(leftWin, 1, baseY + i - 1, trim(lines[i], layout.leftW), COLORS.fg, COLORS.bg)
    end
  end

  engineBox = nil
end

local function centerText(win, y, text, w, fg, bg)
  local x = math.max(1, math.floor((w - #text) / 2) + 1)
  writeAt(win, x, y, text, fg, bg)
end

drawVerticalLabel = function(win, x, y, w, h, text, fg, bg, chunkLenOverride)
  text = safe(text):gsub("%s+", "")
  if text == "" then return end
  text = text:upper()
  local n = #text
  if h < 2 or n <= 0 then return end
  local chunkLen = tonumber(chunkLenOverride) or math.ceil(n / h)
  if chunkLen < 1 then chunkLen = 1 end
  local chunks = {}
  local i = 1
  while i <= n do
    chunks[#chunks + 1] = trim(text:sub(i, i + chunkLen - 1), w)
    i = i + chunkLen
  end
  local total = #chunks
  local start = y + math.floor((h - total) / 2)
  for r = 1, total do
    local chunk = chunks[r]
    local cx = x + math.floor((w - #chunk) / 2)
    writeAt(win, cx, start + r - 1, chunk, fg, bg)
  end
end

local function drawVertical(...)
  return drawVerticalLabel(...)
end

local function drawHome(y0)
  local uname = displayUserName()
  if uname ~= "" then
    local label = "RRID: " .. uname
    label = trim(label, math.max(1, layout.centerW - 1))
    local ux = layout.centerW - #label - 1
    if ux < 1 then ux = 1 end
    writeAt(centerWin, ux, 1, label, COLORS.fg, COLORS.bg)
  end

  cruiseBox = nil
  local l = computeHomeLayout(y0)
  quickBox = drawQuickActionsBlock(l.bigX, l.bigY, l.bigW, l.bigH)
  drawHomeQuickColumns(l)
  drawHomeCruiseAndEngine(l)
end

local function drawStats(y0)
  actionBoxes = {}
  settingsBoxes = {}
  engineBox = nil
  local odo = tonumber(stats.odometer) or 0
  local km = odo / 1000
  local totalTime = tonumber(stats.totalTime) or 0
  local movingTime = tonumber(stats.movingTime) or 0
  local maxBps = tonumber(stats.maxBps) or 0
  local avgBps = (totalTime > 0) and (odo / totalTime) or 0
  local function toUnits(bps)
    local kmh = bps * 3.6
    if settings.units == "MP/H" then return kmh * 0.621371, "mph"
    elseif settings.units == "B/S" then return bps, "bs"
    else return kmh, "kmh" end
  end
  local avgVal, avgUnit = toUnits(avgBps)
  local maxVal, maxUnit = toUnits(maxBps)
  writeAt(centerWin, 2, y0 + 1, trim("Odometer: " .. fmt(km, 2) .. " km", layout.centerW - 2), COLORS.fg, COLORS.bg)
  writeAt(centerWin, 2, y0 + 2, trim("Distance: " .. fmt(odo, 1) .. " blocks", layout.centerW - 2), COLORS.fg, COLORS.bg)
  writeAt(centerWin, 2, y0 + 3, trim("Total Time: " .. fmtTime(totalTime), layout.centerW - 2), COLORS.fg, COLORS.bg)
  writeAt(centerWin, 2, y0 + 4, trim("Moving Time: " .. fmtTime(movingTime), layout.centerW - 2), COLORS.fg, COLORS.bg)
  writeAt(centerWin, 2, y0 + 5, trim("Avg Speed: " .. fmt(avgVal, 1) .. " " .. avgUnit, layout.centerW - 2), COLORS.fg, COLORS.bg)
  writeAt(centerWin, 2, y0 + 6, trim("Max Speed: " .. fmt(maxVal, 1) .. " " .. maxUnit, layout.centerW - 2), COLORS.fg, COLORS.bg)
end

local function drawAbout(y0)
  actionBoxes = {}
  settingsBoxes = {}
  engineBox = nil

  local function getShipId()
    if not ship or type(ship) ~= "table" then resolveShip() end
    if ship and type(ship) == "table" then
      local candidates = {
        "getId", "getID", "getShipId", "getShipID",
        "getShipIdentifier", "getShipUuid", "getUuid", "getUUID", "getShipUUID"
      }
      for i = 1, #candidates do
        local fn = ship[candidates[i]]
        if type(fn) == "function" then
          local ok, v = pcall(fn, ship)
          if ok and v ~= nil then return tostring(v) end
          local ok2, v2 = pcall(fn)
          if ok2 and v2 ~= nil then return tostring(v2) end
        end
      end
    end
    if peripheral and peripheral.getNames then
      local ok, names = pcall(peripheral.getNames)
      if ok and type(names) == "table" then
        for i = 1, #names do
          local name = names[i]
          local ok2, typ = pcall(peripheral.getType, name)
          if ok2 and type(typ) == "string" and typ:lower():find("ship") then
            return tostring(name)
          end
        end
      end
    end
    return "unknown"
  end

  local model = safe(vehicleInfo.model or "MODEL")
  local gen = safe(vehicleInfo.generation or "GEN")
  local eng = safe(vehicleInfo.engineType or "Diesel")
  local shipId = getShipId()

  writeAt(centerWin, 2, y0 + 1, trim("OS Version: " .. tostring(VERSION), layout.centerW - 2), COLORS.fg, COLORS.bg)
  writeAt(centerWin, 2, y0 + 2, trim("Ship ID: " .. tostring(shipId), layout.centerW - 2), COLORS.fg, COLORS.bg)
  writeAt(centerWin, 2, y0 + 3, trim("Model: " .. model, layout.centerW - 2), COLORS.fg, COLORS.bg)
  writeAt(centerWin, 2, y0 + 4, trim("Generation: " .. gen, layout.centerW - 2), COLORS.fg, COLORS.bg)
  writeAt(centerWin, 2, y0 + 5, trim("Engine: " .. eng, layout.centerW - 2), COLORS.fg, COLORS.bg)
end

local function drawActions(y0, viewId)
  actionBoxes = {}
  settingsBoxes = {}
  engineBox = nil
  local btnW = clamp(layout.centerW - 6, 18, layout.centerW)
  local btnH = 2
  local btnX = math.max(1, math.floor((layout.centerW - btnW) / 2) + 1)
  local navX = 1
  local navY = math.max(3, math.floor(layout.h / 2) + 1)
  local navUp = "/\\"
  local navDn = "\\/"
  local upBg = COLORS.panel
  local upFg = COLORS.panelText
  local dnBg = COLORS.panel
  local dnFg = COLORS.panelText
  writeAt(centerWin, navX, navY, navUp, upFg, upBg)
  writeAt(centerWin, navX, navY + 2, navDn, dnFg, dnBg)
  actionBoxes.pageUp = {
    x1 = layout.centerX + navX - 1,
    y1 = navY,
    x2 = layout.centerX + navX + #navUp - 2,
    y2 = navY
  }
  actionBoxes.pageDown = {
    x1 = layout.centerX + navX - 1,
    y1 = navY + 2,
    x2 = layout.centerX + navX + #navDn - 2,
    y2 = navY + 2
  }

  if viewId == "actions" then
    local listTop = y0 + 1
    local y = listTop

    local function addBtn(id, label)
      fillRect(centerWin, btnX, y, btnW, btnH, COLORS.panel)
      local tx = btnX + math.floor((btnW - #label) / 2)
      writeAt(centerWin, tx, y, label, COLORS.panelText, COLORS.panel)
      actionBoxes[id] = {
        x1 = layout.centerX + btnX - 1,
        y1 = y,
        x2 = layout.centerX + btnX + btnW - 2,
        y2 = y + btnH - 1
      }
      y = y + btnH + 1
    end

    addBtn("reset", "Reset Odometer")
    if isDiesel then
      addBtn("engine", car.engineOn and "Engine Stop" or "Engine Start")
    else
      addBtn("drive_mode", "Change Drive Mode")
    end
    addBtn("cruise", car.cruiseOn and "Cruise Off" or "Cruise On")
  elseif viewId == "info" then
    local listTop = y0 + 1
    local y = listTop
    local function addInfoBtn(id, label)
      fillRect(centerWin, btnX, y, btnW, btnH, COLORS.panel)
      local tx = btnX + math.floor((btnW - #label) / 2)
      writeAt(centerWin, tx, y, label, COLORS.panelText, COLORS.panel)
      actionBoxes[id] = {
        x1 = layout.centerX + btnX - 1,
        y1 = y,
        x2 = layout.centerX + btnX + btnW - 2,
        y2 = y + btnH - 1
      }
      y = y + btnH + 1
    end

    addInfoBtn("change_rrid", "Change RRID")
    addInfoBtn("clear_caches", "Clear Caches")
    addInfoBtn("reboot", "Reboot & Update")
  end
end

local function drawSettings(y0)
  actionBoxes = {}
  engineBox = nil
  settingsBoxes = {}
  local btnW = clamp(layout.centerW - 6, 18, layout.centerW)
  local btnH = 2
  local btnX = math.max(1, math.floor((layout.centerW - btnW) / 2) + 1)
  local navX = 1
  local navY = math.max(3, math.floor(layout.h / 2) + 1)
  local navUp = "/\\"
  local navDn = "\\/"
  writeAt(centerWin, navX, navY, navUp, COLORS.panelText, COLORS.panel)
  writeAt(centerWin, navX, navY + 2, navDn, COLORS.panelText, COLORS.panel)
  settingsBoxes.pageUp = {
    x1 = layout.centerX + navX - 1,
    y1 = navY,
    x2 = layout.centerX + navX + #navUp - 2,
    y2 = navY
  }
  settingsBoxes.pageDown = {
    x1 = layout.centerX + navX - 1,
    y1 = navY + 2,
    x2 = layout.centerX + navX + #navDn - 2,
    y2 = navY + 2
  }

  local items = {
    { id = "set_scale", label = "Text Size: " .. tostring(settings.textScale) },
    { id = "set_units", label = "Units: " .. tostring(settings.units):gsub("/", "") },
    { id = "toggle_smooth", label = "Smooth Speed: " .. (settings.smoothEnabled and "ON" or "OFF") },
    { id = "set_smooth", label = "Smooth Level: " .. tostring(settings.speedSmooth) },
    { id = "night_mode", label = "Night Mode: " .. (settings.nightMode and "ON" or "OFF") },
    { id = "set_debug", label = "Debug: " .. (DEBUG and "ON" or "OFF") }
  }

  local listTop = y0 + 1
  local y = listTop
  local visible = 0
  while y + btnH - 1 <= layout.h do
    visible = visible + 1
    y = y + btnH + 1
  end
  if visible < 1 then visible = 1 end
  local maxOffset = math.max(1, #items - visible + 1)
  if settingsViewIndex < 1 then settingsViewIndex = 1 end
  if settingsViewIndex > maxOffset then settingsViewIndex = maxOffset end

  y = listTop
  local idx = settingsViewIndex
  while y + btnH - 1 <= layout.h and idx <= #items do
    local item = items[idx]
    fillRect(centerWin, btnX, y, btnW, btnH, COLORS.panel)
    writeAt(centerWin, btnX + 2, y, item.label, COLORS.panelText, COLORS.panel)
    settingsBoxes[item.id] = {
      x1 = layout.centerX + btnX - 1,
      y1 = y,
      x2 = layout.centerX + btnX + btnW - 2,
      y2 = y + btnH - 1
    }
    y = y + btnH + 1
    idx = idx + 1
  end
end

function car.drawDrive(y0)
  actionBoxes = {}
  settingsBoxes = {}
  engineBox = nil
  cruiseBox = nil
  car.driveBoxes = {}

  local margin = 1
  local gapX = 1
  local gapY = 1
  local columns = 3
  local buttonH = 2
  local availableH = layout.h - y0 + 1
  if availableH < 16 then
    buttonH = 1
    gapY = 1
  end
  local buttonW = math.floor((layout.centerW - margin * 2 - gapX * (columns - 1)) / columns)
  if buttonW < 4 then buttonW = 4 end

  local function addControl(id, column, row, title, status, active, accent)
    local x = margin + 1 + (column - 1) * (buttonW + gapX)
    local y = y0 + (row - 1) * (buttonH + gapY)
    local width = column == columns and layout.centerW - x - margin + 1 or buttonW
    if y > layout.h or width < 1 then return end
    local height = math.min(buttonH, layout.h - y + 1)
    local bg = active and (accent or colors.lime) or COLORS.panel
    local fg = active and bestFg(bg) or COLORS.panelText
    fillRect(centerWin, x, y, width, height, bg)
    local line1, line2 = wrap2(title, math.max(1, width - 2))
    if height == 1 then
      local label = trim(line1 .. (status and (" " .. status) or ""), width)
      writeAt(centerWin, x + math.max(0, math.floor((width - #label) / 2)), y, label, fg, bg)
    else
      local label1 = trim(line1, width)
      local label2 = trim(status or line2 or "", width)
      writeAt(centerWin, x + math.max(0, math.floor((width - #label1) / 2)), y, label1, fg, bg)
      writeAt(centerWin, x + math.max(0, math.floor((width - #label2) / 2)), y + 1, label2, fg, bg)
    end
    car.driveBoxes[id] = {
      x1 = layout.centerX + x - 1,
      y1 = y,
      x2 = layout.centerX + x + width - 2,
      y2 = y + height - 1
    }
  end

  addControl("standard", 1, 1, "STANDARD", "MODE", car.state.mode == "standard", colors.lightBlue)
  addControl("sport", 2, 1, "SPORT", "MODE", car.state.mode == "sport", colors.orange)
  addControl("sport_plus", 3, 1, "SPORT+", "MODE", car.state.mode == "sport_plus", colors.red)

  addControl("clutch", 1, 2, "CLUTCH", "W / S", car.state.clutch, colors.lime)
  addControl("reverse", 2, 2, "REVERSE", "S", car.state.reverse, colors.orange)
  addControl("front_drive", 3, 2, "FRONT DRIVE", car.state.frontDriveOff and "OFF" or "ON", car.state.frontDriveOff, colors.red)

  addControl("drive_engine", 1, 3, "DRIVE ENGINE", car.state.driveEngineOff and "OFF" or "ON", car.state.driveEngineOff, colors.red)
  addControl("work_engine", 2, 3, "SHOP ENGINE", car.state.workshopEngineOff and "OFF" or "ON", car.state.workshopEngineOff, colors.red)
  addControl("boost", 3, 3, "SHOP BOOST", car.state.workshopBoost and "ON" or "OFF", car.state.workshopBoost, colors.orange)

  addControl("headlights", 1, 4, "HEADLIGHTS", "L", car.state.lighting == "headlights", colors.lightBlue)
  addControl("left", 2, 4, "LEFT SIGNAL", "TOUCH", car.state.lighting == "left", colors.yellow)
  addControl("right", 3, 4, "RIGHT SIGNAL", "Z", car.state.lighting == "right", colors.yellow)

  addControl("hazard", 1, 5, "HAZARD", "X", car.state.lighting == "hazard", colors.red)
  addControl("heading", 2, 5, "PORT HEADING", car.state.portHeading:upper(), false, colors.lightBlue)

  local statusY = y0 + 5 * (buttonH + gapY)
  if statusY <= layout.h then
    local portStatus = car.devices.portName and ("Port: " .. car.devices.portName) or "Port: not found"
    writeAt(centerWin, 2, statusY, trim(portStatus, layout.centerW - 2), car.devices.portName and COLORS.fg or colors.red, COLORS.bg)
  end
  if statusY + 1 <= layout.h then
    local keyboardStatus = car.devices.keyboardName and ("Keyboard: " .. car.devices.keyboardName) or "Keyboard: not found"
    writeAt(centerWin, 2, statusY + 1, trim(car.devices.error or keyboardStatus, layout.centerW - 2), car.devices.error and colors.red or COLORS.fg, COLORS.bg)
  end
end

local function drawComingSoon(y0)
  writeAt(centerWin, 2, y0 + 2, trim("Content coming soon", layout.centerW - 2), COLORS.fg, COLORS.bg)
  engineBox = nil
  actionBoxes = {}
  settingsBoxes = {}
  car.driveBoxes = {}
end

local function drawCenter()
  clearWin(centerWin, COLORS.bg, COLORS.fg)

  local tab = tabs[activeTab] or {}
  local id = tab.id or ""
  local title = tab.title or ""
  local viewId = nil
  if id == "actions" then
    viewId = actionViews[actionViewIndex] or "actions"
    if viewId == "actions" then title = "Quick Actions"
    elseif viewId == "info" then title = "RoadRover OS"
    end
  end
  if id == "home" then
    title = ""
  end
  local headerH = drawHeader(centerWin, title, layout.centerW)
  local y0 = headerH + 1
  cruiseBox = nil
  quickBox = nil
  quickMapBox = nil
  quickSettingsBox = nil
  modeStandardBox = nil
  modeSportBox = nil
  car.driveBoxes = {}

  if id == "home" then
    drawHome(y0)
  elseif id == "drive" then
    car.drawDrive(y0)
  elseif id == "stats" then
    drawStats(y0)
  elseif id == "about" then
    drawAbout(y0)
  elseif id == "actions" then
    drawActions(y0, viewId)
  elseif id == "settings" then
    drawSettings(y0)
  else
    drawComingSoon(y0)
  end
end

local function drawRightTime()
  local timeText = os.date("%H:%M")
  local tx = math.max(1, layout.rightW - #timeText + 1)
  writeAt(rightWin, tx, 1, timeText, COLORS.timeText, COLORS.timeBg)
end

local function computeRightLayout()
  local tabsX = 1
  local tabW = layout.rightW
  local tabH = 2
  local startY = 3
  local pageH = 2
  local pageY = math.max(2, layout.h - pageH + 1)
  local bottom = pageY - 1
  return {
    tabsX = tabsX,
    tabW = tabW,
    tabH = tabH,
    startY = startY,
    pageH = pageH,
    pageY = pageY,
    bottom = bottom
  }
end

local function buildPageTabs()
  local pageTabs = {}
  for i = 1, #tabs do
    if (tabs[i].page or 1) == tabPage then
      pageTabs[#pageTabs + 1] = { idx = i, tab = tabs[i] }
    end
  end
  return pageTabs
end

local function drawRightTabs(pageTabs, l)
  for i = 1, #pageTabs do
    local y = l.startY + (i - 1) * l.tabH
    if y + l.tabH - 1 > l.bottom then break end

    local t = pageTabs[i].tab
    local active = (pageTabs[i].idx == activeTab)
    local bg = active and COLORS.activeBg or COLORS.panel
    local fg = active and COLORS.activeText or COLORS.panelText

    fillRect(rightWin, l.tabsX, y, l.tabW, l.tabH, bg)

    local label = trim(t.label or t.title or "", l.tabW - 2)
    local ly = y + math.floor((l.tabH - 1) / 2)
    local tx = l.tabsX + math.floor((l.tabW - #label) / 2)
    writeAt(rightWin, tx, ly, label, fg, bg)

    tabBoxes[#tabBoxes + 1] = {
      x1 = layout.rightX + l.tabsX - 1,
      y1 = y,
      x2 = layout.rightX + l.tabsX + l.tabW - 2,
      y2 = y + l.tabH - 1,
      tabIndex = pageTabs[i].idx
    }
  end
end

local function drawRightPageButton(l)
  local pageLabel = (tabPage == 1) and ">>" or "<<"
  if l.tabW <= 4 then pageLabel = (tabPage == 1) and ">" or "<" end
  local pageBg = COLORS.panel
  local pageFg = COLORS.panelText
  fillRect(rightWin, l.tabsX, l.pageY, l.tabW, l.pageH, pageBg)
  local pageTextY = l.pageY + math.floor(l.pageH / 2)
  local ptx = l.tabsX + math.floor((l.tabW - #pageLabel) / 2)
  writeAt(rightWin, ptx, pageTextY, pageLabel, pageFg, pageBg)
  pageBox = {
    x1 = layout.rightX + l.tabsX - 1,
    y1 = l.pageY,
    x2 = layout.rightX + l.tabsX + l.tabW - 2,
    y2 = l.pageY + l.pageH - 1
  }
end

local function drawRight()
  clearWin(rightWin, COLORS.panel, COLORS.panelText)
  drawRightTime()

  tabBoxes = {}
  pageBox = nil
  local l = computeRightLayout()
  local pageTabs = buildPageTabs()
  drawRightTabs(pageTabs, l)
  drawRightPageButton(l)
end

redraw = function()
  if car.drawHD and car.drawHD() then return end
  drawLeft()
  drawCenter()
  drawRight()
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
  if sleep then pcall(sleep, 0) end
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
  x = math.max(1, math.floor(tonumber(x) or 1))
  y = math.max(1, math.floor(tonumber(y) or 1))
  width = math.min(math.floor(tonumber(width) or 0), car.hd.width - x + 1)
  height = math.min(math.floor(tonumber(height) or 0), car.hd.height - y + 1)
  if width <= 0 or height <= 0 then return false end
  return pcall(gpu.filledRectangle, x, y, width, height, color)
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
  local ok = pcall(gpu.drawText, math.floor(x), math.floor(y), text, color or car.palette.text, background or -1, scale, 0)
  if not ok then ok = pcall(gpu.drawText, math.floor(x), math.floor(y), text, color or car.palette.text, background or -1, scale) end
  if not ok then ok = pcall(gpu.drawText, math.floor(x), math.floor(y), text, color or car.palette.text, background or -1) end
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

function car.hdSpeed()
  local kmh = speedBps * 3.6
  if settings.units == "MP/H" then return kmh * 0.621371, "MPH" end
  if settings.units == "B/S" then return speedBps, "B/S" end
  return kmh, "KM/H"
end

function car.drawHDNav(navX, top, width, height)
  local items = {
    { "HOME", 1 },
    { "DRIVE", 2 },
    { "STATS", 4 },
    { "SET", 3 },
    { "ABOUT", 6 }
  }
  local gap = 4
  local itemH = math.floor((height - gap * (#items - 1)) / #items)
  for i = 1, #items do
    local y = top + (i - 1) * (itemH + gap)
    car.hdButton("tab:" .. tostring(items[i][2]), navX, y, width, itemH, items[i][1], nil, activeTab == items[i][2], car.palette.blue)
  end
end

function car.drawHDHome(x, y, width, height)
  local speedW = math.max(88, math.floor(width * 0.32))
  local gap = 8
  local mainX = x + speedW + gap
  local mainW = width - speedW - gap
  car.hdRound(x, y, speedW, height, 7, car.palette.surface)
  car.hdText(x + 10, y + 9, "SPEED", car.palette.muted, 1)
  local speed, unit = car.hdSpeed()
  local speedText = tostring(math.floor(speed + 0.5))
  local speedScale = #speedText <= 2 and 4 or 3
  car.hdCenteredText(x, y + 42, speedW, speedText, car.palette.text, speedScale)
  car.hdCenteredText(x, y + 84, speedW, unit, car.palette.muted, 1)
  local gear = car.state.reverse and "R" or (car.state.clutch and "D" or "P")
  car.hdCenteredText(x, y + height - 41, speedW, gear, car.state.reverse and car.palette.orange or car.palette.green, 3)

  local modeGap = 4
  local modeW = math.floor((mainW - modeGap * 2) / 3)
  car.hdButton("control:standard", mainX, y, modeW, 28, "STANDARD", nil, car.state.mode == "standard", car.palette.blue)
  car.hdButton("control:sport", mainX + modeW + modeGap, y, modeW, 28, "SPORT", nil, car.state.mode == "sport", car.palette.orange)
  car.hdButton("control:sport_plus", mainX + (modeW + modeGap) * 2, y, mainW - (modeW + modeGap) * 2, 28, "SPORT+", nil, car.state.mode == "sport_plus", car.palette.red)

  local statusY = y + 34
  car.hdRound(mainX, statusY, mainW, 32, 5, car.palette.surface)
  car.hdText(mainX + 9, statusY + 6, car.state.driveEngineOff and "ENGINE OFF" or "ENGINE READY", car.state.driveEngineOff and car.palette.red or car.palette.green, 1)
  car.hdText(mainX + 9, statusY + 17, car.state.frontDriveOff and "FRONT DRIVE OFF" or "ALL WHEEL DRIVE", car.palette.muted, 1)
  car.hdText(mainX + mainW - 54, statusY + 11, car.state.clutch and "CLUTCH" or "IDLE", car.state.clutch and car.palette.green or car.palette.muted, 1)

  local controlsY = statusY + 38
  local controlsGap = 5
  local controlW = math.floor((mainW - controlsGap * 2) / 3)
  local controlH = math.floor((height - (controlsY - y) - controlsGap) / 2)
  car.hdButton("control:drive_engine", mainX, controlsY, controlW, controlH, "ENGINE", car.state.driveEngineOff and "OFF" or "ON", not car.state.driveEngineOff, car.palette.green)
  car.hdButton("control:clutch", mainX + controlW + controlsGap, controlsY, controlW, controlH, "CLUTCH", "W / S", car.state.clutch, car.palette.green)
  car.hdButton("control:reverse", mainX + (controlW + controlsGap) * 2, controlsY, mainW - (controlW + controlsGap) * 2, controlH, "REVERSE", "S", car.state.reverse, car.palette.orange)
  local secondY = controlsY + controlH + controlsGap
  car.hdButton("control:headlights", mainX, secondY, controlW, height - (secondY - y), "LIGHTS", "L", car.state.lighting == "headlights", car.palette.cyan)
  car.hdButton("control:right", mainX + controlW + controlsGap, secondY, controlW, height - (secondY - y), "SIGNAL", "Z", car.state.lighting == "right", car.palette.yellow)
  car.hdButton("control:hazard", mainX + (controlW + controlsGap) * 2, secondY, mainW - (controlW + controlsGap) * 2, height - (secondY - y), "HAZARD", "X", car.state.lighting == "hazard", car.palette.red)
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
    { "left", "LEFT SIGNAL", "TOUCH", car.state.lighting == "left", car.palette.yellow },
    { "right", "RIGHT SIGNAL", "Z", car.state.lighting == "right", car.palette.yellow },
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
    { "CURRENT SPEED", fmt(speed, 1) .. " " .. unit, car.palette.cyan },
    { "MAX SPEED", fmt((stats.maxBps or 0) * 3.6, 1) .. " KM/H", car.palette.orange },
    { "ODOMETER", fmt(stats.odometer or 0, 1) .. " BLOCKS", car.palette.green },
    { "DRIVE TIME", fmtTime(stats.movingTime or 0), car.palette.blue }
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
  car.hdButton("setting:units", x, y, width, rowH, "SPEED UNITS", settings.units, true, car.palette.blue)
  car.hdButton("setting:smooth", x, y + rowH + gap, width, rowH, "SPEED FILTER", settings.smoothEnabled and "ON" or "OFF", settings.smoothEnabled, car.palette.green)
  car.hdButton("control:heading", x, y + (rowH + gap) * 2, width, rowH, "PORT HEADING", car.state.portHeading:upper(), true, car.palette.orange)
  local status = (car.devices.keyboardName and "KEYBOARD READY" or "KEYBOARD MISSING") .. "  |  " .. (car.devices.portName and "REDSTONE READY" or "REDSTONE MISSING")
  car.hdButton(nil, x, y + (rowH + gap) * 3, width, height - (rowH + gap) * 3, "HARDWARE", status, car.devices.keyboardName ~= nil and car.devices.portName ~= nil, car.palette.green)
end

function car.drawHDAbout(x, y, width, height)
  car.hdRound(x, y, width, height, 7, car.palette.surface)
  car.hdCenteredText(x, y + 24, width, "ROADROVER OS", car.palette.text, 3)
  car.hdCenteredText(x, y + 58, width, "VERSION " .. VERSION, car.palette.blue, 1)
  car.hdCenteredText(x, y + 82, width, "HD VEHICLE CONTROL SYSTEM", car.palette.muted, 1)
  car.hdCenteredText(x, y + 105, width, tostring(car.hd.width) .. " x " .. tostring(car.hd.height), car.palette.muted, 1)
  car.hdCenteredText(x, y + height - 24, width, displayUserName(), car.palette.text, 1)
end

function car.drawHD()
  if not car.setupHD(false) then return false end
  local gpu = car.devices.gpu
  local width, height = car.hd.width, car.hd.height
  car.hd.hits = {}
  if gpu.fill then
    pcall(gpu.fill, car.palette.background)
  else
    car.hdFill(1, 1, width, height, car.palette.background)
  end
  car.hdFill(1, 1, width, 24, car.palette.surface)
  car.hdText(9, 8, "ROADROVER", car.palette.text, 1)
  local modeLabel = car.state.mode == "sport_plus" and "SPORT+" or car.state.mode:upper()
  car.hdText(86, 8, modeLabel, car.state.mode == "standard" and car.palette.blue or car.palette.orange, 1)
  local timeText = os.date("%H:%M")
  car.hdText(width - car.hdTextWidth(timeText, 1) - 9, 8, timeText, car.palette.text, 1)

  local margin = 8
  local navW = math.max(58, math.floor(width * 0.17))
  local navX = width - navW - margin + 1
  local contentY = 32
  local contentH = height - contentY - margin + 1
  local contentW = navX - margin - 7
  car.drawHDNav(navX, contentY, navW, contentH)
  local tabId = tabs[activeTab] and tabs[activeTab].id or "home"
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
  if gpu.sync then pcall(gpu.sync) end
  return true
end

function car.handleHDClick(x, y)
  x, y = tonumber(x), tonumber(y)
  if not x or not y then return false end
  for i = #car.hd.hits, 1, -1 do
    local target = car.hd.hits[i]
    if x >= target.x and x <= target.x + target.w - 1 and y >= target.y and y <= target.y + target.h - 1 then
      if target.id:sub(1, 4) == "tab:" then
        activeTab = tonumber(target.id:sub(5)) or activeTab
        tabPage = (tabs[activeTab] and tabs[activeTab].page) or tabPage
      elseif target.id:sub(1, 8) == "control:" then
        car.handleDriveControl(target.id:sub(9))
      elseif target.id == "setting:units" then
        if settings.units == "KM/H" then settings.units = "MP/H"
        elseif settings.units == "MP/H" then settings.units = "B/S"
        else settings.units = "KM/H" end
        saveUserSettings()
      elseif target.id == "setting:smooth" then
        settings.smoothEnabled = not settings.smoothEnabled
        saveUserSettings()
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

local function hit(b, x, y)
  return b and x >= b.x1 and x <= b.x2 and y >= b.y1 and y <= b.y2
end

local function selectTabById(id)
  for i = 1, #tabs do
    if tabs[i].id == id then
      activeTab = i
      tabPage = tabs[i].page or tabPage
      return true
    end
  end
  return false
end

function car.handleDriveControl(id)
  if id == "standard" then
    car.setDriveMode("normal")
  elseif id == "sport" then
    car.setDriveMode("sport")
  elseif id == "sport_plus" then
    car.setDriveMode("sport_plus")
  elseif id == "clutch" then
    car.state.clutch = not car.state.clutch
    car.cruiseOn = car.state.clutch
  elseif id == "reverse" then
    car.state.reverse = not car.state.reverse
  elseif id == "front_drive" then
    car.state.frontDriveOff = not car.state.frontDriveOff
  elseif id == "drive_engine" then
    car.state.driveEngineOff = not car.state.driveEngineOff
    car.engineOn = not car.state.driveEngineOff
  elseif id == "work_engine" then
    car.state.workshopEngineOff = not car.state.workshopEngineOff
  elseif id == "boost" then
    car.state.workshopBoost = not car.state.workshopBoost
  elseif id == "headlights" then
    car.setLighting("headlights")
    return true
  elseif id == "left" then
    car.setLighting("left")
    return true
  elseif id == "right" then
    car.setLighting("right")
    return true
  elseif id == "hazard" then
    car.setLighting("hazard")
    return true
  elseif id == "heading" then
    car.cyclePortHeading()
    return true
  else
    return false
  end
  car.applyOutputs()
  return true
end

local function handleClick(mx, my)
  for id, box in pairs(car.driveBoxes) do
    if hit(box, mx, my) then return car.handleDriveControl(id) end
  end
  if quickMapBox and hit(quickMapBox, mx, my) then
    if selectTabById("map") then return true end
  end
  if quickSettingsBox and hit(quickSettingsBox, mx, my) then
    if selectTabById("settings") then return true end
  end
  if quickBox and hit(quickBox, mx, my) then
    if selectTabById("actions") then
      actionViewIndex = 1
      return true
    end
  end
  if modeStandardBox and hit(modeStandardBox, mx, my) then
    car.setDriveMode("normal")
    return true
  end
  if modeSportBox and hit(modeSportBox, mx, my) then
    car.setDriveMode("sport")
    return true
  end
  if engineBox and hit(engineBox, mx, my) then
    if car.canToggleEngine() then car.toggleEngine() end
    return true
  end
  if cruiseBox and hit(cruiseBox, mx, my) then
    car.cruiseOn = not car.cruiseOn
    car.driveOutput(DRIVE_SIDE, car.cruiseOn)
    return true
  end

  if actionBoxes and activeTab > 0 then
    if actionBoxes.reset and hit(actionBoxes.reset, mx, my) then
      resetStats()
      saveUserStats()
      return true
    end
    if actionBoxes.engine and hit(actionBoxes.engine, mx, my) then
      if isDiesel and car.canToggleEngine() then car.toggleEngine() end
      return true
    end
    if actionBoxes.drive_mode and hit(actionBoxes.drive_mode, mx, my) then
      car.setDriveMode((car.driveMode == "sport") and "normal" or "sport")
      return true
    end
    if actionBoxes.cruise and hit(actionBoxes.cruise, mx, my) then
      car.cruiseOn = not car.cruiseOn
      car.driveOutput(DRIVE_SIDE, car.cruiseOn)
      return true
    end
    if actionBoxes.change_rrid and hit(actionBoxes.change_rrid, mx, my) then
      if changeRRID() then rebuildUI() end
      return true
    end
    if actionBoxes.clear_caches and hit(actionBoxes.clear_caches, mx, my) then
      clearCaches()
      return true
    end
    if actionBoxes.pageUp and hit(actionBoxes.pageUp, mx, my) then
      actionViewIndex = actionViewIndex - 1
      if actionViewIndex < 1 then actionViewIndex = #actionViews end
      return true
    end
    if actionBoxes.pageDown and hit(actionBoxes.pageDown, mx, my) then
      actionViewIndex = actionViewIndex + 1
      if actionViewIndex > #actionViews then actionViewIndex = 1 end
      return true
    end
    if actionBoxes.reboot and hit(actionBoxes.reboot, mx, my) then
      if shell and type(shell.run) == "function" then
        local path = (SCRIPT_DIR ~= "" and fs.combine(SCRIPT_DIR, "startup.lua")) or "startup.lua"
        if fs.exists(path) then
          pcall(function() shell.run(path) end)
          error("", 0)
        end
      end
      return true
    end
  end

  if settingsBoxes and activeTab > 0 then
    if settingsBoxes.pageUp and hit(settingsBoxes.pageUp, mx, my) then
      local visible = math.max(1, math.floor((layout.h - 2) / 3))
      local maxOffset = math.max(1, 6 - visible + 1)
      settingsViewIndex = settingsViewIndex - 1
      if settingsViewIndex < 1 then settingsViewIndex = maxOffset end
      return true
    end
    if settingsBoxes.pageDown and hit(settingsBoxes.pageDown, mx, my) then
      local visible = math.max(1, math.floor((layout.h - 2) / 3))
      local maxOffset = math.max(1, 6 - visible + 1)
      settingsViewIndex = settingsViewIndex + 1
      if settingsViewIndex > maxOffset then settingsViewIndex = 1 end
      return true
    end
    if settingsBoxes.set_scale and hit(settingsBoxes.set_scale, mx, my) then
      settings.textScale = (settings.textScale == 0.5) and 1.0 or 0.5
      rebuildUI()
      saveUserSettings()
      return true
    end
    if settingsBoxes.set_units and hit(settingsBoxes.set_units, mx, my) then
      if settings.units == "KM/H" then settings.units = "MP/H"
      elseif settings.units == "MP/H" then settings.units = "B/S"
      else settings.units = "KM/H" end
      saveUserSettings()
      return true
    end
    if settingsBoxes.toggle_smooth and hit(settingsBoxes.toggle_smooth, mx, my) then
      settings.smoothEnabled = not settings.smoothEnabled
      speedBuf = {}
      saveUserSettings()
      return true
    end
    if settingsBoxes.set_smooth and hit(settingsBoxes.set_smooth, mx, my) then
      local v = tonumber(settings.speedSmooth) or 4
      if v == 0 then v = 3 elseif v == 3 then v = 6 elseif v == 6 then v = 9 else v = 0 end
      settings.speedSmooth = v
      speedBuf = {}
      saveUserSettings()
      return true
    end
    if settingsBoxes.night_mode and hit(settingsBoxes.night_mode, mx, my) then
      settings.nightMode = not settings.nightMode
      NIGHT_MODE = settings.nightMode and true or false
      _G.ROADROVER_NIGHT_MODE = NIGHT_MODE and 1 or 0
      applyNightMode()
      saveUserSettings()
      return true
    end
    if settingsBoxes.set_debug and hit(settingsBoxes.set_debug, mx, my) then
      DEBUG = not DEBUG
      _G.ROADROVER_DEBUG = DEBUG and 1 or 0
      saveUserSettings()
      return true
    end
  end

  if pageBox and hit(pageBox, mx, my) then
    tabPage = (tabPage == 1) and 2 or 1
    return true
  end

  for i = 1, #tabBoxes do
    if hit(tabBoxes[i], mx, my) then
      activeTab = tabBoxes[i].tabIndex or activeTab
      tabPage = (tabs[activeTab] and tabs[activeTab].page) or tabPage
      return true
    end
  end

  return false
end

function car.updateHardware()
  car.scanDevices(false)
  local now = os.clock()
  if car.state.lighting ~= "none" and car.state.lighting ~= "headlights" and now - car.lastBlink >= car.blinkPeriod then
    car.state.blink = not car.state.blink
    car.lastBlink = now
  end
  car.applyOutputs()
end

function car.keyName(code)
  if type(code) == "string" then return code:lower() end
  if keys and keys.getName then
    local ok, name = pcall(keys.getName, code)
    if ok and name then return tostring(name):lower() end
  end
  return tostring(code or ""):lower()
end

function car.handleKey(code, down, repeated)
  local name = car.keyName(code)
  local fresh = down and not repeated
  if name == "w" then
    car.state.wHeld = down
    car.state.clutch = car.state.wHeld or car.state.sHeld or car.cruiseOn
  elseif name == "s" then
    car.state.sHeld = down
    car.state.reverse = car.state.sHeld
    car.state.clutch = car.state.wHeld or car.state.sHeld or car.cruiseOn
  elseif fresh and name == "g" then
    car.state.frontDriveOff = not car.state.frontDriveOff
  elseif fresh and name == "f" then
    car.state.driveEngineOff = not car.state.driveEngineOff
    car.engineOn = not car.state.driveEngineOff
  elseif fresh and name == "l" then
    car.setLighting("headlights")
    return true
  elseif fresh and name == "z" then
    car.toggleIndicator()
    return true
  elseif fresh and name == "x" then
    car.setLighting("hazard")
    return true
  else
    return false
  end
  car.applyOutputs()
  return true
end

function car.releaseKeys()
  car.state.wHeld = false
  car.state.sHeld = false
  car.state.clutch = car.cruiseOn
  car.state.reverse = false
  car.applyOutputs()
end

function car.safeShutdown()
  car.state.mode = "standard"
  car.state.clutch = false
  car.state.reverse = false
  car.state.wHeld = false
  car.state.sHeld = false
  car.state.frontDriveOff = false
  car.state.workshopEngineOff = true
  car.state.driveEngineOff = true
  car.state.workshopBoost = false
  car.state.lighting = "none"
  car.state.blink = false
  car.applyOutputs()
end

local function drawCrash(err)
  term.redirect(ui)
  local w, h = term.getSize()
  term.setBackgroundColor(themeColor(colors.black))
  term.setTextColor(themeColor(colors.white))
  term.clear()

  local msg1 = "We're sorry for the inconvenience."
  local msg2 = "Please try again later."

  local y = math.floor(h / 2) - 1
  term.setCursorPos(math.max(1, math.floor((w - #msg1) / 2) + 1), y)
  term.write(msg1)
  term.setCursorPos(math.max(1, math.floor((w - #msg2) / 2) + 1), y + 1)
  term.write(msg2)

  if err and err ~= "" then
    local e = trim(tostring(err), w)
    term.setCursorPos(1, h)
    term.write(e)
  end

  while true do
    local ev = os.pullEvent()
    if ev == "key" or ev == "mouse_click" or ev == "monitor_touch" then break end
  end
end

local function main()
  car.scanDevices(true)
  car.setupHD(true)
  rebuildUI()
  ensureProfile()
  rebuildUI()
  redraw()

  local timer = os.startTimer(TICK)

  while true do
    if timerResetRequested then
      timer = os.startTimer(TICK)
      timerResetRequested = false
    end
    local ev, a, b, c, d = os.pullEvent()

    if ev == "timer" and a == timer then
      pcall(tick)
      pcall(car.updateHardware)
      redraw()
      timer = os.startTimer(TICK)
    elseif ev == "timer" and car.pulseTimer and a == car.pulseTimer then
      car.stopPulse()

    elseif ev == "tm_monitor_mouse_click" or ev == "tm_monitor_touch" then
      if car.hdEvent(ev, a, b, c, d) then redraw() end

    elseif ev == "monitor_touch" then
      local mx, my = b, c
      if handleClick(mx, my) then redraw() end

    elseif ev == "mouse_click" then
      local mx, my = b, c
      if handleClick(mx, my) then redraw() end

    elseif ev == "key" then
      if car.handleKey(a, true, b == true) then redraw() end

    elseif ev == "key_up" then
      if car.handleKey(a, false, false) then redraw() end

    elseif ev == "tm_keyboard_key" then
      if car.handleKey(b, true, c == true) then redraw() end

    elseif ev == "tm_keyboard_key_up" then
      if car.handleKey(b, false, false) then redraw() end

    elseif ev == "portable_disconnect" or ev == "tm_keyboard_portable_disconnect" then
      car.releaseKeys()
      redraw()

    elseif ev == "peripheral" or ev == "peripheral_detach" then
      car.scanDevices(true)
      car.setupHD(true)
      car.applyOutputs()
      rebuildUI()
      redraw()

    elseif ev == "term_resize" or ev == "monitor_resize" or ev == "tm_monitor_resize" then
      car.setupHD(true)
      rebuildUI()
      redraw()
    end
  end
end

local ok, err = xpcall(main, debug and debug.traceback or function(e) return e end)
if not ok then car.safeShutdown(); drawCrash(err) end
