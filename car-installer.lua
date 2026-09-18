local RELEASE = "2f30055086e086a5f260a479fef90f42ed7d201d"
local RELEASE_BASE = "https://raw.githubusercontent.com/R15ofc/cc-dock-paralimni/" .. RELEASE .. "/"
local TARGET = "startup.lua"
local VEHICLE_INFO = "VehicleInfo.json"
local FILES = {
  { source = "car-os.lua", target = TARGET },
  { source = "roadrover-hd.lua", target = "roadrover-hd.lua" },
  { source = "roadrover-font.lua", target = "roadrover-font.lua" },
  { source = "roadrover-bigfont.lua", target = "roadrover-bigfont.lua" }
}

local function fail(message)
  print("RoadRover OS install failed: " .. tostring(message))
  return false
end

if not http then return fail("HTTP API disabled") end

print("Installing RoadRover OS...")
local cache_key = os.epoch and os.epoch("utc") or math.floor((os.clock and os.clock() or 0) * 1000)
local function download(url)
  local handle, err = http.get(url .. "?v=" .. tostring(cache_key))
  if not handle then return nil, err or "download failed" end
  local data = handle.readAll() or ""
  handle.close()
  if data == "" then return nil, "empty download" end
  return data
end

local function write_temp(path, data)
  if fs.exists(path) then fs.delete(path) end
  local out = fs.open(path, "w")
  if not out then return false end
  out.write(data)
  out.close()
  return true
end

for index = 1, #FILES do
  local item = FILES[index]
  item.temp = item.target .. ".new"
  item.backup = item.target .. ".bak"
  local data, downloadError = download(RELEASE_BASE .. item.source)
  if not data then return fail(item.source .. ": " .. tostring(downloadError)) end
  if not write_temp(item.temp, data) then return fail("cannot write " .. item.temp) end
end

for index = 1, #FILES do
  local item = FILES[index]
  if fs.exists(item.backup) then fs.delete(item.backup) end
  if fs.exists(item.target) then fs.move(item.target, item.backup) end
end

local installed, installError = true, nil
for index = 1, #FILES do
  local item = FILES[index]
  local moved, moveError = pcall(fs.move, item.temp, item.target)
  if not moved then installed, installError = false, moveError; break end
end

if not installed then
  for index = 1, #FILES do
    local item = FILES[index]
    if fs.exists(item.target) then fs.delete(item.target) end
    if fs.exists(item.backup) then fs.move(item.backup, item.target) end
    if fs.exists(item.temp) then fs.delete(item.temp) end
  end
  return fail(installError or "cannot replace RoadRover OS")
end

for index = 1, #FILES do
  local item = FILES[index]
  if fs.exists(item.backup) then fs.delete(item.backup) end
end

if not fs.exists(VEHICLE_INFO) then
  local info = fs.open(VEHICLE_INFO, "w")
  if info then
    info.write('{"model":"RoadRover","generation":"1","engineType":"Diesel","sedan":false,"portHeading":"east"}')
    info.close()
  end
end

print("RoadRover OS installed as startup.lua")
print("Starting...")
shell.run(TARGET)
