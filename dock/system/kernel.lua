local version = require("dock.system.version")
local paths = require("dock.system.paths")
local safe_io = require("dock.system.safe_io")
local logger = require("dock.system.logger")
local event_bus = require("dock.system.event_bus")
local service_manager = require("dock.system.service_manager")
local process_manager = require("dock.system.process_manager")
local settings_service = require("dock.system.settings_service")
local user_service = require("dock.system.user_service")
local fs_service = require("dock.system.fs_service")
local app_service = require("dock.system.app_service")
local package_service = require("dock.system.package_service")
local device_service = require("dock.system.device_service")
local net_service = require("dock.system.net_service")
local notification_service = require("dock.system.notification_service")
local time_service = require("dock.system.time_service")
local ipc_service = require("dock.system.ipc_service")
local window_service = require("dock.system.window_service")
local permission_service = require("dock.system.permission_service")
local app_runtime_service = require("dock.system.app_runtime_service")
local shell_service = require("dock.system.shell_service")

local M = {}

local function seed_file(path, value)
  if not fs.exists(path) then
    safe_io.writeJson(path, value)
  end
end

function M.new()
  local ctx = { version = version, paths = paths, safe_io = safe_io }
  logger.init(paths.join(paths.logs, "system.log"))
  ctx.logger = logger
  ctx.event_bus = event_bus.new(logger)
  ctx.process_manager = process_manager.new(ctx)
  ctx.service_manager = service_manager.new(ctx)
  ctx.user_service = user_service.new(ctx)
  ctx.settings_service = settings_service.new(ctx)
  ctx.fs_service = fs_service.new(ctx)
  ctx.permission_service = permission_service.new(ctx)
  ctx.device_service = device_service.new(ctx)
  ctx.notification_service = notification_service.new(ctx)
  ctx.time_service = time_service.new(ctx)
  ctx.ipc_service = ipc_service.new(ctx)
  ctx.net_service = net_service.new(ctx)
  ctx.package_service = package_service.new(ctx)
  ctx.app_service = app_service.new(ctx)
  ctx.app_runtime_service = app_runtime_service.new(ctx)
  ctx.window_service = window_service.new(ctx)
  ctx.shell_service = shell_service.new(ctx)
  return ctx
end

function M.initialize(ctx)
  for _, dir in ipairs(paths.required_dirs) do
    safe_io.ensureDir(dir)
  end
  seed_file(paths.join(paths.etc, "system.json"), { theme = "paralimni", channel = version.channel })
  seed_file(paths.join(paths.etc, "users.json"), { current = "default", users = { { id = "default", name = "Default User", home = paths.userHome("default") } } })
  seed_file(paths.join(paths.etc, "apps.json"), { scanned_at = 0 })
  seed_file(paths.join(paths.etc, "services.json"), { autostart = { "devices", "notifications", "time", "ipc", "permissions", "app_runtime", "windows", "net" } })
  seed_file(paths.join(paths.etc, "mime.json"), { txt = "document/text", md = "document/text", lua = "code/lua", json = "data/json", png = "image" })
  seed_file(paths.join(paths.etc, "file_categories.json"), { "Desktop", "Documents", "Downloads", "Pictures", "Music", "Videos", "Apps", "System", "Trash", "Unknown" })
  seed_file(paths.join(paths.etc, "permissions.json"), { permissions = { "fs.read", "fs.write", "fs.delete", "network.rednet", "peripheral.access", "settings.read", "settings.write", "process.spawn", "ipc.message", "notification.send", "storage.app", "window.manage" } })
  ctx.user_service.ensureUserFolders()
  ctx.settings_service.load()
  ctx.permission_service.load()
  ctx.app_service.scanApps()
  ctx.time_service.load()
  ctx.service_manager.register("devices", ctx.device_service, { autostart = true })
  ctx.service_manager.register("notifications", ctx.notification_service, { autostart = true })
  ctx.service_manager.register("time", ctx.time_service, { autostart = true })
  ctx.service_manager.register("ipc", ctx.ipc_service, { autostart = true })
  ctx.service_manager.register("permissions", ctx.permission_service, { autostart = true })
  ctx.service_manager.register("app_runtime", ctx.app_runtime_service, { autostart = true })
  ctx.service_manager.register("windows", ctx.window_service, { autostart = true })
  ctx.service_manager.register("net", ctx.net_service, { autostart = false })
  ctx.service_manager.startAutostart()
  ctx.logger.info("kernel initialized")
  return { ok = true }
end

return M
