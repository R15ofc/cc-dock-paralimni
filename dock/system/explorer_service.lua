local paths = require("dock.system.paths")

local M = {}

local function ok(data) return { ok = true, data = data } end
local function err(message, code) return { ok = false, error = tostring(message), code = code or "EXPLORER_ERROR" } end

local function normalize(path)
  return fs.combine("", tostring(path or ""))
end

local function is_dir(path)
  return fs.exists(path) and fs.isDir(path)
end

local function is_app_bundle(path)
  return fs.exists(path) and fs.isDir(path) and fs.getName(path):match("%.app$") and fs.exists(fs.combine(path, "app.json"))
end

local function app_display_name(path)
  local name = fs.getName(path)
  return name:gsub("%.app$", "")
end

local function unique_child_path(parent, wanted_name)
  local base = tostring(wanted_name or "Untitled")
  local candidate = fs.combine(parent, base)
  if not fs.exists(candidate) then return candidate end
  local stem, ext = base:match("^(.*)%.([^%.]+)$")
  if not stem then stem, ext = base, nil end
  local index = 2
  while true do
    local name = stem .. " " .. tostring(index) .. (ext and ("." .. ext) or "")
    candidate = fs.combine(parent, name)
    if not fs.exists(candidate) then return candidate end
    index = index + 1
  end
end

local function copy_item(ctx, source, target)
  if fs.isDir(source) then return ctx.fs_service.copy(source, target) end
  return ctx.safe_io.copyFile(source, target, ctx.safe_io.shouldCopyBinary(source))
end

local function trim(value)
  value = tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
  return value
end

local function sanitize_name(value)
  value = trim(value)
  value = value:gsub("[%z\1-\31]", "")
  value = value:gsub("[/\\:%*%?\"<>|]", "")
  value = value:gsub("^%.+$", "")
  value = value:gsub("%s+", " ")
  return value
end

local function split_editable_name(path)
  local name = fs.getName(path)
  if is_app_bundle(path) then return app_display_name(path), ".app" end
  if fs.isDir(path) then return name, "" end
  local base, extension = name:match("^(.*)(%.[^%.]+)$")
  if not base or base == "" then return name, "" end
  return base, extension
end

local function safe_rename_target(source, new_name)
  new_name = sanitize_name(new_name)
  if new_name == "" then return nil, "empty name" end
  local target = fs.combine(fs.getDir(source), new_name)
  if target ~= source and fs.exists(target) then return nil, "name already exists" end
  return target
end

