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
local MAP_LOG_PATH = fs.combine(BASE_DIR, "roadrover-map.log")
local MAP_CACHE_PATH = fs.combine(BASE_DIR, "system/road-map-cache.json")
local BASE_ENGINE_SIDE = _G.ENGINE_SIDE or "bottom"
local BASE_DRIVE_SIDE = _G.DRIVE_SIDE or "left"
local ENGINE_SIDE = BASE_ENGINE_SIDE
local DRIVE_SIDE = BASE_DRIVE_SIDE
local TEXT_SCALE = 0.5
local PULSE_SEC = 0.18
local VERSION = _G.ROADROVER_VERSION or "2.7.5"
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
    secondaryPortName = nil,
    secondaryPort = nil,
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
  outputCache = { chassis = {}, port = {}, secondary = {} },
  blinkPeriod = 0.55,
  lastBlink = os.clock(),
  engineOn = false,
  pulseTimer = nil,
  suspensionTimer = nil,
  suspensionFallbackSeconds = 0.7,
  pointer = { down = false, lastSeen = -1e9, x = nil, y = nil },
  cruiseOn = false,
  driveMode = "normal",
  animations = {
    values = {},
    presses = {}
  },
  map = {
    zooms = { 16, 32, 64, 128, 256 },
    zoomIndex = 2,
    panX = 0,
    panZ = 0,
    scan = nil,
    view = nil,
    route = nil,
    telemetry = nil,
    shipSize = nil,
    destination = nil,
    error = nil,
    notice = nil,
    portName = nil,
    serverVersion = nil,
    errorDetail = nil,
    logSignature = nil,
    cacheLoaded = false,
    cacheSignature = nil,
    lastCacheSave = -1e9,
    lastUpdate = -1e9,
    lastRoute = -1e9,
    viewport = nil,
    boxes = {}
  },
  autopilot = {
    enabled = false,
    status = "OFF",
    targetSpeed = 0,
    steering = "CENTER",
    obstacleDistance = nil,
    stoppingDistance = 0,
    stoppingTime = 0,
    behavior = "OFF",
    selectedMode = "standard",
    lastControl = 0
  },
  ai = {
    perception = { traffic = nil, ships = nil, fleet = nil },
    lastPerception = -1e9,
    lastPublish = -1e9,
    ownShipId = nil,
    lastSpeed = 0,
    lastDynamics = nil,
    deceleration = 3.0,
    lastMovingAt = os.clock(),
    bestDestinationDistance = math.huge,
    lastProgressAt = os.clock(),
    blockingId = nil,
    blockingSince = nil,
    lastDetour = -1e9,
    routeIndex = 1,
    recovery = { phase = nil, started = 0, attempts = 0, steer = 0 },
    overtake = { phase = nil, started = 0, side = 1, leadId = nil },
    history = {}
  },
  hd = {
    ready = false,
    width = 384,
    height = 192,
    hits = {},
    gpuName = nil,
    profile = nil
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
local DEFAULT_PORT_HEADING = "east"

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

function car.vehicleStatePath()
  if not USER_ROOT then return nil end
  return fs.combine(USER_ROOT, "data/vehicle-state.json")
end

car.vehicleStateDirty = false
car.lastVehicleStateSave = 0

function car.saveVehicleState()
  local path = car.vehicleStatePath()
  if not path or not car.state then return false end
  local data = {
    mode = car.state.mode,
    reverse = car.state.reverseSelected and true or false,
    frontDriveOff = car.state.frontDriveOff and true or false,
    workshopEngineOff = car.state.workshopEngineOff and true or false,
    driveEngineOff = car.state.driveEngineOff and true or false,
    workshopBoost = car.state.workshopBoost and true or false,
    lighting = car.state.lighting,
    cruiseOn = car.cruiseOn and true or false,
    portHeading = car.state.portHeading
  }
  if car.map.destination then
    data.destinationX = tonumber(car.map.destination.x)
    data.destinationZ = tonumber(car.map.destination.z)
  end
  local saved = writeJson(path, data)
  if saved then
    car.vehicleStateDirty = false
    car.lastVehicleStateSave = os.clock()
  end
  return saved
end

function car.loadVehicleState()
  if not car.state then return false end
  local data = readJson(car.vehicleStatePath())
  if type(data) ~= "table" then return false end

  if data.mode == "standard" or data.mode == "sport" or data.mode == "sport_plus" then
    car.state.mode = data.mode
  end
  car.state.reverseSelected = data.reverse and true or false
  car.state.reverse = car.state.reverseSelected
  car.state.frontDriveOff = data.frontDriveOff and true or false
  car.state.workshopEngineOff = data.workshopEngineOff and true or false
  car.state.driveEngineOff = data.driveEngineOff and true or false
  car.state.workshopBoost = data.workshopBoost and true or false
  if data.lighting == "none" or data.lighting == "headlights" or data.lighting == "left"
    or data.lighting == "right" or data.lighting == "hazard" then
    car.state.lighting = data.lighting
  end
  if car.headingValid[tostring(data.portHeading or "")] then
    car.state.portHeading = data.portHeading
    settings.portHeading = data.portHeading
  end
  car.cruiseOn = data.cruiseOn and true or false
  car.driveMode = car.state.mode == "standard" and "normal" or car.state.mode
  car.engineOn = not car.state.driveEngineOff
  car.state.clutch = car.cruiseOn
  car.state.blink = car.state.lighting ~= "none" and car.state.lighting ~= "headlights"
  if tonumber(data.destinationX) and tonumber(data.destinationZ) then
    car.map.destination = { x = tonumber(data.destinationX), z = tonumber(data.destinationZ) }
  else
    car.map.destination = nil
  end
  car.map.route = nil
  car.vehicleStateDirty = false
  return true
end

function car.markVehicleStateDirty()
  car.vehicleStateDirty = true
end

function car.flushVehicleState(force)
  if not car.vehicleStateDirty then return true end
  if not force and (os.clock() - car.lastVehicleStateSave) < 0.4 then return false end
  return car.saveVehicleState()
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
    car.flushVehicleState(true)
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
  if not car.loadVehicleState() then car.saveVehicleState() end
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

  local bundledPath = (SCRIPT_DIR ~= "" and fs.combine(SCRIPT_DIR, "roadrover-bigfont.lua")) or "roadrover-bigfont.lua"
  if fs.exists(bundledPath) then
    local loaded, library = pcall(dofile, bundledPath)
    if loaded and type(library) == "table" then bigfont = library; return library end
  end

  if fs.exists(BIGFONT_FILE) then
    local ok, lib = pcall(dofile, BIGFONT_FILE)
    if ok and type(lib) == "table" then bigfont = lib; return lib end
  end

  return nil
end

local function bigTextWidth(text)
  if bigfont and type(bigfont.width) == "function" then return bigfont.width(text) end
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
  reverseSelected = false,
  frontDriveOff = false,
  workshopEngineOff = true,
  driveEngineOff = true,
  workshopBoost = false,
  lighting = "none",
  blink = false,
  wHeld = false,
  sHeld = false,
  aHeld = false,
  dHeld = false,
  suspension = "neutral",
  portHeading = "east"
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
  local previousSecondaryPortName = car.devices.secondaryPortName
  local portCandidates = {}
  local directSides = { top = 1, bottom = 2, left = 3, right = 4, front = 5, back = 6 }
  car.devices.portName, car.devices.port = nil, nil
  car.devices.secondaryPortName, car.devices.secondaryPort = nil, nil
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
      if kind:find("tm_rsport", 1, true) or (car.hasMethod(name, "getSides") and type(device.setAnalogOutput) == "function") then
        portCandidates[#portCandidates + 1] = { name = name, device = device }
      end
      if not car.devices.keyboard and (kind:find("tm_keyboard", 1, true) or type(device.setFireNativeEvents) == "function") then
        car.devices.keyboardName, car.devices.keyboard = name, device
      end
      if not car.devices.gpu and (kind:find("tm_gpu", 1, true) or (type(device.getSize) == "function" and type(device.sync) == "function" and type(device.filledRectangle) == "function")) then
        car.devices.gpuName, car.devices.gpu = name, device
      end
    end
  end
  table.sort(portCandidates, function(first, second)
    local firstRank = directSides[first.name] or 100
    local secondRank = directSides[second.name] or 100
    if firstRank ~= secondRank then return firstRank < secondRank end
    return first.name < second.name
  end)
  if portCandidates[1] then
    car.devices.portName, car.devices.port = portCandidates[1].name, portCandidates[1].device
  end
  if car.devices.port and type(car.devices.port.getPortCount) == "function" and type(car.devices.port.getPort) == "function" then
    local countOK, count = pcall(car.devices.port.getPortCount)
    if countOK and tonumber(count) and tonumber(count) >= 2 then
      local portOK, chainPort = pcall(car.devices.port.getPort, 2)
      if portOK and chainPort then
        car.devices.secondaryPortName = tostring(car.devices.portName) .. "#2"
        car.devices.secondaryPort = chainPort
      end
    end
  end
  if not car.devices.secondaryPort and portCandidates[2] then
    car.devices.secondaryPortName, car.devices.secondaryPort = portCandidates[2].name, portCandidates[2].device
  end
  if car.devices.keyboard and car.devices.keyboard.setFireNativeEvents then
    pcall(car.devices.keyboard.setFireNativeEvents, true)
  end
  if force or previousPortName ~= car.devices.portName then
    car.outputCache.port = {}
  end
  if force or previousSecondaryPortName ~= car.devices.secondaryPortName then
    car.outputCache.secondary = {}
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

function car.secondaryPortOutput(side, enabled)
  local port = car.devices.secondaryPort
  if not port then return false end
  enabled = enabled and true or false
  if car.outputCache.secondary[side] == enabled then return true end
  local ok, err
  if port.setAnalogOutput then
    ok, err = pcall(port.setAnalogOutput, side, enabled and 15 or 0)
  elseif port.setAnalogueOutput then
    ok, err = pcall(port.setAnalogueOutput, side, enabled and 15 or 0)
  elseif port.setOutput then
    ok, err = pcall(port.setOutput, side, enabled and true or false)
  end
  if ok then
    car.outputCache.secondary[side] = enabled
  else
    car.devices.error = tostring(err or "secondary port output failed")
  end
  return ok == true
end

function car.clearPortOutputs()
  local ports = { car.devices.port, car.devices.secondaryPort }
  local sides = { "up", "down", "north", "east", "south", "west" }
  for portIndex = 1, #ports do
    local port = ports[portIndex]
    if port then
      for sideIndex = 1, #sides do
        if port.setAnalogOutput then
          pcall(port.setAnalogOutput, sides[sideIndex], 0)
        elseif port.setAnalogueOutput then
          pcall(port.setAnalogueOutput, sides[sideIndex], 0)
        elseif port.setOutput then
          pcall(port.setOutput, sides[sideIndex], false)
        end
      end
    end
  end
  car.outputCache.port = {}
  car.outputCache.secondary = {}
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
  car.secondaryPortOutput("north", car.state.aHeld and not car.state.dHeld)
  car.secondaryPortOutput("east", car.state.dHeld and not car.state.aHeld)
  car.secondaryPortOutput("up", car.state.suspension == "down")
  car.secondaryPortOutput("down", car.state.suspension == "up" or car.state.suspension == "down")
end

function car.setLighting(mode)
  if car.state.lighting == mode then mode = "none" end
  car.state.lighting = mode
  car.state.blink = mode ~= "none" and mode ~= "headlights"
  car.lastBlink = os.clock()
  car.applyOutputs()
  car.markVehicleStateDirty()
end

function car.toggleIndicator(side)
  if side ~= "left" and side ~= "right" then return false end
  car.setLighting(side)
  return true
end

function car.cyclePortHeading()
  car.clearPortOutputs()
  car.state.portHeading = "east"
  settings.portHeading = "east"
  saveUserSettings()
  car.applyOutputs()
  car.markVehicleStateDirty()
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
  car.markVehicleStateDirty()
end

function car.toggleEngine()
  car.setEngine(not car.engineOn)
end

function car.setDriveMode(mode)
  if mode ~= "normal" and mode ~= "sport" and mode ~= "sport_plus" then return end
  car.driveMode = mode
  car.state.mode = mode == "normal" and "standard" or mode
  car.applyOutputs()
  car.markVehicleStateDirty()
end

car.scanDevices(true)
car.state.workshopEngineOff = true
car.state.driveEngineOff = true
car.engineOn = false
car.cruiseOn = false
car.state.clutch = false
car.applyOutputs()

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
car.PI = math.pi

function car.atan2(y, x)
  if math.atan2 then return math.atan2(y, x) end
  if x > 0 then return math.atan(y / x) end
  if x < 0 and y >= 0 then return math.atan(y / x) + car.PI end
  if x < 0 and y < 0 then return math.atan(y / x) - car.PI end
  if x == 0 and y > 0 then return car.PI / 2 end
  if x == 0 and y < 0 then return -car.PI / 2 end
  return 0
end

function car.normalizeAngle(value)
  while value > car.PI do value = value - car.PI * 2 end
  while value < -car.PI do value = value + car.PI * 2 end
  return value
end

function car.tableNumber(value, key)
  if type(value) ~= "table" then return nil end
  return tonumber(value[key])
end

function car.vehicleWorldPosition()
  local center = car.map.scan and car.map.scan.center
  local x = car.tableNumber(center, "x")
  local y = car.tableNumber(center, "y")
  local z = car.tableNumber(center, "z")
  if x and z then return { x = x, y = y or 0, z = z } end
  return curPos
end

function car.shipHeading()
  if car.motionHeading and os.clock() - (car.motionHeadingTime or -1e9) < 1.2 then return car.motionHeading end
  if not ship or type(ship) ~= "table" then resolveShip() end
  if not ship or type(ship) ~= "table" then return nil end
  local candidates = { "getEulerAnglesYXZ", "getEulerAnglesXYZ", "getEulerAnglesZYX" }
  for i = 1, #candidates do
    local fn = ship[candidates[i]]
    if type(fn) == "function" then
      local ok, angles = pcall(fn, ship)
      if not ok then ok, angles = pcall(fn) end
      if ok and type(angles) == "table" then
        local yaw = tonumber(angles.y or angles.Y or angles[2])
        if yaw then
          if math.abs(yaw) > car.PI * 2 + 0.1 then yaw = math.rad(yaw) end
          return car.atan2(math.cos(yaw), math.sin(yaw))
        end
      end
    end
  end
  return nil
end

function car.telemetryPort()
  local port = car.devices.port
  if port and type(port.scanRoad) == "function" then return port, car.devices.portName end
  if car.devices.portName and car.hasMethod(car.devices.portName, "scanRoad") then
    return port, car.devices.portName
  end
  if peripheral and type(peripheral.getNames) == "function" then
    local ok, names = pcall(peripheral.getNames)
    if ok and type(names) == "table" then
      for index = 1, #names do
        local wrapped = peripheral.wrap(names[index])
        if wrapped and type(wrapped.scanRoad) == "function" then return wrapped, names[index] end
        if car.hasMethod(names[index], "scanRoad") then return wrapped, names[index] end
      end
    end
  end
  return nil
end

function car.loadMapCache()
  if car.map.cacheLoaded then return car.map.view ~= nil end
  car.map.cacheLoaded = true
  local cached = readJson(MAP_CACHE_PATH)
  if type(cached) ~= "table" or cached.available ~= true or type(cached.samples) ~= "table" then return false end
  car.map.view = cached
  car.map.notice = "CACHED MAP"
  return true
end

function car.saveMapCache(view)
  if type(view) ~= "table" or view.available ~= true or type(view.samples) ~= "table" then return false end
  local center = view.center or {}
  local signature = table.concat({
    tostring(math.floor(tonumber(center.x) or 0)),
    tostring(math.floor(tonumber(center.z) or 0)),
    tostring(view.radius or ""),
    tostring(view.step or ""),
    tostring(view.sharedCells or ""),
    tostring(#view.samples)
  }, ":")
  local now = os.clock()
  if signature == car.map.cacheSignature or now - car.map.lastCacheSave < 20 then return false end
  car.map.cacheSignature = signature
  car.map.lastCacheSave = now
  mkdirp(fs.getDir(MAP_CACHE_PATH))
  return writeJson(MAP_CACHE_PATH, view)
end

function car.ensureMapFallback()
  if car.map.view then return true end
  if car.loadMapCache() then return true end
  local position = curPos or car.vehicleWorldPosition()
  if type(position) ~= "table" then return false end
  local x = tonumber(position.x)
  local y = tonumber(position.y) or 0
  local z = tonumber(position.z)
  if not x or not z then return false end
  car.map.view = {
    available = true,
    center = { x = x, y = y, z = z },
    vehicle = { x = x, y = y, z = z },
    radius = car.map.zooms[car.map.zoomIndex] or 32,
    step = 1,
    sharedCells = 0,
    samples = {}
  }
  return true
end

function car.callTelemetry(method, ...)
  local port, portName = car.telemetryPort()
  if not port and not portName then return false, "Telemetry peripheral unavailable", nil end
  local directError = nil
  if portName and peripheral and type(peripheral.call) == "function" and car.hasMethod(portName, method) then
    local called, first, second, third = pcall(peripheral.call, portName, method, ...)
    if called then return true, first, portName, second, third end
    directError = first
  end
  local fn = port and port[method] or nil
  if type(fn) ~= "function" then
    return false, directError or ("Method " .. tostring(method) .. " unavailable"), portName
  end
  local called, first, second, third = pcall(fn, ...)
  if called then return true, first, portName, second, third end
  return false, directError or first, portName
end

function car.writeMapDiagnostic(status, detail, portName)
  local signature = table.concat({ tostring(status or ""), tostring(detail or ""), tostring(portName or "") }, "|")
  if signature == car.map.logSignature then return end
  car.map.logSignature = signature
  local lines = {
    "RoadRover OS " .. tostring(VERSION) .. " map diagnostics",
    "status=" .. tostring(status or "unknown"),
    "detail=" .. tostring(detail or ""),
    "selectedPeripheral=" .. tostring(portName or car.devices.portName or "none"),
    "primaryPeripheral=" .. tostring(car.devices.portName or "none"),
    "secondaryPeripheral=" .. tostring(car.devices.secondaryPortName or "none")
  }
  if peripheral and type(peripheral.getNames) == "function" then
    local namesOK, names = pcall(peripheral.getNames)
    if namesOK and type(names) == "table" then
      table.sort(names)
      for index = 1, #names do
        local name = names[index]
        local kind = car.peripheralType(name)
        local exposed = {}
        local methodsOK, methods = pcall(peripheral.getMethods, name)
        if methodsOK and type(methods) == "table" then
          local wanted = {
            scanRoad = true,
            getRoadMap = true,
            getTweakedTweaksInfo = true,
            readBus = true,
            getShipDimensions = true,
            getPortCount = true
          }
          for methodIndex = 1, #methods do
            local methodName = tostring(methods[methodIndex])
            if wanted[methodName] then exposed[#exposed + 1] = methodName end
          end
          table.sort(exposed)
        end
        lines[#lines + 1] = "peripheral=" .. tostring(name)
          .. " type=" .. tostring(kind ~= "" and kind or "unknown")
          .. " mapMethods=" .. (#exposed > 0 and table.concat(exposed, ",") or "none")
      end
    else
      lines[#lines + 1] = "peripheralScanError=" .. tostring(names)
    end
  else
    lines[#lines + 1] = "peripheralAPI=unavailable"
  end
  local handle = fs.open(MAP_LOG_PATH, "w")
  if not handle then return end
  handle.write(table.concat(lines, "\n") .. "\n")
  handle.close()
end

function car.routePoints()
  local route = car.map.route
  if type(route) ~= "table" or route.available ~= true or type(route.points) ~= "table" then return nil end
  return route.points
end

function car.updateRoute(force, avoid)
  local destination = car.map.destination
  if not destination then
    car.map.route = nil
    return false
  end
  local now = os.clock()
  if not force and now - car.map.lastRoute < 3 then return car.routePoints() ~= nil end
  car.map.lastRoute = now
  local ok, route
  if type(avoid) == "table" and tonumber(avoid.x) and tonumber(avoid.z) then
    ok, route = car.callTelemetry("planRoadRoute", destination.x, destination.z, avoid.x, avoid.z, tonumber(avoid.radius) or 6)
  else
    ok, route = car.callTelemetry("planRoadRoute", destination.x, destination.z)
  end
  if ok and type(route) == "table" then
    if route.available == true then
      car.map.route = route
      car.map.error = nil
      return true
    end
    if not (type(avoid) == "table" and car.routePoints()) then car.map.route = route end
    car.map.error = tostring(route.error or "Route unavailable")
    return false
  end
  car.map.route = nil
  car.map.error = tostring(route or "Route request failed")
  return false
end

function car.updateMap(force)
  local port, portName = car.telemetryPort()
  if not port and not portName then
    local version = nil
    local primary = car.devices.port
    if primary and type(primary.getTweakedTweaksInfo) == "function" then
      local infoOK, info = pcall(primary.getTweakedTweaksInfo)
      if infoOK and type(info) == "table" then version = tostring(info.version or "") end
    end
    car.map.error = version and version ~= ""
      and ("Server mod " .. version .. " has no road map API")
      or (car.devices.portName and ("Road map API unavailable on " .. tostring(car.devices.portName))
        or "Redstone Port not connected")
    car.map.notice = nil
    car.map.errorDetail = car.map.error
    car.writeMapDiagnostic("peripheral-unavailable", car.map.error, portName)
    return car.ensureMapFallback()
  end
  car.map.portName = portName
  local now = os.clock()
  if not force and now - car.map.lastUpdate < 2 then return true end
  car.map.lastUpdate = now
  if not car.map.serverVersion then
    local infoOK, info = car.callTelemetry("getTweakedTweaksInfo")
    if infoOK and type(info) == "table" then car.map.serverVersion = tostring(info.version or "") end
  end
  local scanOK, scan, scanPortName = car.callTelemetry("scanRoad", 24)
  if not scanOK or type(scan) ~= "table" or scan.available ~= true then
    local rawError = tostring((type(scan) == "table" and scan.error) or scan or "Road scan failed")
    car.map.errorDetail = rawError
    if rawError:find("ClientLevel", 1, true) and rawError:find("DEDICATED_SERVER", 1, true) then
      local version = car.map.serverVersion and car.map.serverVersion ~= "" and car.map.serverVersion or "old"
      car.map.error = "SERVER MOD " .. version .. " MUST BE UPDATED"
    else
      car.map.error = rawError
    end
    car.map.notice = nil
    car.writeMapDiagnostic("scan-failed", rawError, scanPortName or portName)
    return car.ensureMapFallback()
  end
  car.map.scan = scan
  local vehicle = scan.center or {}
  local vehicleX = tonumber(vehicle.x) or 0
  local vehicleZ = tonumber(vehicle.z) or 0
  local centerX = vehicleX + car.map.panX
  local centerZ = vehicleZ + car.map.panZ
  local radius = car.map.zooms[car.map.zoomIndex] or 32
  local step = radius <= 32 and 1 or (radius <= 64 and 2 or (radius <= 128 and 4 or 8))
  car.map.view = {
    available = true,
    center = { x = vehicleX, y = tonumber(vehicle.y) or 0, z = vehicleZ },
    vehicle = { x = vehicleX, y = tonumber(vehicle.y) or 0, z = vehicleZ },
    radius = tonumber(scan.radius) or 24,
    step = 1,
    sharedCells = tonumber(scan.sharedCells) or 0,
    samples = type(scan.samples) == "table" and scan.samples or {}
  }
  car.map.error = nil
  car.map.errorDetail = nil
  car.map.notice = "LOCAL SCAN"
  if (port and type(port.getRoadMap) == "function") or (portName and car.hasMethod(portName, "getRoadMap")) then
    local viewOK, view = car.callTelemetry("getRoadMap", centerX, centerZ, radius, step)
    if viewOK and type(view) == "table" and view.available == true then
      car.map.view = view
      car.map.notice = nil
    else
      car.map.notice = "LOCAL SCAN - SHARED MAP UNAVAILABLE"
    end
  end
  car.saveMapCache(car.map.view)
  if (port and type(port.readBus) == "function") or (portName and car.hasMethod(portName, "readBus")) then
    local telemetryOK, telemetry = car.callTelemetry("readBus")
    if telemetryOK and type(telemetry) == "table" then car.map.telemetry = telemetry end
  end
  if not car.map.shipSize and ((port and type(port.getShipDimensions) == "function") or (portName and car.hasMethod(portName, "getShipDimensions"))) then
    local sizeOK, size = car.callTelemetry("getShipDimensions")
    if sizeOK and type(size) == "table" then car.map.shipSize = size end
  end
  car.writeMapDiagnostic(
    "ready",
    "samples=" .. tostring(type(scan.samples) == "table" and #scan.samples or 0)
      .. " sharedCells=" .. tostring(scan.sharedCells or 0)
      .. " loaded=" .. tostring(scan.loaded),
    scanPortName or portName
  )
  if car.map.destination then car.updateRoute(force) end
  return car.map.view ~= nil
end

function car.nearestObstacle(position)
  local devices = car.map.telemetry
  if type(devices) ~= "table" or not position then return nil end
  local nearest = nil
  for _, device in pairs(devices) do
    if type(device) == "table" and type(device.radar) == "table" then
      for _, contact in pairs(device.radar) do
        if type(contact) == "table" then
          local x, y, z = tonumber(contact.x), tonumber(contact.y), tonumber(contact.z)
          if x and z then
            local dx = x - position.x
            local dz = z - position.z
            local dy = (y or position.y or 0) - (position.y or 0)
            local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
            if distance > 0.5 and (not nearest or distance < nearest) then nearest = distance end
          end
        end
      end
    end
  end
  return nearest
end

function car.aiDimensions()
  local size = car.map.shipSize
  if type(size) ~= "table" then return 2.5, 5, 2 end
  local width = tonumber(size.width) or 2.5
  local length = tonumber(size.length) or 5
  if width > length then width, length = length, width end
  return math.max(1, width), math.max(2, length), math.max(1, tonumber(size.height) or 2)
end

function car.aiDistance(first, second)
  if type(first) ~= "table" or type(second) ~= "table" then return math.huge end
  local firstX, firstZ = tonumber(first.x), tonumber(first.z)
  local secondX, secondZ = tonumber(second.x), tonumber(second.z)
  if not firstX or not firstZ or not secondX or not secondZ then return math.huge end
  return math.sqrt((secondX - firstX) ^ 2 + (secondZ - firstZ) ^ 2)
end

function car.aiUpdateDynamics(now, distanceToDestination)
  local ai = car.ai
  local dt = ai.lastDynamics and (now - ai.lastDynamics) or 0
  if dt > 0.04 and dt < 1.5 then
    local observed = (ai.lastSpeed - speedBps) / dt
    if observed > 0.2 and observed < 24 and not car.state.clutch then
      ai.deceleration = clamp(ai.deceleration * 0.86 + observed * 0.14, 0.8, 12)
    end
  end
  ai.lastSpeed = speedBps
  ai.lastDynamics = now
  if speedBps > 0.35 then ai.lastMovingAt = now end
  if distanceToDestination + 0.75 < ai.bestDestinationDistance then
    ai.bestDestinationDistance = distanceToDestination
    ai.lastProgressAt = now
  end
  ai.history[#ai.history + 1] = { time = now, speed = speedBps, clutch = car.state.clutch and true or false }
  while #ai.history > 48 do table.remove(ai.history, 1) end
end

function car.aiStoppingModel(targetSpeed)
  local _, length = car.aiDimensions()
  local deceleration = clamp(tonumber(car.ai.deceleration) or 3, 0.8, 12)
  local reaction = car.driveMode == "sport_plus" and 0.38 or (car.driveMode == "sport" and 0.45 or 0.55)
  local currentSquared = speedBps * speedBps
  local targetSquared = math.max(0, tonumber(targetSpeed) or 0) ^ 2
  local braking = math.max(0, currentSquared - targetSquared) / (2 * deceleration)
  local margin = 2 + length * 0.5
  return braking + speedBps * reaction + margin, math.max(0, speedBps - (tonumber(targetSpeed) or 0)) / deceleration + reaction
end

function car.aiRouteGeometry(position, points)
  if not position or type(points) ~= "table" or #points == 0 then return nil end
  local nearestIndex = 1
  local nearestDistance = math.huge
  for index = 1, #points do
    local point = points[index]
    local distance = car.aiDistance(position, point)
    if distance < nearestDistance then nearestDistance = distance; nearestIndex = index end
  end
  car.ai.routeIndex = nearestIndex
  local wanted = clamp(3.5 + speedBps * 0.9, 4, 16)
  local targetIndex = nearestIndex
  local walked = 0
  local previous = position
  while targetIndex < #points and walked < wanted do
    targetIndex = targetIndex + 1
    walked = walked + car.aiDistance(previous, points[targetIndex])
    previous = points[targetIndex]
  end
  local target = points[targetIndex] or points[#points]
  local nextPoint = points[math.min(#points, targetIndex + 1)] or target
  local targetX, targetZ = tonumber(target.x), tonumber(target.z)
  local nextX, nextZ = tonumber(nextPoint.x), tonumber(nextPoint.z)
  if not targetX or not targetZ or not nextX or not nextZ then return nil end
  local firstHeading = car.atan2(targetZ - position.z, targetX - position.x)
  local secondHeading = (nextX == targetX and nextZ == targetZ) and firstHeading or car.atan2(nextZ - targetZ, nextX - targetX)
  local turnAngle = math.abs(car.normalizeAngle(secondHeading - firstHeading))
  local segment = math.max(1, car.aiDistance(position, target))
  local radius = turnAngle < 0.03 and 999 or math.max(2, segment / math.max(0.08, 2 * math.sin(turnAngle * 0.5)))
  return {
    target = target,
    nextPoint = nextPoint,
    nearestIndex = nearestIndex,
    targetIndex = targetIndex,
    desiredHeading = firstHeading,
    turnAngle = turnAngle,
    turnRadius = radius,
    turnDistance = segment
  }
end

function car.aiUpdatePerception(position, heading, target)
  local port = car.telemetryPort()
  if not port then return end
  local now = os.clock()
  if now - car.ai.lastPerception >= 0.45 then
    car.ai.lastPerception = now
    if type(port.scanProtectedTraffic) == "function" then
      local ok, value = pcall(port.scanProtectedTraffic, 80)
      if ok and type(value) == "table" and value.available == true then car.ai.perception.traffic = value end
    end
    if type(port.scanShips) == "function" then
      local ok, value = pcall(port.scanShips, 160)
      if ok and type(value) == "table" and value.available == true then car.ai.perception.ships = value end
    end
    if type(port.getFleetVehicles) == "function" then
      local ok, value = pcall(port.getFleetVehicles, 192)
      if ok and type(value) == "table" and value.available == true then car.ai.perception.fleet = value end
    end
  end
  if now - car.ai.lastPublish >= 0.35 and type(port.publishFleetState) == "function" then
    car.ai.lastPublish = now
    local destination = car.map.destination or position
    local waypoint = target or destination
    local ok, value = pcall(
      port.publishFleetState,
      car.autopilot.enabled,
      heading or 0,
      car.autopilot.targetSpeed or 0,
      destination.x or position.x,
      destination.z or position.z,
      waypoint.x or position.x,
      waypoint.z or position.z,
      car.autopilot.behavior or "manual"
    )
    if ok and type(value) == "table" and value.available == true then car.ai.ownShipId = tonumber(value.shipId) end
  end
end

function car.aiContactMetrics(position, heading, contact)
  if type(contact) ~= "table" then return nil end
  local contactX, contactZ = tonumber(contact.x), tonumber(contact.z)
  if not contactX or not contactZ then return nil end
  local forwardX, forwardZ = math.cos(heading), math.sin(heading)
  local leftX, leftZ = -forwardZ, forwardX
  local relativeX, relativeZ = contactX - position.x, contactZ - position.z
  local longitudinal = relativeX * forwardX + relativeZ * forwardZ
  local lateral = relativeX * leftX + relativeZ * leftZ
  local width, length = car.aiDimensions()
  local contactWidth = math.max(0.5, tonumber(contact.width) or tonumber(contact.worldWidth) or 2)
  local contactLength = math.max(0.5, tonumber(contact.length) or tonumber(contact.worldLength) or contactWidth)
  local halfWidth = (width + math.min(contactWidth, contactLength)) * 0.5 + 1.25
  local halfLength = (length + math.max(contactWidth, contactLength)) * 0.5 + 2
  local velocityX, velocityZ = tonumber(contact.vx) or 0, tonumber(contact.vz) or 0
  local ownVelocityX, ownVelocityZ = forwardX * speedBps, forwardZ * speedBps
  local relativeVelocityX, relativeVelocityZ = velocityX - ownVelocityX, velocityZ - ownVelocityZ
  local earliest, minimumDistance = nil, math.sqrt(relativeX * relativeX + relativeZ * relativeZ)
  local horizons = { 0.5, 1, 1.5, 2, 3 }
  for index = 1, #horizons do
    local horizon = horizons[index]
    local futureX = relativeX + relativeVelocityX * horizon
    local futureZ = relativeZ + relativeVelocityZ * horizon
    local futureLong = futureX * forwardX + futureZ * forwardZ
    local futureLateral = futureX * leftX + futureZ * leftZ
    local futureDistance = math.sqrt(futureX * futureX + futureZ * futureZ)
    minimumDistance = math.min(minimumDistance, futureDistance)
    if not earliest and math.abs(futureLateral) <= halfWidth and futureLong >= -halfLength and futureLong <= halfLength + speedBps * 1.4 then
      earliest = horizon
    end
  end
  local forwardSpeed = velocityX * forwardX + velocityZ * forwardZ
  return {
    contact = contact,
    id = tostring(contact.id or contact.kind or "contact"),
    distance = math.sqrt(relativeX * relativeX + relativeZ * relativeZ),
    minimumDistance = minimumDistance,
    longitudinal = longitudinal,
    lateral = lateral,
    halfWidth = halfWidth,
    halfLength = halfLength,
    speed = math.sqrt(velocityX * velocityX + velocityZ * velocityZ),
    forwardSpeed = forwardSpeed,
    collisionTime = earliest,
    ahead = longitudinal > -halfLength and math.abs(lateral) <= halfWidth + 1,
    behind = longitudinal < 0 and math.abs(lateral) <= halfWidth + 2,
    protected = contact.protected == true or contact.kind == "player" or contact.kind == "cat" or contact.kind == "dog"
  }
end

function car.aiAssessTraffic(position, heading, stopDistance, stopTime)
  local result = {
    hardStop = false,
    reason = nil,
    nearest = math.huge,
    lead = nil,
    oncoming = false,
    protectedNearby = false,
    protectedBehind = false,
    stationaryBlock = nil,
    allied = {}
  }
  local fleet = car.ai.perception.fleet
  if type(fleet) == "table" and type(fleet.vehicles) == "table" then
    for _, vehicle in pairs(fleet.vehicles) do
      if type(vehicle) == "table" then result.allied[tostring(vehicle.id or "")] = vehicle end
    end
  end
  local traffic = car.ai.perception.traffic
  if type(traffic) == "table" and type(traffic.traffic) == "table" then
    for _, contact in pairs(traffic.traffic) do
      local metrics = car.aiContactMetrics(position, heading, contact)
      if metrics then
        result.nearest = math.min(result.nearest, metrics.distance)
        result.protectedNearby = result.protectedNearby or metrics.distance < stopDistance + 12
        result.protectedBehind = result.protectedBehind or (metrics.behind and metrics.distance < metrics.halfLength + 5)
        if metrics.collisionTime or metrics.distance < metrics.halfWidth + 1 then
          result.hardStop = true
          result.reason = string.upper(tostring(contact.kind or "PROTECTED"))
        end
      end
    end
  end
  local ships = car.ai.perception.ships
  if type(ships) == "table" and type(ships.ships) == "table" then
    for _, contact in pairs(ships.ships) do
      local metrics = car.aiContactMetrics(position, heading, contact)
      if metrics then
        metrics.allied = result.allied[tostring(contact.id or "")] ~= nil
        result.nearest = math.min(result.nearest, metrics.distance)
        if metrics.longitudinal > 0 and metrics.forwardSpeed < -0.5 and math.abs(metrics.lateral) < metrics.halfWidth + 4 then
          result.oncoming = true
        end
        if metrics.ahead and metrics.longitudinal > 0 and (not result.lead or metrics.longitudinal < result.lead.longitudinal) then
          result.lead = metrics
        end
        if metrics.collisionTime and metrics.collisionTime <= stopTime + 1.2 then
          local mustYield = not metrics.allied or not car.ai.ownShipId or tonumber(contact.id) == nil or car.ai.ownShipId > tonumber(contact.id)
          if mustYield or metrics.distance <= stopDistance then
            result.hardStop = true
            result.reason = metrics.allied and "YIELD FLEET" or "SHIP CONFLICT"
          end
        end
        if metrics.ahead and metrics.speed < 0.3 and metrics.longitudinal < stopDistance + 15 then
          result.stationaryBlock = metrics
        end
      end
    end
  end
  if result.nearest == math.huge then result.nearest = nil end
  return result
end

function car.aiChooseMode(geometry, traffic, distanceToDestination)
  local scan = car.map.scan or {}
  local confidence = tonumber(scan.confidence) or 0
  local crosswalk = tonumber(scan.crosswalkDistance) or -1
  local tunnel = (tonumber(scan.tunnelCells) or 0) > 0
  if traffic.hardStop or traffic.lead or traffic.protectedNearby or traffic.oncoming or tunnel
    or (crosswalk >= 0 and crosswalk < 24) or geometry.turnAngle > 0.28 or confidence < 0.55 then
    return "normal", 7
  end
  if geometry.turnAngle < 0.06 and confidence >= 0.82 and distanceToDestination > 70
    and not traffic.nearest and scan.loaded ~= false then
    return "sport_plus", 14
  end
  return "sport", 10.5
end

function car.aiOvertakeOffset(traffic, geometry, now)
  local overtake = car.ai.overtake
  local width = car.aiDimensions()
  local roadWidth = tonumber(car.map.scan and car.map.scan.estimatedWidth) or 12
  local crosswalk = tonumber(car.map.scan and car.map.scan.crosswalkDistance) or -1
  local tunnel = (tonumber(car.map.scan and car.map.scan.tunnelCells) or 0) > 0
  local safeRoad = roadWidth >= width * 2 + 3 and geometry.turnAngle < 0.10 and not tunnel
    and not (crosswalk >= 0 and crosswalk < 30) and not traffic.oncoming and not traffic.protectedNearby

  if overtake.phase == "pass" then
    if not safeRoad or traffic.hardStop then
      overtake.phase = "return"
      overtake.started = now
    elseif now - overtake.started > 4.5 or not traffic.lead then
      overtake.phase = "return"
      overtake.started = now
    end
  elseif overtake.phase == "return" then
    if now - overtake.started > 1.4 then
      overtake.phase = nil
      overtake.leadId = nil
    end
  elseif traffic.lead and traffic.lead.longitudinal > 7 and traffic.lead.longitudinal < 28
    and traffic.lead.speed + 1.2 < math.max(4, speedBps) and safeRoad then
    if overtake.leadId == traffic.lead.id then
      overtake.followSince = overtake.followSince or now
    else
      overtake.leadId = traffic.lead.id
      overtake.followSince = now
    end
    if now - overtake.followSince > 1.8 then
      overtake.phase = "pass"
      overtake.started = now
      overtake.side = traffic.lead.lateral >= 0 and -1 or 1
    end
  else
    overtake.followSince = nil
    if not overtake.phase then overtake.leadId = nil end
  end

  if overtake.phase == "pass" then return overtake.side * math.min(4, math.max(2.5, width + 0.75)), "OVERTAKE" end
  if overtake.phase == "return" then
    local progress = clamp((now - overtake.started) / 1.4, 0, 1)
    return overtake.side * math.min(4, math.max(2.5, width + 0.75)) * (1 - progress), "RETURN LANE"
  end
  return 0, nil
end

function car.aiOffsetTarget(position, target, offset)
  if not target or math.abs(offset or 0) < 0.05 then return target end
  local dx, dz = (tonumber(target.x) or position.x) - position.x, (tonumber(target.z) or position.z) - position.z
  local length = math.sqrt(dx * dx + dz * dz)
  if length < 0.01 then return target end
  return { x = (tonumber(target.x) or position.x) - dz / length * offset, z = (tonumber(target.z) or position.z) + dx / length * offset }
end

function car.aiSetSteering(error, aggressive)
  local deadzone = clamp((aggressive and 0.045 or 0.075) + speedBps * 0.008, 0.05, 0.20)
  car.state.aHeld = error < -deadzone
  car.state.dHeld = error > deadzone
  car.autopilot.steering = car.state.aHeld and "LEFT" or (car.state.dHeld and "RIGHT" or "CENTER")
end

function car.aiRecoveryControl(now, headingError, traffic, shouldRecover)
  local recovery = car.ai.recovery
  if not recovery.phase and shouldRecover and recovery.attempts < 3 and not traffic.protectedBehind and not traffic.hardStop then
    recovery.phase = "reverse"
    recovery.started = now
    recovery.attempts = recovery.attempts + 1
    recovery.steer = headingError >= 0 and -1 or 1
  end
  if recovery.phase == "reverse" then
    car.autopilot.behavior = "RECOVERY REVERSE"
    car.autopilot.status = "RECOVERY REVERSE"
    car.state.reverse = true
    car.state.clutch = true
    car.state.aHeld = recovery.steer < 0
    car.state.dHeld = recovery.steer > 0
    if now - recovery.started >= 1.05 then recovery.phase = "forward"; recovery.started = now end
    return true
  elseif recovery.phase == "forward" then
    car.autopilot.behavior = "RECOVERY FORWARD"
    car.autopilot.status = "RECOVERY FORWARD"
    car.state.reverse = false
    car.state.clutch = true
    car.state.aHeld = recovery.steer > 0
    car.state.dHeld = recovery.steer < 0
    if now - recovery.started >= 1.35 then
      recovery.phase = nil
      car.ai.lastMovingAt = now
      car.ai.lastProgressAt = now
    end
    return true
  end
  return false
end

function car.stopAutopilot(reason)
  car.autopilot.enabled = false
  car.autopilot.status = reason or "OFF"
  car.autopilot.behavior = reason or "OFF"
  car.autopilot.targetSpeed = 0
  car.autopilot.steering = "CENTER"
  car.autopilot.stoppingDistance = 0
  car.ai.recovery.phase = nil
  car.ai.overtake.phase = nil
  car.state.aHeld = false
  car.state.dHeld = false
  car.state.reverse = car.state.reverseSelected
  car.state.clutch = car.cruiseOn
  car.applyOutputs()
end

function car.setAutopilot(enabled)
  if not enabled then car.stopAutopilot("OFF"); return true end
  if not car.map.destination then car.autopilot.status = "SET DESTINATION"; return false end
  car.updateMap(true)
  if not car.updateRoute(true) then car.autopilot.status = "ROUTE UNAVAILABLE"; return false end
  car.cruiseOn = false
  car.state.reverseSelected = false
  car.state.reverse = false
  car.autopilot.enabled = true
  car.autopilot.status = "READY"
  car.autopilot.behavior = "READY"
  car.ai.lastMovingAt = os.clock()
  car.ai.lastProgressAt = os.clock()
  car.ai.bestDestinationDistance = math.huge
  car.ai.blockingId = nil
  car.ai.blockingSince = nil
  car.ai.recovery.phase = nil
  car.ai.recovery.attempts = 0
  car.ai.overtake.phase = nil
  car.markVehicleStateDirty()
  return true
end

function car.updateAutopilot()
  if not car.autopilot.enabled then return end
  local now = os.clock()
  local position = car.vehicleWorldPosition()
  local points = car.routePoints()
  if not position or not points or #points < 1 then car.stopAutopilot("NO ROUTE"); return end
  if car.state.driveEngineOff then
    car.autopilot.status = "ENGINE OFF"
    car.state.clutch = false
    car.state.aHeld = false
    car.state.dHeld = false
    car.applyOutputs()
    return
  end
  local destination = car.map.destination
  local distanceToDestination = destination and math.sqrt((destination.x - position.x) ^ 2 + (destination.z - position.z) ^ 2) or math.huge
  if distanceToDestination <= 3 then car.stopAutopilot("ARRIVED"); return end
  car.aiUpdateDynamics(now, distanceToDestination)

  local confidence = tonumber(car.map.scan and car.map.scan.confidence) or 0
  if confidence < 0.12 then
    car.autopilot.status = "ROAD LOST"
    car.state.clutch = false
    car.state.aHeld = false
    car.state.dHeld = false
    car.applyOutputs()
    return
  end

  local geometry = car.aiRouteGeometry(position, points)
  local target = geometry and geometry.target
  local targetX, targetZ = target and tonumber(target.x), target and tonumber(target.z)
  local heading = car.shipHeading()
  if not targetX or not targetZ or not heading then
    car.autopilot.status = "HEADING WAIT"
    car.state.clutch = false
    car.applyOutputs()
    return
  end

  car.aiUpdatePerception(position, heading, target)
  local preliminaryStopDistance, preliminaryStopTime = car.aiStoppingModel(0)
  local traffic = car.aiAssessTraffic(position, heading, preliminaryStopDistance, preliminaryStopTime)
  local selectedMode, targetSpeed = car.aiChooseMode(geometry, traffic, distanceToDestination)
  if car.driveMode ~= selectedMode then car.setDriveMode(selectedMode) end
  car.autopilot.selectedMode = selectedMode == "normal" and "standard" or selectedMode

  local lateralAcceleration = selectedMode == "sport_plus" and 3.8 or (selectedMode == "sport" and 2.8 or 1.8)
  local curveSpeed = math.sqrt(math.max(1, lateralAcceleration * geometry.turnRadius))
  if geometry.turnAngle > 0.05 then targetSpeed = math.min(targetSpeed, curveSpeed) end
  local crosswalkDistance = tonumber(car.map.scan and car.map.scan.crosswalkDistance) or -1
  local tunnelCells = tonumber(car.map.scan and car.map.scan.tunnelCells) or 0
  if crosswalkDistance >= 0 and crosswalkDistance < 18 then targetSpeed = math.min(targetSpeed, 2.8) end
  if tunnelCells > 0 then targetSpeed = math.min(targetSpeed, 4.5) end
  if geometry.turnAngle > 0.45 then targetSpeed = math.min(targetSpeed, 3.2) end
  if distanceToDestination < 16 then targetSpeed = math.min(targetSpeed, math.max(1.5, distanceToDestination * 0.35)) end

  local size = car.map.shipSize
  local vehicleWidth = type(size) == "table" and math.min(tonumber(size.width) or 0, tonumber(size.length) or 0) or 0
  local roadWidth = tonumber(car.map.scan and car.map.scan.estimatedWidth) or 12
  if vehicleWidth > 0 and roadWidth > 0 and vehicleWidth + 1 > roadWidth then car.stopAutopilot("VEHICLE TOO WIDE"); return end

  local offset, overtakeBehavior = car.aiOvertakeOffset(traffic, geometry, now)
  local steeringTarget = car.aiOffsetTarget(position, target, offset)
  local desiredHeading = car.atan2((tonumber(steeringTarget.z) or targetZ) - position.z, (tonumber(steeringTarget.x) or targetX) - position.x)
  local headingError = car.normalizeAngle(desiredHeading - heading)

  if traffic.lead and not overtakeBehavior then
    local followingSpeed = math.max(0, traffic.lead.speed - clamp((12 - traffic.lead.longitudinal) * 0.18, 0, 2.5))
    targetSpeed = math.min(targetSpeed, followingSpeed)
  end
  if traffic.hardStop then targetSpeed = 0 end

  local stopDistance, stopTime = car.aiStoppingModel(targetSpeed)
  car.autopilot.stoppingDistance = stopDistance
  car.autopilot.stoppingTime = stopTime
  car.autopilot.obstacleDistance = traffic.nearest

  if traffic.stationaryBlock then
    if car.ai.blockingId ~= traffic.stationaryBlock.id then
      car.ai.blockingId = traffic.stationaryBlock.id
      car.ai.blockingSince = now
    elseif now - (car.ai.blockingSince or now) > 3.5 and now - car.ai.lastDetour > 4 then
      car.ai.lastDetour = now
      local contact = traffic.stationaryBlock.contact
      local avoidRadius = math.max(5, (tonumber(contact.width) or 2) + (tonumber(contact.length) or 4) * 0.5 + 2)
      if car.updateRoute(true, { x = contact.x, z = contact.z, radius = avoidRadius }) then
        car.autopilot.status = "DETOUR"
        car.autopilot.behavior = "DETOUR"
        points = car.routePoints() or points
      end
    end
  else
    car.ai.blockingId = nil
    car.ai.blockingSince = nil
  end

  local shouldRecover = car.state.clutch and targetSpeed > 1.5 and speedBps < 0.18
    and now - car.ai.lastMovingAt > 2.8 and now - car.ai.lastProgressAt > 2.8
    and not traffic.stationaryBlock
  if car.aiRecoveryControl(now, headingError, traffic, shouldRecover) then
    car.autopilot.targetSpeed = 1.5
    car.applyOutputs()
    return
  end

  car.state.reverse = false
  car.aiSetSteering(headingError, overtakeBehavior ~= nil)
  if traffic.hardStop then
    car.autopilot.status = traffic.reason or "BRAKE"
    car.autopilot.behavior = "EMERGENCY STOP"
  elseif overtakeBehavior then
    car.autopilot.status = overtakeBehavior
    car.autopilot.behavior = overtakeBehavior
  elseif traffic.lead then
    car.autopilot.status = "FOLLOW"
    car.autopilot.behavior = "FOLLOW"
  elseif targetSpeed < 1 then
    car.autopilot.status = "HOLD"
    car.autopilot.behavior = "HOLD"
  elseif geometry.turnAngle > 0.18 then
    car.autopilot.status = "CORNER"
    car.autopilot.behavior = "CORNER"
  else
    car.autopilot.status = "CRUISE"
    car.autopilot.behavior = "CRUISE"
  end
  car.autopilot.targetSpeed = targetSpeed
  if targetSpeed <= 0.05 then
    car.state.clutch = false
  elseif speedBps < targetSpeed - 0.35 then
    car.state.clutch = true
  elseif speedBps > targetSpeed + 0.15 then
    car.state.clutch = false
  end
  car.applyOutputs()
end

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

  local moveX = curPos.x - prevPos.x
  local moveZ = curPos.z - prevPos.z
  local horizontal = math.sqrt(moveX * moveX + moveZ * moveZ)
  if horizontal > 0.03 and not car.state.reverse then
    car.motionHeading = car.atan2(moveZ, moveX)
    car.motionHeadingTime = t
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

local nativeTerm = term.current()
local ui = nativeTerm
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
  local hdTerm = car.getHDTerminal and car.getHDTerminal() or nil
  local mon = hdTerm and nil or getPrimaryMonitor()
  if hdTerm then
    ui = hdTerm
  elseif mon then
    ui = mon
    if mon.setTextScale then pcall(function() mon.setTextScale(settings.textScale) end) end
  else
    ui = term.current()
  end
  term.redirect(ui)

  local w, h = term.getSize()
  local compact = w < 48 or h < 12
  local hdCompact = car.hd.ready and w >= 64 and h >= 16
  local hdDense = car.hd.ready and w >= 88 and h >= 28
  local leftW
  local rightW
  if hdDense then
    leftW = 10
    rightW = 9
  elseif hdCompact then
    leftW = clamp(math.floor(w * 0.15), 11, 14)
    rightW = clamp(math.floor(w * 0.15), 10, 14)
  else
    leftW = compact and clamp(math.floor(w * 0.25), 7, math.max(7, w - 12)) or math.floor(w / 3)
    rightW = compact and clamp(math.floor(w * 0.16), 5, math.max(5, w - leftW - 8))
      or clamp(math.floor(math.max(1, w - (2 * math.floor(w / 3))) * 0.22), 6, 10)
  end
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
    monW = leftW, rightMonitorW = rightW,
    compact = compact,
    hdCompact = hdCompact,
    hdDense = hdDense
  }
end

local function writeAt(win, x, y, s, fg, bg)
  local winW, winH = win.getSize()
  x = math.floor(tonumber(x) or 1)
  y = math.floor(tonumber(y) or 1)
  s = tostring(s or "")
  if y < 1 or y > winH or x > winW or s == "" then return end
  if x < 1 then
    s = s:sub(2 - x)
    x = 1
  end
  s = s:sub(1, math.max(0, winW - x + 1))
  if s == "" then return end
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
  local winW, winH = win.getSize()
  x = math.floor(tonumber(x) or 1)
  y = math.floor(tonumber(y) or 1)
  w = math.floor(tonumber(w) or 0)
  h = math.floor(tonumber(h) or 0)
  if x < 1 then w = w - (1 - x); x = 1 end
  if y < 1 then h = h - (1 - y); y = 1 end
  w = math.min(w, winW - x + 1)
  h = math.min(h, winH - y + 1)
  if w <= 0 or h <= 0 then return end
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

function car.approach(current, target, amount)
  if current < target then return math.min(target, current + amount) end
  if current > target then return math.max(target, current - amount) end
  return target
end

function car.easeOutCubic(value)
  value = clamp(tonumber(value) or 0, 0, 1)
  local inverse = 1 - value
  return 1 - inverse * inverse * inverse
end

function car.bumpAnimation(key)
  if not key then return end
  car.animations.presses[key] = 1
end

function car.animationProgress(key, active)
  local values = car.animations.values
  local presses = car.animations.presses
  local current = tonumber(values[key]) or 0
  current = car.approach(current, active and 1 or 0, active and 0.22 or 0.18)
  local press = tonumber(presses[key]) or 0
  if press > 0 then
    press = math.max(0, press - 0.28)
    presses[key] = press > 0 and press or nil
  end
  values[key] = current
  return car.easeOutCubic(math.max(current, press * 0.16))
end

function car.drawAnimatedLine(win, x, y, w, text, overlayWidth, activeFg, inactiveFg, activeBg, inactiveBg)
  text = trim(text or "", math.max(1, w - (w >= 3 and 2 or 0)))
  local startX = x + math.max(0, math.floor((w - #text) / 2))
  local overlayEnd = x + overlayWidth - 1
  for index = 1, #text do
    local charX = startX + index - 1
    local covered = overlayWidth > 0 and charX <= overlayEnd
    writeAt(win, charX, y, text:sub(index, index), covered and activeFg or inactiveFg, covered and activeBg or inactiveBg)
  end
end

function car.drawAnimatedButton(win, x, y, w, h, key, line1, line2, active, activeBg, inactiveBg)
  if w < 1 or h < 1 then return end
  activeBg = activeBg or COLORS.activeBg
  inactiveBg = inactiveBg or COLORS.panel
  local activeFg = activeBg == COLORS.activeBg and COLORS.activeText or bestFg(activeBg)
  local inactiveFg = inactiveBg == COLORS.panel and COLORS.panelText or bestFg(inactiveBg)
  local progress = car.animationProgress(key, active)
  local overlayWidth = math.floor(w * progress + 0.5)
  fillRect(win, x, y, w, h, inactiveBg)
  if overlayWidth > 0 then fillRect(win, x, y, overlayWidth, h, activeBg) end
  if line2 and line2 ~= "" and h >= 2 then
    local firstY = y + math.floor((h - 2) / 2)
    car.drawAnimatedLine(win, x, firstY, w, line1, overlayWidth, activeFg, inactiveFg, activeBg, inactiveBg)
    car.drawAnimatedLine(win, x, firstY + 1, w, line2, overlayWidth, activeFg, inactiveFg, activeBg, inactiveBg)
  else
    car.drawAnimatedLine(win, x, y + math.floor((h - 1) / 2), w, line1, overlayWidth, activeFg, inactiveFg, activeBg, inactiveBg)
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
    if car.flushHD then car.flushHD() end
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
  local created = sanitizeRRIDInput(_G.ROADROVER_DEFAULT_USER or "DRIVER")
  saveRRID(created)
  return setCurrentUser(created)
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
    if car.flushHD then car.flushHD() end
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
  { id = "settings", title = "Settings", label = "Settings", page = 1 },
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

  return tonumber(bf.height) or 3
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
  local fontHeight = bf and tonumber(bf.height) or 3
  local canBig = bf and type(bf.bigWrite) == "function"
    and bigTextWidth(l1) <= bigW and bigTextWidth(l2) <= bigW
    and bigH >= fontHeight * 2
  if canBig then
    local totalH = fontHeight * 2
    local ty = bigY + math.floor((bigH - totalH) / 2)
    local x1 = bigX + math.floor((bigW - bigTextWidth(l1)) / 2)
    local x2 = bigX + math.floor((bigW - bigTextWidth(l2)) / 2)
    drawBigLabel(centerWin, x1, ty, l1, COLORS.panel, COLORS.panelText, bf)
    drawBigLabel(centerWin, x2, ty + fontHeight, l2, COLORS.panel, COLORS.panelText, bf)
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

  local bigH = canBig and (tonumber(bf.height) or 3) or 1
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
  local uy = by + bigH
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

function car.drawHomeNavigation(top, availableH, mapX, settingsX, quickW, modeX, modeW)
  local navigationH = layout.hdDense and math.min(availableH, 5)
    or (layout.hdCompact and math.min(availableH, 7) or availableH)
  if quickW > 0 then
    fillRect(centerWin, mapX, top, quickW, navigationH, COLORS.panel)
    drawVerticalLabel(centerWin, mapX, top, quickW, navigationH, "MAP", COLORS.panelText, COLORS.panel)
    quickMapBox = {
      x1 = layout.centerX + mapX - 1,
      y1 = top,
      x2 = layout.centerX + mapX + quickW - 2,
      y2 = top + navigationH - 1
    }

    fillRect(centerWin, settingsX, top, quickW, navigationH, COLORS.panel)
    drawVerticalLabel(centerWin, settingsX, top, quickW, navigationH, "SETTINGS", COLORS.panelText, COLORS.panel, 2)
    quickSettingsBox = {
      x1 = layout.centerX + settingsX - 1,
      y1 = top,
      x2 = layout.centerX + settingsX + quickW - 2,
      y2 = top + navigationH - 1
    }
  end

  local modes = {
    { id = "standard", label = "ST", active = car.state.mode == "standard" },
    { id = "sport", label = "S", active = car.state.mode == "sport" },
    { id = "sport_plus", label = "S+", active = car.state.mode == "sport_plus" }
  }
  local modeGap = 1
  local modeH = layout.hdDense and 1
    or (layout.hdCompact and 2 or math.max(2, math.floor((availableH - modeGap * 2) / 3)))
  for index = 1, #modes do
    local mode = modes[index]
    local y = top + (index - 1) * (modeH + modeGap)
    local height = layout.hdCompact and modeH or (index == #modes and layout.h - y + 1 or modeH)
    local text = trim(mode.label, math.max(1, modeW - (mode.active and 0 or 2)))
    car.drawAnimatedButton(centerWin, modeX, y, modeW, height, "mode:" .. mode.id, text, nil, mode.active, COLORS.activeBg, COLORS.panel)
    car.driveBoxes[mode.id] = {
      x1 = layout.centerX + modeX - 1,
      y1 = y,
      x2 = layout.centerX + modeX + modeW - 2,
      y2 = y + height - 1
    }
  end
end

function car.drawHomeControls(top, availableH, controlsX, controlsW)
  if controlsW < 6 then return end
  local columns = layout.hdCompact and 4 or 2
  local rows = layout.hdCompact and 2 or 4
  local buttonGap = availableH < 11 and 0 or 1
  local buttonW = math.floor((controlsW - buttonGap * (columns - 1)) / columns)
  local buttonH = layout.hdDense and 2
    or (layout.hdCompact and 3 or math.max(1, math.floor((availableH - buttonGap * (rows - 1)) / rows)))
  local controls = {
    { id = "work_engine", title = "SHOP", status = car.state.workshopEngineOff and "OFF" or "ON", active = car.state.workshopEngineOff },
    { id = "drive_engine", title = "DRIVE", status = car.state.driveEngineOff and "OFF" or "ON", active = car.state.driveEngineOff },
    { id = "cruise", title = "CRUISE", status = car.cruiseOn and "ON" or "OFF", active = car.cruiseOn },
    { id = "front_drive", title = "TRACTION", status = car.state.frontDriveOff and "2WD" or "AWD", active = not car.state.frontDriveOff },
    { id = "boost", title = "BOOST", status = car.state.workshopBoost and "ON" or "OFF", active = car.state.workshopBoost },
    { id = "headlights", title = "LIGHTS", status = car.state.lighting == "headlights" and "ON" or "OFF", active = car.state.lighting == "headlights" },
    { id = "suspension_up", title = "/\\", status = car.state.suspension == "up" and "ACTIVE" or "HOLD", active = car.state.suspension == "up" },
    { id = "suspension_down", title = "\\/", status = car.state.suspension == "down" and "ACTIVE" or "HOLD", active = car.state.suspension == "down" }
  }
  for index = 1, #controls do
    local control = controls[index]
    local column = ((index - 1) % columns) + 1
    local row = math.floor((index - 1) / columns) + 1
    local x = controlsX + (column - 1) * (buttonW + buttonGap)
    local y = top + (row - 1) * (buttonH + buttonGap)
    local width = column == columns and layout.centerW - x + 1 or buttonW
    local height = math.min(buttonH, layout.h - y + 1)
    if width >= 1 and height >= 1 then
      local line1 = trim(height == 1 and control.status or control.title, math.max(1, width - 2))
      local line2 = trim(control.status, math.max(1, width - 2))
      car.drawAnimatedButton(centerWin, x, y, width, height, "home:" .. control.id, line1, height > 1 and line2 or nil, control.active, COLORS.activeBg, COLORS.panel)
      car.driveBoxes[control.id] = {
        x1 = layout.centerX + x - 1,
        y1 = y,
        x2 = layout.centerX + x + width - 2,
        y2 = y + height - 1
      }
    end
  end
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

  engineBox = nil
  cruiseBox = nil
  quickBox = nil
  modeStandardBox = nil
  modeSportBox = nil

  local top = math.max(2, y0)
  local availableH = math.max(1, layout.h - top + 1)
  local gap = 1
  local quickW = layout.compact and 0 or (layout.hdCompact and 2 or (layout.centerW >= 32 and 3 or 2))
  local modeW = layout.hdCompact and 3 or (layout.centerW >= 32 and 4 or 3)
  local mapX = 1
  local settingsX = mapX + quickW + gap
  local modeX = quickW > 0 and (settingsX + quickW + gap) or 1
  local controlsX = modeX + modeW + gap
  local controlsW = layout.centerW - controlsX + 1

  car.drawHomeNavigation(top, availableH, mapX, settingsX, quickW, modeX, modeW)
  car.drawHomeControls(top, availableH, controlsX, controlsW)
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
  local columns = layout.hdCompact and (layout.centerW >= 64 and 5 or 4) or 3
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
    local line1, line2 = wrap2(title, math.max(1, width - 2))
    if height == 1 then
      local label = trim(line1 .. (status and (" " .. status) or ""), width)
      car.drawAnimatedButton(centerWin, x, y, width, height, "drive:" .. id, label, nil, active, accent or colors.lime, COLORS.panel)
    else
      local label1 = trim(line1, width)
      local label2 = trim(status or line2 or "", width)
      car.drawAnimatedButton(centerWin, x, y, width, height, "drive:" .. id, label1, label2, active, accent or colors.lime, COLORS.panel)
    end
    car.driveBoxes[id] = {
      x1 = layout.centerX + x - 1,
      y1 = y,
      x2 = layout.centerX + x + width - 2,
      y2 = y + height - 1
    }
  end

  local controls = {
    { "standard", "STANDARD", "MODE", car.state.mode == "standard", colors.lightBlue },
    { "sport", "SPORT", "MODE", car.state.mode == "sport", colors.orange },
    { "sport_plus", "SPORT+", "MODE", car.state.mode == "sport_plus", colors.red },
    { "clutch", "CLUTCH", "W / S", car.state.clutch, colors.lime },
    { "reverse", "REVERSE", "S", car.state.reverse, colors.orange },
    { "front_drive", "FRONT DRIVE", car.state.frontDriveOff and "OFF" or "ON", car.state.frontDriveOff, colors.red },
    { "drive_engine", "DRIVE ENGINE", car.state.driveEngineOff and "OFF" or "ON", car.state.driveEngineOff, colors.red },
    { "work_engine", "SHOP ENGINE", car.state.workshopEngineOff and "OFF" or "ON", car.state.workshopEngineOff, colors.red },
    { "boost", "SHOP BOOST", car.state.workshopBoost and "ON" or "OFF", car.state.workshopBoost, colors.orange },
    { "headlights", "HEADLIGHTS", "L", car.state.lighting == "headlights", colors.lightBlue },
    { "left", "LEFT SIGNAL", "Z", car.state.lighting == "left", colors.yellow },
    { "right", "RIGHT SIGNAL", "C", car.state.lighting == "right", colors.yellow },
    { "hazard", "HAZARD", "X", car.state.lighting == "hazard", colors.red },
    { "heading", "PORT HEADING", car.state.portHeading:upper(), false, colors.lightBlue }
  }
  for index = 1, #controls do
    local control = controls[index]
    local column = ((index - 1) % columns) + 1
    local row = math.floor((index - 1) / columns) + 1
    addControl(control[1], column, row, control[2], control[3], control[4], control[5])
  end

  local controlRows = math.ceil(#controls / columns)
  local statusY = y0 + controlRows * (buttonH + gapY)
  if statusY <= layout.h then
    local portStatus = car.devices.portName and ("Port: " .. car.devices.portName) or "Port: not found"
    writeAt(centerWin, 2, statusY, trim(portStatus, layout.centerW - 2), car.devices.portName and COLORS.fg or colors.red, COLORS.bg)
  end
  if statusY + 1 <= layout.h then
    local keyboardStatus = car.devices.keyboardName and ("Keyboard: " .. car.devices.keyboardName) or "Keyboard: not found"
    writeAt(centerWin, 2, statusY + 1, trim(car.devices.error or keyboardStatus, layout.centerW - 2), car.devices.error and colors.red or COLORS.fg, COLORS.bg)
  end
  if statusY + 2 <= layout.h then
    local secondaryStatus = car.devices.secondaryPortName and ("Port 2: " .. car.devices.secondaryPortName) or "Port 2: not connected"
    writeAt(centerWin, 2, statusY + 2, trim(secondaryStatus, layout.centerW - 2), car.devices.secondaryPortName and COLORS.fg or colors.red, COLORS.bg)
  end
end

function car.mapProject(worldX, worldZ, centerX, centerZ, radius, x1, y1, x2, y2)
  local width = math.max(1, x2 - x1)
  local height = math.max(1, y2 - y1)
  local sx = x1 + math.floor(((worldX - centerX + radius) / (radius * 2)) * width + 0.5)
  local sy = y1 + math.floor(((worldZ - centerZ + radius) / (radius * 2)) * height + 0.5)
  if sx < x1 or sx > x2 or sy < y1 or sy > y2 then return nil, nil end
  return sx, sy
end

function car.drawMapLine(x1, y1, x2, y2, color)
  local dx = math.abs(x2 - x1)
  local sx = x1 < x2 and 1 or -1
  local dy = -math.abs(y2 - y1)
  local sy = y1 < y2 and 1 or -1
  local err = dx + dy
  while true do
    fillRect(centerWin, x1, y1, 1, 1, color)
    if x1 == x2 and y1 == y2 then break end
    local e2 = 2 * err
    if e2 >= dy then err = err + dy; x1 = x1 + sx end
    if e2 <= dx then err = err + dx; y1 = y1 + sy end
  end
end

function car.drawMap(y0)
  engineBox = nil
  actionBoxes = {}
  settingsBoxes = {}
  car.driveBoxes = {}
  car.map.boxes = {}
  car.updateMap(false)

  local view = car.map.view
  local scan = car.map.scan
  local status = car.map.error or car.map.notice
  if not status and car.autopilot.enabled then
    status = "AI " .. tostring(car.autopilot.status) .. "  " .. tostring(car.autopilot.selectedMode):upper()
      .. "  " .. fmt(car.autopilot.targetSpeed, 1) .. " b/s  STOP " .. fmt(car.autopilot.stoppingDistance, 1)
  elseif not status and car.map.destination then
    status = "Destination " .. math.floor(car.map.destination.x) .. ", " .. math.floor(car.map.destination.z)
  elseif not status then
    status = "Tap map to set destination"
  end
  writeAt(centerWin, 2, y0, trim(status, math.max(1, layout.centerW - 2)), car.map.error and colors.red or COLORS.fg, COLORS.bg)

  local mapX1 = 2
  local mapY1 = y0 + 1
  local mapX2 = math.max(mapX1, layout.centerW - 1)
  local controlsY = layout.h
  local mapY2 = math.max(mapY1, controlsY - 2)
  fillRect(centerWin, mapX1, mapY1, mapX2 - mapX1 + 1, mapY2 - mapY1 + 1, colors.lightGray)

  if type(view) == "table" then
    local center = view.center or {}
    local centerX = tonumber(center.x) or 0
    local centerZ = tonumber(center.z) or 0
    local radius = tonumber(view.radius) or (car.map.zooms[car.map.zoomIndex] or 32)
    car.map.viewport = {
      x1 = layout.centerX + mapX1 - 1, y1 = mapY1,
      x2 = layout.centerX + mapX2 - 1, y2 = mapY2,
      localX1 = mapX1, localY1 = mapY1, localX2 = mapX2, localY2 = mapY2,
      centerX = centerX, centerZ = centerZ, radius = radius
    }

    if type(view.samples) == "table" then
      for _, sample in pairs(view.samples) do
        if type(sample) == "table" then
          local worldX = centerX + (tonumber(sample.x) or 0)
          local worldZ = centerZ + (tonumber(sample.z) or 0)
          local sx, sy = car.mapProject(worldX, worldZ, centerX, centerZ, radius, mapX1, mapY1, mapX2, mapY2)
          if sx and sy then
            local kind = tostring(sample.kind or "")
            local color = colors.gray
            if kind == "road" then color = colors.black
            elseif kind == "crosswalk_marker" then color = colors.yellow
            elseif kind == "crosswalk" then color = colors.white
            elseif kind == "sidewalk" then color = colors.lightGray end
            if sample.tunnel == true then color = ((sx + sy) % 2 == 0) and colors.gray or color end
            fillRect(centerWin, sx, sy, 1, 1, color)
          end
        end
      end
    end

    local points = car.routePoints()
    if points and #points > 0 then
      local previousX, previousY = nil, nil
      for index = 1, #points do
        local point = points[index]
        local sx, sy = car.mapProject(tonumber(point.x) or 0, tonumber(point.z) or 0, centerX, centerZ, radius, mapX1, mapY1, mapX2, mapY2)
        if sx and sy then
          if previousX then car.drawMapLine(previousX, previousY, sx, sy, colors.lightBlue) end
          previousX, previousY = sx, sy
        else
          previousX, previousY = nil, nil
        end
      end
    end

    local ships = car.ai.perception.ships
    if type(ships) == "table" and type(ships.ships) == "table" then
      for _, contact in pairs(ships.ships) do
        if type(contact) == "table" then
          local sx, sy = car.mapProject(tonumber(contact.x) or 0, tonumber(contact.z) or 0, centerX, centerZ, radius, mapX1, mapY1, mapX2, mapY2)
          if sx and sy then writeAt(centerWin, sx, sy, "V", colors.white, colors.orange) end
        end
      end
    end
    local protectedTraffic = car.ai.perception.traffic
    if type(protectedTraffic) == "table" and type(protectedTraffic.traffic) == "table" then
      for _, contact in pairs(protectedTraffic.traffic) do
        if type(contact) == "table" then
          local sx, sy = car.mapProject(tonumber(contact.x) or 0, tonumber(contact.z) or 0, centerX, centerZ, radius, mapX1, mapY1, mapX2, mapY2)
          if sx and sy then writeAt(centerWin, sx, sy, "!", colors.white, colors.red) end
        end
      end
    end

    if car.map.destination then
      local dx, dy = car.mapProject(car.map.destination.x, car.map.destination.z, centerX, centerZ, radius, mapX1, mapY1, mapX2, mapY2)
      if dx and dy then
        fillRect(centerWin, dx, dy, 1, 1, colors.red)
        writeAt(centerWin, dx, dy, "X", colors.white, colors.red)
      end
    end
    local vehicle = view.vehicle or (scan and scan.center)
    if type(vehicle) == "table" then
      local vx, vy = car.mapProject(tonumber(vehicle.x) or 0, tonumber(vehicle.z) or 0, centerX, centerZ, radius, mapX1, mapY1, mapX2, mapY2)
      if vx and vy then writeAt(centerWin, vx, vy, "^", colors.black, colors.lime) end
    end
  else
    car.map.viewport = nil
    centerText(centerWin, math.floor((mapY1 + mapY2) / 2), "Map unavailable", layout.centerW, colors.red, colors.lightGray)
  end

  if car.map.errorDetail then
    local detail = safe(car.map.errorDetail)
    local width = math.max(1, mapX2 - mapX1 + 1)
    local maxLines = math.max(1, math.min(4, mapY2 - mapY1 + 1))
    fillRect(centerWin, mapX1, mapY1, width, maxLines, colors.red)
    for line = 1, maxLines do
      local first = (line - 1) * width + 1
      if first > #detail then break end
      writeAt(centerWin, mapX1, mapY1 + line - 1, detail:sub(first, first + width - 1), colors.white, colors.red)
    end
  end

  local controls = {
    { "zoom_out", "-" }, { "zoom_in", "+" }, { "pan_left", "<" }, { "pan_right", ">" },
    { "pan_up", "^" }, { "pan_down", "v" }, { "recenter", "C" }, { "autopilot", car.autopilot.enabled and "STOP" or "AUTO" }
  }
  local gap = 1
  local available = layout.centerW - 2
  local buttonW = math.max(1, math.floor((available - gap * (#controls - 1)) / #controls))
  local x = 2
  for index = 1, #controls do
    local control = controls[index]
    local width = index == #controls and math.max(1, layout.centerW - x) or buttonW
    local active = control[1] == "autopilot" and car.autopilot.enabled
    local bg = active and colors.lime or COLORS.panel
    writeAt(centerWin, x, controlsY, trim(control[2], width), bestFg(bg), bg)
    car.map.boxes[control[1]] = {
      x1 = layout.centerX + x - 1, y1 = controlsY,
      x2 = layout.centerX + x + width - 2, y2 = controlsY
    }
    x = x + width + gap
    if x > layout.centerW then break end
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
  car.map.boxes = {}
  car.map.viewport = nil

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
  elseif id == "map" then
    car.drawMap(y0)
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
  local tabH = layout.hdCompact and 1 or 2
  local startY = layout.hdCompact and 2 or 3
  local pageH = layout.hdCompact and 0 or 2
  local pageY = pageH > 0 and math.max(2, layout.h - pageH + 1) or layout.h + 1
  local bottom = pageH > 0 and pageY - 1 or layout.h
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
    if layout.hdCompact or (tabs[i].page or 1) == tabPage then
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
    local label = trim(t.label or t.title or "", math.max(1, l.tabW - 2))
    car.drawAnimatedButton(rightWin, l.tabsX, y, l.tabW, l.tabH, "sidebar:" .. t.id, label, nil, active, COLORS.activeBg, COLORS.panel)

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
  if l.pageH < 1 then
    pageBox = nil
    return
  end
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
  drawLeft()
  drawCenter()
  drawRight()
  if car.flushHD then car.flushHD() end
end

function car.loadHDRenderer()
  local modulePath = (SCRIPT_DIR ~= "" and fs.combine(SCRIPT_DIR, "roadrover-hd.lua")) or "roadrover-hd.lua"
  if not fs.exists(modulePath) then car.hd.error = "roadrover-hd.lua missing"; return false end
  local loaded, attach = pcall(dofile, modulePath)
  if not loaded or type(attach) ~= "function" then car.hd.error = tostring(attach); return false end
  local attached, attachError = pcall(attach, car, {
    version = VERSION,
    scriptDir = SCRIPT_DIR,
    tabs = tabs,
    settings = settings,
    stats = stats,
    getActiveTab = function() return activeTab end,
    selectTab = function(id)
      for index = 1, #tabs do
        if tabs[index].id == id then
          activeTab = index
          tabPage = tabs[index].page or tabPage
          return true
        end
      end
      return false
    end,
    getSpeed = function() return speedBps end,
    saveSettings = saveUserSettings,
    displayUserName = displayUserName,
    fmt = fmt,
    fmtTime = fmtTime
  })
  car.hd.error = attached and nil or tostring(attachError)
  return attached
end

car.loadHDRenderer()

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

function car.releaseSuspension()
  if car.suspensionTimer and os.cancelTimer then pcall(os.cancelTimer, car.suspensionTimer) end
  car.suspensionTimer = nil
  if car.state.suspension == "neutral" then return false end
  car.state.suspension = "neutral"
  car.applyOutputs()
  return true
end

function car.setSuspension(direction, fallback)
  if direction ~= "up" and direction ~= "down" then return car.releaseSuspension() end
  if car.suspensionTimer and os.cancelTimer then pcall(os.cancelTimer, car.suspensionTimer) end
  car.suspensionTimer = nil
  car.state.suspension = direction
  car.applyOutputs()
  if fallback then car.suspensionTimer = os.startTimer(car.suspensionFallbackSeconds) end
  return true
end

function car.suspensionControlAt(mx, my)
  local upBox = car.driveBoxes.suspension_up
  local downBox = car.driveBoxes.suspension_down
  if hit(upBox, mx, my) then return "up", "suspension_up" end
  if hit(downBox, mx, my) then return "down", "suspension_down" end
  return nil, nil
end

function car.handleDriveControl(id)
  if car.autopilot.enabled then car.stopAutopilot("MANUAL") end
  car.bumpAnimation("drive:" .. tostring(id))
  car.bumpAnimation("home:" .. tostring(id))
  car.bumpAnimation("mode:" .. tostring(id))
  if id == "standard" then
    car.setDriveMode("normal")
  elseif id == "sport" then
    car.setDriveMode("sport")
  elseif id == "sport_plus" then
    car.setDriveMode("sport_plus")
  elseif id == "clutch" then
    car.state.clutch = not car.state.clutch
    car.cruiseOn = car.state.clutch
  elseif id == "cruise" then
    car.cruiseOn = not car.cruiseOn
    car.driveOutput(DRIVE_SIDE, car.cruiseOn)
    car.markVehicleStateDirty()
    return true
  elseif id == "reverse" then
    car.state.reverseSelected = not car.state.reverseSelected
    car.state.reverse = car.state.reverseSelected or car.state.sHeld
  elseif id == "front_drive" then
    car.state.frontDriveOff = not car.state.frontDriveOff
  elseif id == "drive_engine" then
    car.state.driveEngineOff = not car.state.driveEngineOff
    car.engineOn = not car.state.driveEngineOff
  elseif id == "work_engine" then
    car.state.workshopEngineOff = not car.state.workshopEngineOff
  elseif id == "boost" then
    car.state.workshopBoost = not car.state.workshopBoost
  elseif id == "suspension_up" or id == "suspension_down" then
    return false
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
  car.markVehicleStateDirty()
  return true
end

local function handleClick(mx, my)
  for id, box in pairs(car.map.boxes or {}) do
    if hit(box, mx, my) then
      local radius = car.map.zooms[car.map.zoomIndex] or 32
      local panStep = math.max(4, math.floor(radius / 2))
      if id == "zoom_out" then
        car.map.zoomIndex = math.min(#car.map.zooms, car.map.zoomIndex + 1)
      elseif id == "zoom_in" then
        car.map.zoomIndex = math.max(1, car.map.zoomIndex - 1)
      elseif id == "pan_left" then
        car.map.panX = car.map.panX - panStep
      elseif id == "pan_right" then
        car.map.panX = car.map.panX + panStep
      elseif id == "pan_up" then
        car.map.panZ = car.map.panZ - panStep
      elseif id == "pan_down" then
        car.map.panZ = car.map.panZ + panStep
      elseif id == "recenter" then
        car.map.panX = 0
        car.map.panZ = 0
      elseif id == "autopilot" then
        car.setAutopilot(not car.autopilot.enabled)
      end
      car.map.lastUpdate = -1e9
      car.updateMap(true)
      return true
    end
  end
  local viewport = car.map.viewport
  if viewport and hit(viewport, mx, my) then
    if car.autopilot.enabled then car.stopAutopilot("DESTINATION CHANGED") end
    local width = math.max(1, viewport.x2 - viewport.x1)
    local height = math.max(1, viewport.y2 - viewport.y1)
    local worldX = viewport.centerX + ((mx - viewport.x1) / width * 2 - 1) * viewport.radius
    local worldZ = viewport.centerZ + ((my - viewport.y1) / height * 2 - 1) * viewport.radius
    car.map.destination = { x = math.floor(worldX + 0.5), z = math.floor(worldZ + 0.5) }
    car.map.lastRoute = -1e9
    car.updateRoute(true)
    car.markVehicleStateDirty()
    return true
  end
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
    car.markVehicleStateDirty()
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
      car.markVehicleStateDirty()
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
      if tabs[activeTab] then car.bumpAnimation("sidebar:" .. tabs[activeTab].id) end
      return true
    end
  end

  return false
end

function car.handlePointer(mx, my, isDown, supportsRelease)
  if isDown == false then return car.releaseSuspension() end
  if isDown ~= true then return false end
  local direction, id = car.suspensionControlAt(mx, my)
  if direction then
    car.bumpAnimation("home:" .. id)
    car.bumpAnimation("drive:" .. id)
    return car.setSuspension(direction, not supportsRelease)
  end
  return handleClick(mx, my)
end

function car.handleTouchEvent(mx, my, pressed, hasRelease)
  local pointer = car.pointer
  local now = os.clock()
  if not hasRelease then return car.handlePointer(mx, my, true, false) end
  if pressed then
    pointer.lastSeen = now
    pointer.x, pointer.y = mx, my
    if pointer.down then
      local direction = car.suspensionControlAt(mx, my)
      if direction then return car.setSuspension(direction, false) end
      return false
    end
    pointer.down = true
    return car.handlePointer(mx, my, true, true)
  end
  if pointer.down then
    pointer.down = false
    pointer.lastSeen = now
    pointer.x, pointer.y = nil, nil
    return car.handlePointer(mx, my, false, true)
  end
  return car.handlePointer(mx, my, true, false)
end

function car.updateHardware()
  car.scanDevices(false)
  car.updateMap(false)
  car.updateAutopilot()
  local now = os.clock()
  if car.pointer.down and now - car.pointer.lastSeen > 0.8 then
    car.pointer.down = false
    car.pointer.x, car.pointer.y = nil, nil
    car.releaseSuspension()
  end
  if car.state.lighting ~= "none" and car.state.lighting ~= "headlights" and now - car.lastBlink >= car.blinkPeriod then
    car.state.blink = not car.state.blink
    car.lastBlink = now
  end
  car.applyOutputs()
  car.flushVehicleState(false)
end

function car.keyName(code)
  if type(code) == "string" then return code:lower() end
  if keys then
    local fixed = {
      [keys.w] = "w", [keys.s] = "s", [keys.a] = "a", [keys.d] = "d",
      [keys.f] = "f", [keys.g] = "g", [keys.l] = "l",
      [keys.z] = "z", [keys.c] = "c", [keys.x] = "x"
    }
    if fixed[code] then return fixed[code] end
  end
  if keys and keys.getName then
    local ok, name = pcall(keys.getName, code)
    if ok and name then return tostring(name):lower() end
  end
  return tostring(code or ""):lower()
end

function car.handleKey(code, down, repeated)
  local name = car.keyName(code)
  local fresh = down and not repeated
  if car.autopilot.enabled and down and (name == "w" or name == "s" or name == "a" or name == "d") then
    car.stopAutopilot("MANUAL")
  end
  if name == "w" then
    car.state.wHeld = down
    car.state.clutch = car.state.wHeld or car.state.sHeld or car.cruiseOn
  elseif name == "s" then
    car.state.sHeld = down
    car.state.reverse = car.state.reverseSelected or car.state.sHeld
    car.state.clutch = car.state.wHeld or car.state.sHeld or car.cruiseOn
  elseif name == "a" then
    car.state.aHeld = down
  elseif name == "d" then
    car.state.dHeld = down
  elseif fresh and name == "g" then
    car.state.frontDriveOff = not car.state.frontDriveOff
    car.markVehicleStateDirty()
  elseif fresh and name == "f" then
    car.state.driveEngineOff = not car.state.driveEngineOff
    car.engineOn = not car.state.driveEngineOff
    car.markVehicleStateDirty()
  elseif fresh and name == "l" then
    car.setLighting("headlights")
    return true
  elseif fresh and name == "z" then
    car.toggleIndicator("left")
    return true
  elseif fresh and name == "c" then
    car.toggleIndicator("right")
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
  car.state.aHeld = false
  car.state.dHeld = false
  car.state.clutch = car.cruiseOn
  car.state.reverse = car.state.reverseSelected
  car.releaseSuspension()
  car.applyOutputs()
end

function car.safeShutdown()
  car.autopilot.enabled = false
  car.autopilot.status = "OFF"
  car.state.mode = "standard"
  car.state.clutch = false
  car.state.reverse = false
  car.state.reverseSelected = false
  car.state.wHeld = false
  car.state.sHeld = false
  car.state.aHeld = false
  car.state.dHeld = false
  car.state.suspension = "neutral"
  car.state.frontDriveOff = false
  car.state.workshopEngineOff = true
  car.state.driveEngineOff = true
  car.state.workshopBoost = false
  car.state.lighting = "none"
  car.state.blink = false
  car.applyOutputs()
end

local function drawCrash(err)
  if car.writeHDError then pcall(car.writeHDError, err) end
  if car.drawHDError then pcall(car.drawHDError, err) end
  term.redirect(ui)
  local w, h = term.getSize()
  term.setBackgroundColor(themeColor(colors.black))
  term.setTextColor(themeColor(colors.white))
  term.clear()

  term.setCursorPos(1, 1)
  term.write(trim("RoadRover OS " .. VERSION .. " stopped", w))
  term.setTextColor(themeColor(colors.red))
  local message = tostring(err or "Unknown error"):gsub("\r", "")
  local row = 3
  for sourceLine in (message .. "\n"):gmatch("(.-)\n") do
    local offset = 1
    repeat
      term.setCursorPos(1, row)
      term.write(sourceLine:sub(offset, offset + w - 1))
      offset = offset + w
      row = row + 1
    until offset > #sourceLine or row > h
    if row > h then break end
  end

  if car.flushHD then car.flushHD() end

  if nativeTerm and nativeTerm ~= ui then
    term.redirect(nativeTerm)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    print("RoadRover OS stopped")
    term.setTextColor(colors.red)
    print(tostring(err or "Unknown error"))
    term.setTextColor(colors.lightGray)
    print("Log: roadrover-hd-error.log")
  end
end

local function main()
  car.scanDevices(true)
  if car.setupHD then car.setupHD(true) end
  rebuildUI()
  redraw()
  ensureProfile()
  car.state.workshopEngineOff = true
  car.state.driveEngineOff = true
  car.engineOn = false
  car.state.wHeld = false
  car.state.sHeld = false
  car.state.aHeld = false
  car.state.dHeld = false
  car.state.suspension = "neutral"
  car.state.clutch = car.cruiseOn
  car.markVehicleStateDirty()
  car.applyOutputs()
  car.flushVehicleState(true)
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
      tick()
      car.updateHardware()
      redraw()
      timer = os.startTimer(TICK)
    elseif ev == "timer" and car.pulseTimer and a == car.pulseTimer then
      car.stopPulse()

    elseif ev == "timer" and car.suspensionTimer and a == car.suspensionTimer then
      if car.releaseSuspension() then redraw() end

    elseif ev == "tm_monitor_touch" then
      local mx, my
      if car.hdToTermPoint then mx, my = car.hdToTermPoint(b, c) end
      local hasRelease = type(d) == "boolean"
      local pressed = hasRelease and d or true
      if mx and my and car.handleTouchEvent(mx, my, pressed, hasRelease) then redraw() end

    elseif ev == "tm_monitor_mouse_click" then
      local mx, my
      if car.hdToTermPoint then mx, my = car.hdToTermPoint(a, b, c, d) end
      if mx and my and car.handleTouchEvent(mx, my, true, false) then redraw() end

    elseif ev == "monitor_touch" then
      local mx, my = b, c
      if car.handleTouchEvent(mx, my, true, false) then redraw() end

    elseif ev == "mouse_click" then
      local mx, my = b, c
      if car.handleTouchEvent(mx, my, true, true) then redraw() end

    elseif ev == "mouse_up" then
      if car.handleTouchEvent(b, c, false, true) then redraw() end

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
      if car.setupHD then car.setupHD(true) end
      car.applyOutputs()
      rebuildUI()
      redraw()

    elseif ev == "term_resize" or ev == "monitor_resize" or ev == "tm_monitor_resize" then
      if car.setupHD then car.setupHD(true) end
      rebuildUI()
      redraw()
    end
  end
end

local ok, err = xpcall(main, debug and debug.traceback or function(e) return e end)
if not ok then car.safeShutdown(); drawCrash(err) end
