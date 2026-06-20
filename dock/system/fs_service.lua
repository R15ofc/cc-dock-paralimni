local paths = require("dock.system.paths")
local safe_io = require("dock.system.safe_io")

local M = {}

local extension_types = {
  txt = "document/text", md = "document/text", log = "document/text",
  lua = "code/lua", json = "data/json",
  nfp = "image", nft = "image", png = "image",
}

local function ok(data) return { ok = true, data = data } end
local function err(message, code) return { ok = false, error = tostring(message), code = code or "FS_ERROR" } end

local function copy_recursive(source, target)
  if fs.isDir(source) then
    safe_io.ensureDir(target)
    for _, child in ipairs(fs.list(source)) do
      local copied = copy_recursive(fs.combine(source, child), fs.combine(target, child))
      if copied and not copied.ok then return copied end
    end
  else
    return safe_io.copyFile(source, target, safe_io.shouldCopyBinary(source))
  end
  return ok(target)
end

function M.new(ctx)
  local service = { ctx = ctx }

  function service.createFile(path, data)
    local result = safe_io.writeFile(path, data or "")
    if result.ok and ctx.event_bus then ctx.event_bus.emit("file_created", { path = path }) end
    return result
  end

  function service.readFile(path) return safe_io.readFile(path) end
  function service.writeFile(path, data) return service.createFile(path, data) end
  function service.appendFile(path, data) return safe_io.appendFile(path, data) end
  function service.createDirectory(path) return safe_io.ensureDir(path) end

  function service.listDirectory(path)
    if not fs.exists(path) then return err("path not found: " .. tostring(path), "NOT_FOUND") end
    if not fs.isDir(path) then return err("path is not a directory", "NOT_DIRECTORY") end
    local items = {}
    for _, name in ipairs(fs.list(path)) do
      local item_path = fs.combine(path, name)
      table.insert(items, { name = name, path = item_path, dir = fs.isDir(item_path), size = fs.isDir(item_path) and 0 or fs.getSize(item_path) })
    end
    table.sort(items, function(a, b)
      if a.dir ~= b.dir then return a.dir end
      return a.name:lower() < b.name:lower()
    end)
    return ok(items)
  end

  function service.copy(source, target) return copy_recursive(source, target) end

  function service.move(source, target)
    if not fs.exists(source) then return err("source not found", "NOT_FOUND") end
    safe_io.ensureParent(target)
    if fs.exists(target) then fs.delete(target) end
    local moved, move_err = pcall(fs.move, source, target)
    if not moved then return err(move_err, "MOVE_FAILED") end
    if ctx.event_bus then ctx.event_bus.emit("file_moved", { source = source, target = target }) end
    return ok(target)
  end

  function service.rename(source, name)
    return service.move(source, fs.combine(fs.getDir(source), name))
  end

  function service.delete(path)
    if not fs.exists(path) then return err("path not found", "NOT_FOUND") end
    fs.delete(path)
    if ctx.event_bus then ctx.event_bus.emit("file_deleted", { path = path }) end
    return ok(path)
  end

  function service.moveToTrash(path)
    if not fs.exists(path) then return err("path not found", "NOT_FOUND") end
    local trash = paths.userFolder("default", "Trash")
    safe_io.ensureDir(trash)
    local trash_id = tostring(os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)) .. "-" .. fs.getName(path)
    local target = fs.combine(trash, trash_id)
    local moved = service.move(path, target)
    if not moved.ok then return moved end
    local index_path = fs.combine(trash, ".trash-index.json")
    local index = safe_io.readJson(index_path, {}).data or {}
    index[trash_id] = { original = path, trash_path = target, deleted_at = os.clock() }
    safe_io.writeJson(index_path, index)
    return ok({ id = trash_id, path = target })
  end

  function service.restoreFromTrash(trash_id)
    local trash = paths.userFolder("default", "Trash")
    local index_path = fs.combine(trash, ".trash-index.json")
    local index = safe_io.readJson(index_path, {}).data or {}
    local item = index[trash_id]
    if not item then return err("trash item not found", "NOT_FOUND") end
    local restored = service.move(item.trash_path, item.original)
    if not restored.ok then return restored end
    index[trash_id] = nil
    safe_io.writeJson(index_path, index)
    return ok(item.original)
  end

  function service.permanentDelete(path) return service.delete(path) end
  function service.exists(path) return ok(fs.exists(path)) end
  function service.isDirectory(path) return ok(fs.exists(path) and fs.isDir(path)) end
  function service.getSize(path) return ok(fs.exists(path) and (fs.isDir(path) and 0 or fs.getSize(path)) or 0) end

  function service.getAttributes(path)
    if fs.attributes then
      local attr = fs.attributes(path)
      return ok(attr)
    end
    return ok({ size = fs.exists(path) and (fs.isDir(path) and 0 or fs.getSize(path)) or 0, isDir = fs.exists(path) and fs.isDir(path) or false })
  end

  function service.getFileType(path)
    if fs.isDir(path) and fs.getName(path):match("%.app$") and fs.exists(fs.combine(path, "app.json")) then return ok("application/bundle") end
    if fs.isDir(path) then return ok("folder") end
    if path:match("%.app%.json$") or fs.getName(path) == "app.json" then return ok("application/manifest") end
    if path:match("%.link%.json$") then return ok("desktop/shortcut") end
    local ext = fs.getName(path):match("%.([%w_%-]+)$")
    return ok(ext and extension_types[ext:lower()] or "unknown")
  end

  function service.getCategory(path)
    local home = paths.userHome("default")
    for category, folder in pairs(paths.user_folders) do
      local folder_path = fs.combine(home, folder)
      if path == folder_path or path:sub(1, #folder_path + 1) == folder_path .. "/" then
        return ok(category)
      end
    end
    local file_type = service.getFileType(path).data
    if file_type == "image" then return ok("Pictures") end
    if file_type == "document/text" then return ok("Documents") end
    if file_type == "code/lua" then return ok("System") end
    return ok("Unknown")
  end

  function service.searchByName(query, base)
    query = tostring(query or ""):lower()
    base = base or paths.userHome("default")
    local results = {}
    local function scan(path)
      if fs.getName(path):lower():find(query, 1, true) then table.insert(results, path) end
      if fs.isDir(path) then
        for _, child in ipairs(fs.list(path)) do scan(fs.combine(path, child)) end
      end
    end
    if fs.exists(base) then scan(base) end
    return ok(results)
  end

  function service.searchByCategory(category)
    local folder = paths.user_folders[category]
    if folder then return service.listDirectory(paths.userFolder("default", folder)) end
    return ok({})
  end

  function service.getUserFolders()
    local folders = {}
    for category, folder in pairs(paths.user_folders) do
      table.insert(folders, { category = category, path = paths.userFolder("default", folder) })
    end
    table.sort(folders, function(a, b) return a.category < b.category end)
    return ok(folders)
  end

  function service.createDesktopShortcut(name, target, icon)
    local shortcut = { type = "shortcut", name = name, target = target, icon = icon or "document", created_at = os.clock() }
    local path = fs.combine(paths.userFolder("default", "Desktop"), tostring(name):gsub("[^%w_%- ]", "_") .. ".link.json")
    return safe_io.writeJson(path, shortcut)
  end

  function service.resolveDesktopShortcut(path)
    local data = safe_io.readJson(path, nil)
    if not data.ok or type(data.data) ~= "table" or data.data.type ~= "shortcut" then return err("invalid shortcut", "INVALID_SHORTCUT") end
    return ok(data.data)
  end

  function service.openFile(path)
    if not ctx.app_service then return err("app service unavailable", "APP_SERVICE_UNAVAILABLE") end
    local file_type = service.getFileType(path).data
    local app = ctx.app_service.resolveFileAssociation(file_type)
    if not app.ok then return app end
    return ctx.app_service.launch(app.data.id, { path })
  end

  return service
end

return M