function M.new(ctx)
  local service = { ctx = ctx, states = {}, clipboard = nil }

  local function default_path()
    return paths.userFolder("default", "Desktop")
  end

  local function new_state(id)
    return {
      id = id,
      path = fs.exists(default_path()) and default_path() or paths.userHome("default"),
      selected = nil,
      history = {},
      future = {},
      search = "",
      view = "list",
      scroll = 0,
      preview = nil,
      rename = nil,
    }
  end

  local function state(id)
    id = tostring(id or "main")
    service.states[id] = service.states[id] or new_state(id)
    if not is_dir(service.states[id].path) then service.states[id].path = default_path() end
    return service.states[id]
  end

  local function set_path(item, target, push_history)
    target = normalize(target)
    if not is_dir(target) then return err("directory not found: " .. target, "NOT_FOUND") end
    if push_history and item.path ~= target then table.insert(item.history, item.path) end
    item.path = target
    item.selected = nil
    item.preview = nil
    item.rename = nil
    item.future = push_history and {} or item.future
    item.scroll = 0
    return ok(item)
  end

  function service.state(id)
    return ok(state(id))
  end

  function service.sidebar()
    local folders = {
      { name = "Desktop", path = paths.userFolder("default", "Desktop") },
      { name = "Documents", path = paths.userFolder("default", "Documents") },
      { name = "Downloads", path = paths.userFolder("default", "Downloads") },
      { name = "Pictures", path = paths.userFolder("default", "Pictures") },
      { name = "Music", path = paths.userFolder("default", "Music") },
      { name = "Videos", path = paths.userFolder("default", "Videos") },
      { name = "Apps", path = paths.userFolder("default", "Apps") },
      { name = "Trash", path = paths.userFolder("default", "Trash") },
      { name = "System", path = paths.root },
    }
    return ok(folders)
  end

  function service.list(id)
    local item = state(id)
    local listed = ctx.fs_service.listDirectory(item.path)
    if not listed.ok then return listed end
    local search = tostring(item.search or ""):lower()
    local rows = {}
    for _, row in ipairs(listed.data or {}) do
      if search == "" or row.name:lower():find(search, 1, true) then
        if is_app_bundle(row.path) then
          row.display_name = app_display_name(row.path)
          row.bundle = "app"
        end
        row.type = ctx.fs_service.getFileType(row.path).data
        row.category = ctx.fs_service.getCategory(row.path).data
        row.selected = item.selected == row.path
        table.insert(rows, row)
      end
    end
    local selected_meta = nil
    if item.selected and fs.exists(item.selected) then
      selected_meta = {
        name = fs.getName(item.selected),
        display_name = is_app_bundle(item.selected) and app_display_name(item.selected) or fs.getName(item.selected),
        path = item.selected,
        dir = fs.isDir(item.selected),
        bundle = is_app_bundle(item.selected) and "app" or nil,
        size = fs.isDir(item.selected) and 0 or fs.getSize(item.selected),
        type = ctx.fs_service.getFileType(item.selected).data,
        preview = item.preview == item.selected,
      }
    end
    return ok({ state = item, rows = rows, sidebar = service.sidebar().data, clipboard = service.clipboard, selected = selected_meta, rename = item.rename })
  end

  function service.navigate(id, path)
    return set_path(state(id), path, true)
  end

  function service.back(id)
    local item = state(id)
    local previous = table.remove(item.history)
    if not previous then return ok(item) end
    table.insert(item.future, item.path)
    return set_path(item, previous, false)
  end

  function service.forward(id)
    local item = state(id)
    local next_path = table.remove(item.future)
    if not next_path then return ok(item) end
    table.insert(item.history, item.path)
    return set_path(item, next_path, false)
  end

  function service.up(id)
    local item = state(id)
    local parent = fs.getDir(item.path)
    if not parent or parent == "" or parent == item.path then return ok(item) end
    return set_path(item, parent, true)
  end

  function service.select(id, path)
    local item = state(id)
    path = normalize(path)
    if not fs.exists(path) then return err("path not found: " .. path, "NOT_FOUND") end
    if item.selected == path then
      if is_app_bundle(path) then
        local manifest = ctx.safe_io.readJson(fs.combine(path, "app.json"), nil)
        if manifest.ok and manifest.data and manifest.data.id then
          if ctx.app_service then ctx.app_service.scanApps() end
          if ctx.app_runtime_service and ctx.app_runtime_service.stateForApp then
            local state_for_app = ctx.app_runtime_service.stateForApp(manifest.data.id).data
            if not state_for_app.running then ctx.app_runtime_service.launch(manifest.data.id, {}) end
          end
          if ctx.window_service then ctx.window_service.open(manifest.data.id, { x = 46, y = 26, w = 220, h = 120 }) end
        end
        return ok(item)
      end
      if fs.isDir(path) then return service.navigate(id, path) end
      item.preview = path
      return ok(item)
    end
    item.selected = path
    item.preview = nil
    item.rename = nil
    return ok(item)
  end

  function service.openSelected(id)
    local item = state(id)
    if not item.selected then return err("nothing selected", "NO_SELECTION") end
    if fs.isDir(item.selected) then return service.navigate(id, item.selected) end
    item.preview = item.selected
    return ok(item)
  end

  function service.startRename(id)
    local item = state(id)
    if not item.selected or not fs.exists(item.selected) then return err("nothing selected", "NO_SELECTION") end
    local base, extension = split_editable_name(item.selected)
    item.rename = {
      path = item.selected,
      value = base,
      extension = extension,
      original = fs.getName(item.selected),
      dir = fs.isDir(item.selected),
    }
    return ok(item.rename)
  end

  function service.setRenameText(id, value)
    local item = state(id)
    if not item.rename then return err("rename not active", "RENAME_INACTIVE") end
    item.rename.value = sanitize_name(value)
    return ok(item.rename)
  end

  function service.appendRenameText(id, value)
    local item = state(id)
    if not item.rename then return err("rename not active", "RENAME_INACTIVE") end
    item.rename.value = sanitize_name(tostring(item.rename.value or "") .. tostring(value or ""))
    return ok(item.rename)
  end

  function service.backspaceRenameText(id)
    local item = state(id)
    if not item.rename then return err("rename not active", "RENAME_INACTIVE") end
    local value = tostring(item.rename.value or "")
    item.rename.value = value:sub(1, math.max(0, #value - 1))
    return ok(item.rename)
  end

  function service.cancelRename(id)
    local item = state(id)
    item.rename = nil
    return ok(item)
  end

  function service.commitRename(id)
    local item = state(id)
    if not item.rename then return err("rename not active", "RENAME_INACTIVE") end
    if not fs.exists(item.rename.path) then item.rename = nil; return err("path not found", "NOT_FOUND") end
    local value = sanitize_name(item.rename.value)
    local extension = item.rename.extension or ""
    if extension ~= "" and value:sub(-#extension):lower() == extension:lower() then
      value = sanitize_name(value:sub(1, #value - #extension))
    end
    if value == "" then value = item.rename.dir and "Untitled Folder" or "Untitled" end
    local new_name = value .. extension
    local target, rename_error = safe_rename_target(item.rename.path, new_name)
    if not target then return err(rename_error, "INVALID_NAME") end
    if target == item.rename.path then item.rename = nil; return ok(item.selected) end
    local renamed = ctx.fs_service.move(item.rename.path, target)
    if renamed.ok then
      item.selected = renamed.data
      item.rename = nil
    end
    return renamed
  end

  function service.setSearch(id, value)
    local item = state(id)
    item.search = tostring(value or "")
    item.scroll = 0
    return ok(item)
  end

  function service.scroll(id, delta)
    local item = state(id)
    item.scroll = math.max(0, (tonumber(item.scroll) or 0) + (tonumber(delta) or 0))
    return ok(item)
  end

  function service.appendSearch(id, value)
    local item = state(id)
    item.search = tostring(item.search or "") .. tostring(value or "")
    item.scroll = 0
    return ok(item)
  end

  function service.backspaceSearch(id)
    local item = state(id)
    item.search = tostring(item.search or "")
    item.search = item.search:sub(1, math.max(0, #item.search - 1))
    item.scroll = 0
    return ok(item)
  end

  function service.createFolder(id, name)
    local item = state(id)
    local target = unique_child_path(item.path, name or "New Folder")
    local created = ctx.fs_service.createDirectory(target)
    if created.ok then item.selected = target end
    return created
  end

  function service.createFile(id, name)
    local item = state(id)
    local target = unique_child_path(item.path, name or "New File.txt")
    local created = ctx.fs_service.createFile(target, "")
    if created.ok then item.selected = target end
    return created
  end

  function service.trashSelected(id)
    local item = state(id)
    if not item.selected then return err("nothing selected", "NO_SELECTION") end
    local moved = ctx.fs_service.moveToTrash(item.selected)
    if moved.ok then item.selected = nil; item.rename = nil end
    return moved
  end

  function service.copySelected(id)
    local item = state(id)
    if not item.selected then return err("nothing selected", "NO_SELECTION") end
    service.clipboard = { action = "copy", path = item.selected, name = fs.getName(item.selected) }
    return ok(service.clipboard)
  end

  function service.cutSelected(id)
    local item = state(id)
    if not item.selected then return err("nothing selected", "NO_SELECTION") end
    service.clipboard = { action = "cut", path = item.selected, name = fs.getName(item.selected) }
    return ok(service.clipboard)
  end

  function service.paste(id)
    local item = state(id)
    local clip = service.clipboard
    if not clip or not fs.exists(clip.path) then return err("clipboard empty", "EMPTY_CLIPBOARD") end
    local target = unique_child_path(item.path, clip.name)
    local result
    if clip.action == "cut" then result = ctx.fs_service.move(clip.path, target) else result = copy_item(ctx, clip.path, target) end
    if result.ok then
      item.selected = target
      if clip.action == "cut" then service.clipboard = nil end
    end
    return result
  end

  function service.renameSelected(id, name)
    local item = state(id)
    if not item.selected then return err("nothing selected", "NO_SELECTION") end
    local target, rename_error = safe_rename_target(item.selected, name or fs.getName(item.selected))
    if not target then return err(rename_error, "INVALID_NAME") end
    if target == item.selected then return ok(item.selected) end
    local renamed = ctx.fs_service.move(item.selected, target)
    if renamed.ok then item.selected = renamed.data; item.rename = nil end
    return renamed
  end

  function service.start()
    return ok(true)
  end

  return service
end

return M
