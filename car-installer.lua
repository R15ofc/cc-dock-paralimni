local SOURCE = "https://raw.githubusercontent.com/R15ofc/cc-dock-paralimni/main/car-os.lua"
local TARGET = "startup.lua"
local TEMP = TARGET .. ".new"
local BACKUP = TARGET .. ".bak"
local VEHICLE_INFO = "VehicleInfo.json"

local function fail(message)
  print("RoadRover OS install failed: " .. tostring(message))
  return false
end

if not http then return fail("HTTP API disabled") end

print("Installing RoadRover OS...")
local cache_key = os.epoch and os.epoch("utc") or math.floor((os.clock and os.clock() or 0) * 1000)
local handle, err = http.get(SOURCE .. "?v=" .. tostring(cache_key))
if not handle then return fail(err or "download failed") end
local data = handle.readAll() or ""
handle.close()

if data == "" then return fail("empty download") end
if fs.exists(TEMP) then fs.delete(TEMP) end
local out = fs.open(TEMP, "w")
if not out then return fail("cannot write " .. TEMP) end
out.write(data)
out.close()

if fs.exists(BACKUP) then fs.delete(BACKUP) end
if fs.exists(TARGET) then fs.move(TARGET, BACKUP) end
local moved, move_error = pcall(fs.move, TEMP, TARGET)
if not moved then
  if fs.exists(BACKUP) then fs.move(BACKUP, TARGET) end
  return fail(move_error or "cannot replace " .. TARGET)
end
if fs.exists(BACKUP) then fs.delete(BACKUP) end

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
