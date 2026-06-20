local paths = require("dock.system.paths")

local M = {}

local function ok(data) return { ok = true, data = data } end
local function err(message, code) return { ok = false, error = tostring(message), code = code or "STUDIO_ERROR" } end

local function safe_id(value)
  value = tostring(value or "my_app"):lower():gsub("[^%w_%-%.]", "_")
  value = value:gsub("^_+", ""):gsub("_+$", "")
  if value == "" then value = "my_app" end
  if not value:find("%.", 1, true) then value = "user." .. value end
  return value
end

local function escape_lua(value)
  return string.format("%q", tostring(value or ""))
end

local function encode_manifest(project)
  local permissions = {}
  for _, permission in ipairs(project.permissions or {}) do table.insert(permissions, '"' .. permission .. '"') end
  return "{\n" ..
    '  "id": "' .. project.id .. '",\n' ..
    '  "name": "' .. project.name .. '",\n' ..
    '  "version": "' .. (project.version or "0.0.1") .. '",\n' ..
    '  "entry": "main.lua",\n' ..
    '  "type": "user",\n' ..
    '  "category": "created",\n' ..
    '  "icon": "' .. (project.icon or "app") .. '",\n' ..
    '  "permissions": [' .. table.concat(permissions, ", ") .. '],\n' ..
    '  "file_associations": [],\n' ..
    '  "autoload": false,\n' ..
    '  "desktop": true\n' ..
    "}\n"
end

local function render_main(project)
  local lines = {
    "return {",
    "  run = function(ctx)",
    "    print(" .. escape_lua(project.name) .. ")",
  }
  for _, component in ipairs(project.components or {}) do
    if component.kind == "text" then
      table.insert(lines, "    print(" .. escape_lua(component.text or "Text") .. ")")
    elseif component.kind == "input" then
      table.insert(lines, "    print(" .. escape_lua((component.label or "Input") .. ": <input>") .. ")")
    elseif component.kind == "button" then
      table.insert(lines, "    print(" .. escape_lua("[Button] " .. (component.label or "Button")) .. ")")
    elseif component.kind == "shape" then
      table.insert(lines, "    print(" .. escape_lua("[Shape] " .. (component.label or "Box")) .. ")")
    end
  end
  table.insert(lines, "    return { ok = true }")
  table.insert(lines, "  end,")
  table.insert(lines, "}")
  return table.concat(lines, "\n") .. "\n"
end

function M.new(ctx)
  local service = { ctx = ctx, project = nil }
  local projects_dir = paths.join(paths.userFolder("default", "Apps"), "StudioProjects")

  local function ensure()
    if not fs.exists(projects_dir) then fs.makeDir(projects_dir) end
  end

  local function default_project()
    return {
      id = "user.paralimni_app",
      name = "Paralimni App",
      version = "0.0.1",
      icon = "app",
      permissions = { "fs.read" },
      components = {
        { kind = "text", text = "Hello from DockOS", x = 12, y = 12, w = 92, h = 14 },
        { kind = "button", label = "Action", x = 12, y = 34, w = 62, h = 16 },
      },
      code = "-- App Studio project\n",
      selected = 1,
      dirty = false,
    }
  end

  function service.current()
    if not service.project then service.project = default_project() end
    return ok(service.project)
  end

  function service.newProject(name)
    service.project = default_project()
    if name and name ~= "" then
      service.project.name = tostring(name)
      service.project.id = safe_id(name)
    end
    service.project.dirty = true
    return ok(service.project)
  end

  function service.addComponent(kind)
    local project = service.current().data
    kind = tostring(kind or "text")
    local component = { kind = kind, x = 16 + (#project.components * 6), y = 16 + (#project.components * 5), w = 70, h = 16 }
    if kind == "text" then component.text = "Text"
    elseif kind == "input" then component.label = "Text Input"
    elseif kind == "image" then component.label = "Image"
    elseif kind == "shape" then component.label = "Shape"
    else component.label = "Button"; component.kind = "button" end
    table.insert(project.components, component)
    project.selected = #project.components
    project.dirty = true
    return ok(component)
  end

  function service.setName(name)
    local project = service.current().data
    project.name = tostring(name or project.name)
    project.id = safe_id(project.name)
    project.dirty = true
    return ok(project)
  end

  function service.setCode(code)
    local project = service.current().data
    project.code = tostring(code or "")
    project.dirty = true
    return ok(project)
  end

  function service.save()
    ensure()
    local project = service.current().data
    local path = paths.join(projects_dir, project.id .. ".json")
    project.dirty = false
    return ctx.safe_io.writeJson(path, project)
  end

  function service.exportApp()
    local project = service.current().data
    local target = paths.join(paths.userFolder("default", "Apps"), project.id)
    if fs.exists(target) then fs.delete(target) end
    fs.makeDir(target)
    local manifest = ctx.safe_io.writeFile(paths.join(target, "app.json"), encode_manifest(project))
    if not manifest.ok then return manifest end
    local main = ctx.safe_io.writeFile(paths.join(target, "main.lua"), render_main(project))
    if not main.ok then return main end
    ctx.app_service.scanApps()
    project.dirty = false
    return ok({ path = target, manifest = paths.join(target, "app.json") })
  end

  function service.preview()
    local project = service.current().data
    return ok({ title = project.name, components = project.components })
  end

  function service.start() return ok(true) end

  return service
end

return M
