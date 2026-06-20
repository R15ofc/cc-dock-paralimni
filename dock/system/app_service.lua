local paths = require("dock.system.paths")
local safe_io = require("dock.system.safe_io")
local registry_module = require("dock.system.registry")

local M = {}
local required_fields = { "id", "name", "version", "entry", "type", "category", "icon", "permissions", "file_associations", "desktop" }

local function validate(manifest)
  if type(manifest) ~= "table" then return { ok = false, error = "manifest must be table", code = "INVALID_MANIFEST" } end
  for _, field in ipairs(required_fields) do
    if manifest[field] == nil then return { ok = false, error = "manifest missing field: " .. field, code = "INVALID_MANIFEST" } end
  end
  if type(manifest.permissions) ~= "table" then return { ok = false, error = "permissions must be table", code = "INVALID_PERMISSIONS" } end
  return { ok = true, data = manifest }
end

local function scan_base(service, base)
  if not fs.exists(base) or not fs.isDir(base) then return end
  for _, name in ipairs(fs.list(base)) do
    local dir = fs.combine(base, name)
    local manifest_path = fs.combine(dir, "app.json")
    if fs.isDir(dir) and fs.exists(manifest_path) then
      local read = safe_io.readJson(manifest_path, nil)
      if read.ok then
        service.registerApp(read.data, dir)
      elseif service.ctx.logger then
        service.ctx.logger.warn("invalid app manifest: " .. manifest_path .. ": " .. tostring(read.error), service.ctx.logger.file("apps.log"))
      end
    end
  end
end

function M.new(ctx)
  local service = { ctx = ctx, registry = registry_module.new() }

  function service.validateManifest(manifest) return validate(manifest) end

  function service.scanApps()
    service.registry = registry_module.new()
    scan_base(service, paths.system_apps)
    scan_base(service, paths.installed_apps)
    scan_base(service, paths.userFolder("default", "Apps"))
    return service.registry.list()
  end

  function service.registerApp(manifest, source_dir)
    local valid = validate(manifest)
    if not valid.ok then return valid end
    return service.registry.register(manifest, source_dir)
  end

  function service.unregisterApp(id) return service.registry.unregister(id) end
  function service.getApp(id) return service.registry.get(id) end

  function service.listApps() return service.registry.list() end

  function service.listAppsByCategory(category)
    local all = service.registry.list().data
    local out = {}
    for _, app in ipairs(all) do if app.manifest.category == category then table.insert(out, app) end end
    return { ok = true, data = out }
  end

  function service.listAppsForDesktop()
    local all = service.registry.list().data
    local out = {}
    for _, app in ipairs(all) do if app.manifest.desktop then table.insert(out, app) end end
    return { ok = true, data = out }
  end

  function service.resolveFileAssociation(file_type)
    for _, app in ipairs(service.registry.list().data) do
      for _, assoc in ipairs(app.manifest.file_associations or {}) do
        if assoc == file_type then return { ok = true, data = app.manifest } end
      end
    end
    return { ok = false, error = "no application for " .. tostring(file_type), code = "NO_ASSOCIATION" }
  end

  function service.launch(id, args)
    local app = service.getApp(id)
    if not app.ok then return app end
    local entry_path = fs.combine(app.data.source_dir, app.data.manifest.entry)
    if not fs.exists(entry_path) then return { ok = false, error = "entry missing: " .. entry_path, code = "ENTRY_MISSING" } end
    local loaded, module_or_error = pcall(dofile, entry_path)
    if not loaded then return { ok = false, error = tostring(module_or_error), code = "APP_LOAD_FAILED" } end
    local module = module_or_error
    if type(module) ~= "table" or type(module.run) ~= "function" then return { ok = false, error = "app must return table with run", code = "INVALID_APP" } end
    if ctx.event_bus then ctx.event_bus.emit("app_launched", { id = id }) end
    return ctx.process_manager.spawn(app.data.manifest.name, function()
      return module.run(ctx, args or {}, app.data.manifest)
    end, { app_id = id })
  end

  function service.openFile(path)
    return ctx.fs_service.openFile(path)
  end

  function service.installLocalApp(path)
    return ctx.package_service.installLocal(path)
  end

  function service.removeInstalledApp(id)
    return ctx.package_service.uninstall(id)
  end

  return service
end

return M
