local paths = require("dock.system.paths")
local safe_io = require("dock.system.safe_io")
local logger = require("dock.system.logger")
local kernel = require("dock.system.kernel")

local M = {}
local current

local function ensure_boot_dirs()
  for _, dir in ipairs(paths.required_dirs) do
    safe_io.ensureDir(dir)
  end
end

function M.boot()
  ensure_boot_dirs()
  logger.init(paths.join(paths.logs, "boot.log"))
  logger.info("boot_started")
  local ctx = kernel.new()
  local init = kernel.initialize(ctx)
  if not init.ok then
    logger.error("boot failed: " .. tostring(init.error))
    return init
  end
  current = ctx
  if ctx.event_bus then ctx.event_bus.emit("boot_completed", {}) end
  logger.info("boot_completed")
  return { ok = true, data = ctx }
end

function M.context()
  if current then return current end
  local booted = M.boot()
  return booted.data
end

function M.start(options)
  local booted = M.boot()
  if not booted.ok then
    print("DockOS boot failed: " .. tostring(booted.error))
    return booted
  end
  if options and options.mode == "desktop" then
    return booted.data.shell_service.runDesktop()
  end
  return booted
end

function M.command(args)
  local ctx = M.context()
  return ctx.shell_service.runCommand(args or {})
end

return M
