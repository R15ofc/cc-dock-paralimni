local RELEASE = "b313872ac4d81f5a232ef0811a7c6224f434b046"
local RELEASE_BASE = "https://raw.githubusercontent.com/R15ofc/cc-dock-paralimni/" .. RELEASE .. "/"
local SOURCE = RELEASE_BASE .. "car-os.lua"
local HD_SOURCE = RELEASE_BASE .. "roadrover-hd.lua"
local TARGET = "startup.lua"
local TEMP = TARGET .. ".new"
local BACKUP = TARGET .. ".bak"
local HD_TARGET = "roadrover-hd.lua"
local HD_TEMP = HD_TARGET .. ".new"
local HD_BACKUP = HD_TARGET .. ".bak"
local VEHICLE_INFO = "VehicleInfo.json"

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

local data, download_error = download(SOURCE)
if not data then return fail(download_error) end
local hd_data, hd_download_error = download(HD_SOURCE)
if not hd_data then return fail(hd_download_error) end
if not write_temp(TEMP, data) then return fail("cannot write " .. TEMP) end
if not write_temp(HD_TEMP, hd_data) then return fail("cannot write " .. HD_TEMP) end

if fs.exists(BACKUP) then fs.delete(BACKUP) end
if fs.exists(HD_BACKUP) then fs.delete(HD_BACKUP) end
if fs.exists(TARGET) then fs.move(TARGET, BACKUP) end
if fs.exists(HD_TARGET) then fs.move(HD_TARGET, HD_BACKUP) end

local hd_moved, hd_move_error = pcall(fs.move, HD_TEMP, HD_TARGET)
local moved, move_error = false, nil
if hd_moved then moved, move_error = pcall(fs.move, TEMP, TARGET) end
if not hd_moved or not moved then
  if fs.exists(TARGET) then fs.delete(TARGET) end
  if fs.exists(HD_TARGET) then fs.delete(HD_TARGET) end
  if fs.exists(BACKUP) then fs.move(BACKUP, TARGET) end
  if fs.exists(HD_BACKUP) then fs.move(HD_BACKUP, HD_TARGET) end
  return fail(hd_move_error or move_error or "cannot replace RoadRover OS")
end
if fs.exists(BACKUP) then fs.delete(BACKUP) end
if fs.exists(HD_BACKUP) then fs.delete(HD_BACKUP) end

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
