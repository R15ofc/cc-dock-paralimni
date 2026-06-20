local DEFAULT_SOURCE_URL = "https://raw.githubusercontent.com/R15ofc/cc-dock-paralimni/main"
local FILES = {
  "startup.lua", "dock.lua", "bin/dock.lua",
  "dock/system/version.lua", "dock/system/paths.lua", "dock/system/json.lua", "dock/system/safe_io.lua",
  "dock/system/logger.lua", "dock/system/event_bus.lua", "dock/system/service_manager.lua", "dock/system/process_manager.lua",
  "dock/system/settings_service.lua", "dock/system/user_service.lua", "dock/system/fs_service.lua", "dock/system/registry.lua",
  "dock/system/app_service.lua", "dock/system/package_service.lua", "dock/system/device_service.lua", "dock/system/tom_adapter.lua",
  "dock/system/net_service.lua", "dock/system/notification_service.lua", "dock/system/time_service.lua", "dock/system/ipc_service.lua",
  "dock/system/window_service.lua", "dock/system/permission_service.lua", "dock/system/app_runtime_service.lua",
  "dock/system/explorer_service.lua", "dock/system/cursor_service.lua", "dock/system/text_input_service.lua", "dock/system/menu_service.lua",
  "dock/system/studio_service.lua", "dock/system/loading.lua", "dock/system/scrollbar.lua", "dock/system/splash.lua", "dock/system/update_service.lua",
  "dock/system/shell_service.lua", "dock/system/kernel.lua", "dock/system/boot.lua",
  "dock/apps/system/files/app.json", "dock/apps/system/files/main.lua",
  "dock/apps/system/terminal/app.json", "dock/apps/system/terminal/main.lua",
  "dock/apps/system/settings/app.json", "dock/apps/system/settings/main.lua",
  "dock/apps/system/studio/app.json", "dock/apps/system/studio/main.lua",
  "dock/tests/selftest.lua",
  "dock/assets/wallpaper-128x64.png",
  "dock/assets/wallpaper-256x96.png",
  "dock/assets/wallpaper-256x128.png",
  "dock/assets/wallpaper-380x192.png",
  "dock/assets/wallpaper-382x192.png",
  "dock/assets/wallpaper-384x192.png",
  "dock/assets/wallpaper-512x256.png",
  "dock/assets/dock-glass-128x64.png",
  "dock/assets/dock-glass-256x96.png",
  "dock/assets/dock-glass-256x128.png",
  "dock/assets/dock-glass-380x192.png",
  "dock/assets/dock-glass-382x192.png",
  "dock/assets/dock-glass-384x192.png",
  "dock/assets/dock-glass-512x256.png"
}

local function combine(a, b) return fs.combine(a, b) end
local function ensureParent(path)
  local dir = fs.getDir(path)
  if dir and dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
end
local function download(source, file)
  local url = source .. "/" .. file
  local binary = file:match("%.png$") ~= nil
  local handle, err = http.get(url, nil, binary)
  if not handle then return false, err or ("request failed: " .. url) end
  ensureParent(file)
  local out = fs.open(file, binary and "wb" or "w") or fs.open(file, "w")
  if not out then handle.close(); return false, "cannot write " .. file end
  if binary then
    while true do
      local chunk = handle.read(8192)
      if chunk == nil then break end
      out.write(chunk)
    end
  else
    out.write(handle.readAll() or "")
  end
  out.close(); handle.close(); return true
end

local source = ({ ... })[1] or DEFAULT_SOURCE_URL
print("DockOS Paralimni Installer")
for index, file in ipairs(FILES) do
  print("Installing " .. tostring(index) .. "/" .. tostring(#FILES) .. " " .. file)
  local ok, err = download(source, file)
  if not ok then print("Install failed: " .. tostring(err)); return end
end
print("DockOS Paralimni installed")
print("Run: dock")
