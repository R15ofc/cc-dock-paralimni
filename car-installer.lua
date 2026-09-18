local SOURCE = "https://raw.githubusercontent.com/R15ofc/cc-dock-paralimni/main/car-os.lua"
local TARGET = "startup.lua"

local function fail(message)
  print("CarOS install failed: " .. tostring(message))
  return false
end

if not http then return fail("HTTP API disabled") end

print("Installing CarOS...")
local handle, err = http.get(SOURCE)
if not handle then return fail(err or "download failed") end
local data = handle.readAll() or ""
handle.close()

if data == "" then return fail("empty download") end
if fs.exists(TARGET) then fs.delete(TARGET) end
local out = fs.open(TARGET, "w")
if not out then return fail("cannot write " .. TARGET) end
out.write(data)
out.close()

print("CarOS installed as startup.lua")
print("Starting...")
shell.run(TARGET)
