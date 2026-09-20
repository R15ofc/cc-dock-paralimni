local RELEASE = "c1a735828fcf64a9f56e7584c63d54e395d25ced"
local RELEASE_BASE = "https://raw.githubusercontent.com/R15ofc/cc-dock-paralimni/" .. RELEASE .. "/"
local TARGET = "startup.lua"
local VEHICLE_INFO = "VehicleInfo.json"
local FILES = {
  { source = "car-os.lua", target = TARGET },
  { source = "roadrover-hd.lua", target = "roadrover-hd.lua" },
  { source = "roadrover-music.lua", target = "roadrover-music.lua" },
  { source = "roadrover-font.lua", target = "roadrover-font.lua" },
  { source = "roadrover-bigfont.lua", target = "roadrover-bigfont.lua" }
}
local LEGACY_FILES = {
  "car-os.lua",
  "roadrover.lua",
  "rros.lua",
  "roadrover-hd-error.log"
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

local function remove_path(path)
  if not fs.exists(path) then return true end
  local ok = pcall(fs.delete, path)
  return ok and not fs.exists(path)
end

local function clear_user_caches()
  if not fs.exists("users") or not fs.isDir("users") then return true end
  local users = fs.list("users")
  for index = 1, #users do
    local root = fs.combine("users", users[index])
    if fs.isDir(root) and not remove_path(fs.combine(root, "caches")) then return false end
  end
  return true
end

local function is_transaction_file(name)
  for index = 1, #FILES do
    local target = FILES[index].target
    if name == target .. ".new" or name == target .. ".bak" then return true end
  end
  return false
end

local function wipe_old_os()
  for index = 1, #LEGACY_FILES do
    if not remove_path(LEGACY_FILES[index]) then return false end
  end
  local entries = fs.list("")
  for index = 1, #entries do
    local name = entries[index]
    local base = name:gsub("%.new$", ""):gsub("%.bak$", ""):gsub("%.tmp$", "")
    local managed = base:match("^roadrover[%-%_].*%.lua$") or base:match("^rros[%-%_].*%.lua$")
    if managed and not is_transaction_file(name) then
      if not remove_path(name) then return false end
    end
  end
  if not remove_path(fs.combine("system", "update")) then return false end
  if not clear_user_caches() then return false end
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

print("Removing old RoadRover OS files...")
if not wipe_old_os() then
  for index = 1, #FILES do
    local item = FILES[index]
    if fs.exists(item.target) then fs.delete(item.target) end
    if fs.exists(item.backup) then fs.move(item.backup, item.target) end
    if fs.exists(item.temp) then fs.delete(item.temp) end
  end
  return fail("cannot remove old OS files")
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
