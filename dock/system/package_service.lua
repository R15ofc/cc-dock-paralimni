local paths = require("dock.system.paths")
local safe_io = require("dock.system.safe_io")

local M = {}

local function copy_dir(source, target)
  safe_io.ensureDir(target)
  for _, name in ipairs(fs.list(source)) do
    local src = fs.combine(source, name)
    local dst = fs.combine(target, name)
    if fs.isDir(src) then
      local copied = copy_dir(src, dst)
      if copied and not copied.ok then return copied end
    else
      local copied = safe_io.copyFile(src, dst, safe_io.shouldCopyBinary(src))
      if not copied.ok then return copied end
    end
  end
  return { ok = true }
end

function M.new(ctx)
  local service = { ctx = ctx }

  function service.installLocal(path)
    if not fs.exists(path) or not fs.isDir(path) then return { ok = false, error = "package directory not found", code = "NOT_FOUND" } end
    local manifest_read = safe_io.readJson(fs.combine(path, "app.json"), nil)
    if not manifest_read.ok then return manifest_read end
    local valid = ctx.app_service.validateManifest(manifest_read.data)
    if not valid.ok then return valid end
    local target = fs.combine(paths.installed_apps, valid.data.id)
    if fs.exists(target) then fs.delete(target) end
    local copied = copy_dir(path, target)
    if not copied.ok then return copied end
    ctx.app_service.scanApps()
    if ctx.event_bus then ctx.event_bus.emit("app_installed", { id = valid.data.id }) end
    return { ok = true, data = valid.data }
  end

  function service.uninstall(id)
    local target = fs.combine(paths.installed_apps, id)
    if not fs.exists(target) then return { ok = false, error = "installed app not found", code = "NOT_FOUND" } end
    fs.delete(target)
    ctx.app_service.scanApps()
    if ctx.event_bus then ctx.event_bus.emit("app_removed", { id = id }) end
    return { ok = true }
  end

  function service.listInstalled()
    local items = {}
    if fs.exists(paths.installed_apps) then
      for _, name in ipairs(fs.list(paths.installed_apps)) do table.insert(items, name) end
    end
    table.sort(items)
    return { ok = true, data = items }
  end

  function service.updateMetadata(id, metadata)
    return safe_io.writeJson(fs.combine(paths.installed_apps, id, "metadata.json"), metadata or {})
  end

  return service
end

return M
