local paths = require("dock.system.paths")

local M = {}

local function ok(data) return { ok = true, data = data } end
local function err(message, code) return { ok = false, error = tostring(message), code = code or "STUDIO_ERROR" } end

local function safe_id(value)
  value = tostring(value or "my_app"):lower():gsub("[^%w_%-%.]", "_")
  value = value:gsub("^_+", ""):gsub("_+$", "")
  if value == "" then value = "my_app" end
  if not value:find(".", 1, true) then value = "user." .. value end
  return value
end

local function safe_file_name(value)
  value = tostring(value or "Paralimni App"):gsub("[/\\:%*%?\"<>|]", "")
  value = value:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
  if value == "" then value = "Paralimni App" end
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
    '  "icon": "' .. (project.icon or "placeholder") .. '",\n' ..
    '  "permissions": [' .. table.concat(permissions, ", ") .. '],\n' ..
    '  "file_associations": [],\n' ..
    '  "autoload": false,\n' ..
    '  "desktop": true\n' ..
    "}\n"
end

local function line_value(script, key, default)
  local escaped = key:gsub("%.", "%%.")
  local value = tostring(script or ""):match("\n?%s*" .. escaped .. "%s*=%s*\"([^\"]*)\"")
  if value ~= nil then return value end
  value = tostring(script or ""):match("\n?%s*" .. escaped .. "%s*=%s*([^\n]+)")
  if value ~= nil then return value:gsub("^%s+", ""):gsub("%s+$", "") end
  return default
end

local function script_lines(script)
  local lines = {}
  script = tostring(script or "")
  for line in (script .. "\n"):gmatch("(.-)\n") do table.insert(lines, line) end
  if #lines == 0 then table.insert(lines, "") end
  return lines
end

local function bool_value(script, key, default)
  local value = line_value(script, key, nil)
  if value == nil then return default end
  value = tostring(value):lower()
  return value == "true" or value == "yes" or value == "on" or value == "1"
end

local function number_pair(value, default_w, default_h)
  local w, h = tostring(value or ""):match("(%d+)%s*x%s*(%d+)")
  return tonumber(w) or default_w, tonumber(h) or default_h
end

local function clamp_component(project, component)
  local window = project.window or { w = 220, h = 120 }
  local window_w = math.max(80, tonumber(window.w) or 220)
  local window_h = math.max(60, tonumber(window.h) or 120)
  local max_w = math.max(12, window_w - 2)
  local max_h = math.max(8, window_h - 24)
  component.w = math.max(12, math.min(max_w, math.floor(tonumber(component.w) or 60)))
  component.h = math.max(8, math.min(max_h, math.floor(tonumber(component.h) or 16)))
  component.x = math.max(1, math.min(math.max(1, window_w - component.w - 1), math.floor(tonumber(component.x) or 1)))
  component.y = math.max(1, math.min(math.max(1, window_h - 22 - component.h), math.floor(tonumber(component.y) or 1)))
  return component
end

local function normalize_layout(project)
  local window = project.window or { w = 220, h = 120, titlebar = true }
  window.w = math.max(80, math.min(640, math.floor(tonumber(window.w) or 220)))
  window.h = math.max(60, math.min(360, math.floor(tonumber(window.h) or 120)))
  project.window = window
  for _, component in ipairs(project.components or {}) do clamp_component(project, component) end
  project.selected = math.min(math.max(1, tonumber(project.selected) or 1), math.max(1, #(project.components or {})))
  return project
end

local function parse_components(script)
  local components = {}
  local seen_ui = false
  for line in tostring(script or ""):gmatch("[^\n]+") do
    local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
    if trimmed:match("^ui%.") then seen_ui = true end
    local id, x, y, text = trimmed:match('^ui%.text%(%s*"([^"]+)"%s*,%s*(-?%d+)%s*,%s*(-?%d+)%s*,%s*"([^"]*)"')
    if id then
      table.insert(components, { id = id, kind = "text", text = text, x = tonumber(x), y = tonumber(y), w = math.max(42, #text * 6), h = 14 })
    else
      local label
      id, x, y, w, h, label = trimmed:match('^ui%.button%(%s*"([^"]+)"%s*,%s*(-?%d+)%s*,%s*(-?%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,%s*"([^"]*)"')
      if id then
        local action = trimmed:match('on_click%s*=%s*"([^"]+)"') or "notify"
        table.insert(components, { id = id, kind = "button", label = label, action = action, message = label, x = tonumber(x), y = tonumber(y), w = tonumber(w), h = tonumber(h) })
      else
        id, x, y, w, h, label = trimmed:match('^ui%.input%(%s*"([^"]+)"%s*,%s*(-?%d+)%s*,%s*(-?%d+)%s*,%s*(%d+)%s*,%s*(%d+)%s*,%s*"([^"]*)"')
        if id then
          table.insert(components, { id = id, kind = "input", label = label, x = tonumber(x), y = tonumber(y), w = tonumber(w), h = tonumber(h) })
        else
          id, x, y, w, h = trimmed:match('^ui%.shape%(%s*"([^"]+)"%s*,%s*(-?%d+)%s*,%s*(-?%d+)%s*,%s*(%d+)%s*,%s*(%d+)')
          if id then
            table.insert(components, { id = id, kind = "shape", label = id, color = trimmed:match('color%s*=%s*"([^"]+)"') or "blue", x = tonumber(x), y = tonumber(y), w = tonumber(w), h = tonumber(h) })
          else
            id, x, y, w, h = trimmed:match('^ui%.image%(%s*"([^"]+)"%s*,%s*(-?%d+)%s*,%s*(-?%d+)%s*,%s*(%d+)%s*,%s*(%d+)')
            if id then
              local source = trimmed:match('source%s*=%s*"([^"]+)"') or "placeholder"
              table.insert(components, { id = id, kind = "image", label = source, source = source, x = tonumber(x), y = tonumber(y), w = tonumber(w), h = tonumber(h) })
            end
          end
        end
      end
    end
  end
  if seen_ui then return components end
  return nil
end

local function component_script_line(component, index)
  local id = component.id or (component.kind or "node") .. tostring(index)
  if component.kind == "text" then
    return "ui.text(" .. escape_lua(id) .. ", " .. tostring(component.x or 1) .. ", " .. tostring(component.y or 1) .. ", " .. escape_lua(component.text or "Text") .. ")"
  elseif component.kind == "button" then
    return "ui.button(" .. escape_lua(id) .. ", " .. tostring(component.x or 1) .. ", " .. tostring(component.y or 1) .. ", " .. tostring(component.w or 64) .. ", " .. tostring(component.h or 16) .. ", " .. escape_lua(component.label or "Button") .. ", on_click=" .. escape_lua(component.action or "notify") .. ")"
  elseif component.kind == "input" then
    return "ui.input(" .. escape_lua(id) .. ", " .. tostring(component.x or 1) .. ", " .. tostring(component.y or 1) .. ", " .. tostring(component.w or 86) .. ", " .. tostring(component.h or 16) .. ", " .. escape_lua(component.label or "Text Input") .. ")"
  elseif component.kind == "shape" then
    return "ui.shape(" .. escape_lua(id) .. ", " .. tostring(component.x or 1) .. ", " .. tostring(component.y or 1) .. ", " .. tostring(component.w or 72) .. ", " .. tostring(component.h or 38) .. ", color=" .. escape_lua(component.color or "blue") .. ")"
  elseif component.kind == "image" then
    return "ui.image(" .. escape_lua(id) .. ", " .. tostring(component.x or 1) .. ", " .. tostring(component.y or 1) .. ", " .. tostring(component.w or 54) .. ", " .. tostring(component.h or 34) .. ", source=" .. escape_lua(component.source or component.label or "placeholder") .. ")"
  end
  return "ui.button(" .. escape_lua(id) .. ", " .. tostring(component.x or 1) .. ", " .. tostring(component.y or 1) .. ", " .. tostring(component.w or 64) .. ", " .. tostring(component.h or 16) .. ", " .. escape_lua(component.label or "Button") .. ", on_click=\"notify\")"
end

local function dockscript(project)
  local window = project.window or { w = 220, h = 120 }
  local lines = {
    "app.name = " .. escape_lua(project.name),
    "app.id = " .. escape_lua(project.id),
    "app.icon = " .. escape_lua(project.icon or "placeholder"),
    "window.size = " .. tostring(window.w or 220) .. "x" .. tostring(window.h or 120),
    "window.titlebar = true",
    "",
    "def on_start():",
    "    notify(app.name, \"Ready\")",
    "",
    "def on_click(id):",
    "    if id == \"notify\":",
    "        notify(app.name, \"Button pressed\")",
  }
  for index, component in ipairs(project.components or {}) do table.insert(lines, component_script_line(component, index)) end
  return table.concat(lines, "\n") .. "\n"
end

local function apply_script(project, script)
  project.script = tostring(script or project.script or "")
  project.name = line_value(project.script, "app.name", project.name)
  project.id = safe_id(line_value(project.script, "app.id", project.id))
  project.icon = line_value(project.script, "app.icon", project.icon or "placeholder")
  local width, height = number_pair(line_value(project.script, "window.size", nil), project.window and project.window.w or 220, project.window and project.window.h or 120)
  project.window = { w = width, h = height, titlebar = bool_value(project.script, "window.titlebar", true) }
  local parsed = parse_components(project.script)
  if parsed then
    project.components = parsed
    project.selected = math.min(math.max(1, tonumber(project.selected) or 1), math.max(1, #project.components))
  end
  normalize_layout(project)
  return project
end

local function lua_component(component)
  local entries = {}
  for key, value in pairs(component or {}) do
    if type(value) == "string" then table.insert(entries, key .. " = " .. escape_lua(value))
    elseif type(value) == "number" or type(value) == "boolean" then table.insert(entries, key .. " = " .. tostring(value)) end
  end
  table.sort(entries)
  return "{ " .. table.concat(entries, ", ") .. " }"
end

local function render_main(project)
  apply_script(project, project.script)
  local component_lines = {}
  for _, component in ipairs(project.components or {}) do table.insert(component_lines, "      " .. lua_component(component) .. ",") end
  local lines = {
    "return {",
    "  run = function(ctx)",
    "    local app_name = " .. escape_lua(project.name),
    "    local components = {",
    table.concat(component_lines, "\n"),
    "    }",
    "    ctx.ui.menu.set({",
    "      { id = \"app.about\", label = \"About\" },",
    "      { id = \"app.reload\", label = \"Reload\" },",
    "    })",
    "    ctx.notification.send(app_name, \"Application started\")",
    "    while true do",
    "      local event, payload = coroutine.yield(\"*\")",
    "      if event == \"dock_app_event\" and type(payload) == \"table\" and payload.app_id == ctx.app.id then",
    "        if payload.kind == \"button\" then",
    "          local message = payload.message or \"Button pressed\"",
    "          ctx.storage.set(\"last_button\", payload.id or payload.index or \"button\")",
    "          ctx.notification.send(app_name, message)",
    "        end",
    "      elseif event == \"terminate\" then",
    "        break",
    "      end",
    "    end",
    "    return { ok = true, data = components }",
    "  end,",
    "}",
  }
  return table.concat(lines, "\n") .. "\n"
end

function M.new(ctx)
  local service = { ctx = ctx, project = nil }
  local projects_dir = paths.join(paths.userFolder("default", "Apps"), "StudioProjects")

  local function ensure()
    if not fs.exists(projects_dir) then fs.makeDir(projects_dir) end
  end

  local function refresh(project)
    normalize_layout(project)
    project.script = dockscript(project)
    project.code = project.script
    return project
  end

  local function sync_component_line(project, index)
    local component = project.components and project.components[index]
    if not component then return project end
    local replacement = component_script_line(component, index)
    local lines = script_lines(project.script)
    local target = 'ui%.' .. tostring(component.kind or "button") .. '%(%s*"' .. tostring(component.id or ""):gsub("([^%w])", "%%%1") .. '"'
    local replaced = false
    for line_index, line in ipairs(lines) do
      if tostring(line):match(target) then
        lines[line_index] = replacement
        replaced = true
        break
      end
    end
    if not replaced then
      table.insert(lines, "")
      table.insert(lines, replacement)
    end
    project.script = table.concat(lines, "\n") .. "\n"
    project.code = project.script
    apply_script(project, project.script)
    return project
  end

  local function sync_assignment_line(project, key, value)
    local lines = script_lines(project.script)
    local escaped = tostring(key):gsub("%.", "%%.")
    local replacement = tostring(key) .. " = " .. escape_lua(value)
    local replaced = false
    for line_index, line in ipairs(lines) do
      if tostring(line):match("^%s*" .. escaped .. "%s*=") then
        lines[line_index] = replacement
        replaced = true
        break
      end
    end
    if not replaced then table.insert(lines, 1, replacement) end
    project.script = table.concat(lines, "\n") .. "\n"
    project.code = project.script
    return project
  end

  local function default_project()
    local project = {
      id = "user.paralimni_app",
      name = "Paralimni App",
      version = "0.0.1",
      icon = "placeholder",
      permissions = { "fs.read", "notification.send", "settings.read", "settings.write", "storage.app" },
      window = { w = 220, h = 120, titlebar = true },
      preview_scroll_x = 0,
      preview_scroll_y = 0,
      code_scroll = 0,
      mode = "design",
      tool = "move",
      insert_kind = "button",
      components = {
        { id = "title", kind = "text", text = "Hello from DockOS", x = 12, y = 12, w = 92, h = 14 },
        { id = "notify", kind = "button", label = "Notify", action = "notify", message = "Hello from App Studio", x = 12, y = 34, w = 62, h = 16 },
      },
      selected = 1,
      dirty = false,
    }
    return refresh(project)
  end

  function service.current()
    if not service.project then service.project = default_project() end
    service.project.mode = service.project.mode or "design"
    service.project.tool = service.project.tool or "move"
    service.project.insert_kind = service.project.insert_kind or "button"
    return ok(service.project)
  end

  function service.newProject(name)
    service.project = default_project()
    if name and name ~= "" then
      service.project.name = tostring(name)
      service.project.id = safe_id(name)
    end
    service.project.dirty = true
    return ok(refresh(service.project))
  end

  function service.setMode(mode)
    local project = service.current().data
    mode = tostring(mode or "design")
    if mode ~= "script" and mode ~= "design" and mode ~= "preview" then mode = "design" end
    project.mode = mode
    return ok(project)
  end

  function service.setTool(tool, insert_kind)
    local project = service.current().data
    tool = tostring(tool or "move")
    if tool ~= "move" and tool ~= "add" then tool = "move" end
    project.tool = tool
    if insert_kind then project.insert_kind = tostring(insert_kind) end
    return ok(project)
  end

  function service.addComponent(kind, x, y)
    local project = service.current().data
    kind = tostring(kind or "text")
    local index = #(project.components or {}) + 1
    local component = {
      id = kind .. tostring(index),
      kind = kind,
      x = math.floor(tonumber(x) or (16 + (#project.components * 6))),
      y = math.floor(tonumber(y) or (16 + (#project.components * 5))),
      w = 70,
      h = 16,
    }
    if kind == "text" then component.text = "Text"
    elseif kind == "input" then component.label = "Text Input"; component.w = 86
    elseif kind == "image" then component.label = "Image"; component.source = "placeholder"; component.w = 54; component.h = 34
    elseif kind == "shape" then component.label = "Shape"; component.color = "blue"; component.w = 72; component.h = 38
    else component.label = "Button"; component.action = "notify"; component.message = "Button pressed"; component.kind = "button" end
    clamp_component(project, component)
    table.insert(project.components, component)
    project.selected = #project.components
    project.dirty = true
    return ok(sync_component_line(project, project.selected))
  end

  function service.selectComponent(index)
    local project = service.current().data
    index = tonumber(index)
    if not index or not project.components[index] then return err("component not found", "NOT_FOUND") end
    project.selected = index
    return ok(project.components[index])
  end

  function service.moveComponent(index, x, y)
    local project = service.current().data
    index = tonumber(index)
    local component = index and project.components[index]
    if not component then return err("component not found", "NOT_FOUND") end
    component.x = math.floor(tonumber(x) or component.x or 1)
    component.y = math.floor(tonumber(y) or component.y or 1)
    clamp_component(project, component)
    project.selected = index
    project.dirty = true
    return ok(sync_component_line(project, index))
  end

  function service.resizeComponent(index, dw, dh)
    local project = service.current().data
    local component = project.components[tonumber(index) or -1]
    if not component then return err("component not found", "NOT_FOUND") end
    component.w = math.max(12, (component.w or 40) + (tonumber(dw) or 0))
    component.h = math.max(8, (component.h or 12) + (tonumber(dh) or 0))
    clamp_component(project, component)
    project.dirty = true
    return ok(sync_component_line(project, tonumber(index) or -1))
  end

  function service.updateSelectedField(field, value)
    local project = service.current().data
    local component = project.components[tonumber(project.selected) or -1]
    if not component then return err("component not found", "NOT_FOUND") end
    field = tostring(field or "label")
    if field == "x" or field == "y" or field == "w" or field == "h" then value = tonumber(value) or component[field] or 0 end
    component[field] = value
    clamp_component(project, component)
    project.dirty = true
    return ok(sync_component_line(project, tonumber(project.selected) or -1))
  end

  function service.scrollPreview(dx, dy)
    local project = service.current().data
    project.preview_scroll_x = math.max(0, (tonumber(project.preview_scroll_x) or 0) + (tonumber(dx) or 0))
    project.preview_scroll_y = math.max(0, (tonumber(project.preview_scroll_y) or 0) + (tonumber(dy) or 0))
    return ok({ x = project.preview_scroll_x, y = project.preview_scroll_y })
  end

  function service.scrollCode(delta)
    local project = service.current().data
    project.code_scroll = math.max(0, (tonumber(project.code_scroll) or 0) + (tonumber(delta) or 0))
    return ok(project.code_scroll)
  end

  function service.sourceCode()
    local project = service.current().data
    project.code = project.script or dockscript(project)
    return ok(project.code)
  end

  function service.diagnostics()
    local project = service.current().data
    local issues = {}
    local seen = {}
    local window = project.window or { w = 220, h = 120 }
    for index, component in ipairs(project.components or {}) do
      local id = tostring(component.id or "")
      if id == "" then
        table.insert(issues, { level = "error", message = "Component " .. tostring(index) .. " has no id" })
      elseif seen[id] then
        table.insert(issues, { level = "error", message = "Duplicate component id: " .. id })
      end
      seen[id] = true
      if (component.x or 1) < 1 or (component.y or 1) < 1 or ((component.x or 1) + (component.w or 0)) > (window.w or 220) or ((component.y or 1) + (component.h or 0)) > ((window.h or 120) - 20) then
        table.insert(issues, { level = "warning", message = "Component outside window: " .. (id ~= "" and id or tostring(index)) })
      end
    end
    return ok({ count = #issues, issues = issues })
  end

  function service.setScript(script)
    local project = service.current().data
    apply_script(project, script)
    project.code = project.script
    project.dirty = true
    return ok(project)
  end

  function service.setScriptLine(line_index, value)
    local project = service.current().data
    local lines = script_lines(project.script)
    line_index = math.max(1, math.floor(tonumber(line_index) or 1))
    while #lines < line_index do table.insert(lines, "") end
    lines[line_index] = tostring(value or "")
    return service.setScript(table.concat(lines, "\n") .. "\n")
  end

  function service.insertScriptLine(line_index, value)
    local project = service.current().data
    local lines = script_lines(project.script)
    line_index = math.max(1, math.min(#lines + 1, math.floor(tonumber(line_index) or (#lines + 1))))
    table.insert(lines, line_index, tostring(value or ""))
    return service.setScript(table.concat(lines, "\n") .. "\n")
  end

  function service.deleteScriptLine(line_index)
    local project = service.current().data
    local lines = script_lines(project.script)
    if #lines <= 1 then return service.setScript("") end
    line_index = math.max(1, math.min(#lines, math.floor(tonumber(line_index) or #lines)))
    table.remove(lines, line_index)
    return service.setScript(table.concat(lines, "\n") .. "\n")
  end

  function service.loadExample(name)
    service.project = default_project()
    local project = service.project
    name = tostring(name or "notify")
    if name == "duo" then
      project.name = "Language Cards"
      project.id = safe_id(project.name)
      project.window = { w = 250, h = 140, titlebar = true }
      project.components = {
        { id = "headline", kind = "text", text = "Choose the correct translation", x = 16, y = 14, w = 168, h = 12 },
        { id = "card", kind = "shape", label = "Card", color = "green", x = 16, y = 34, w = 112, h = 52 },
        { id = "answer", kind = "input", label = "Type answer", x = 16, y = 94, w = 120, h = 16 },
        { id = "check", kind = "button", label = "Check", action = "notify", message = "Correct", x = 146, y = 94, w = 58, h = 16 },
      }
    elseif name == "counter" then
      project.name = "Counter App"
      project.id = safe_id(project.name)
      project.components = {
        { id = "title", kind = "text", text = "Counter", x = 14, y = 14, w = 70, h = 12 },
        { id = "increment", kind = "button", label = "Increment", action = "notify", message = "Counter clicked", x = 14, y = 34, w = 78, h = 16 },
        { id = "panel", kind = "shape", label = "Panel", color = "blue", x = 108, y = 16, w = 70, h = 54 },
      }
    else
      project.name = "Notification App"
      project.id = safe_id(project.name)
      project.components = {
        { id = "title", kind = "text", text = "Notification demo", x = 14, y = 14, w = 112, h = 12 },
        { id = "notify", kind = "button", label = "Send", action = "notify", message = "Notification API works", x = 14, y = 36, w = 58, h = 16 },
        { id = "message", kind = "input", label = "Message", x = 14, y = 60, w = 104, h = 16 },
      }
    end
    project.selected = 1
    project.mode = "design"
    project.tool = "move"
    project.insert_kind = "button"
    project.dirty = true
    return ok(refresh(project))
  end

  function service.setName(name)
    local project = service.current().data
    project.name = tostring(name or project.name)
    project.id = safe_id(project.name)
    project.dirty = true
    sync_assignment_line(project, "app.name", project.name)
    sync_assignment_line(project, "app.id", project.id)
    return ok(project)
  end

  function service.setCode(code)
    return service.setScript(code)
  end

  function service.setIcon(icon)
    local project = service.current().data
    project.icon = tostring(icon or "placeholder")
    project.dirty = true
    sync_assignment_line(project, "app.icon", project.icon)
    return ok(project)
  end

  function service.cycleIcon()
    local project = service.current().data
    local icons = { "placeholder", "studio", "settings", "folder", "terminal" }
    local current = project.icon or "placeholder"
    local next_icon = icons[1]
    for index, icon in ipairs(icons) do
      if icon == current then next_icon = icons[(index % #icons) + 1]; break end
    end
    return service.setIcon(next_icon)
  end

  function service.save()
    ensure()
    local project = service.current().data
    apply_script(project, project.script)
    local path = paths.join(projects_dir, project.id .. ".json")
    project.dirty = false
    return ctx.safe_io.writeJson(path, project)
  end

  function service.exportApp()
    local project = service.current().data
    apply_script(project, project.script)
    local target = paths.join(paths.userFolder("default", "Apps"), safe_file_name(project.name) .. ".app")
    if fs.exists(target) then fs.delete(target) end
    fs.makeDir(target)
    local manifest = ctx.safe_io.writeFile(paths.join(target, "app.json"), encode_manifest(project))
    if not manifest.ok then return manifest end
    local ui = ctx.safe_io.writeJson(paths.join(target, "ui.json"), {
      format = "dockos.app.ui",
      language = "DockScript",
      script = project.script,
      name = project.name,
      icon = project.icon or "placeholder",
      window = project.window or { w = 220, h = 120 },
      components = project.components or {},
    })
    if not ui.ok then return ui end
    local main = ctx.safe_io.writeFile(paths.join(target, "main.lua"), render_main(project))
    if not main.ok then return main end
    ctx.app_service.scanApps()
    if ctx.permission_service then
      for _, permission in ipairs(project.permissions or {}) do ctx.permission_service.grant(project.id, permission) end
    end
    project.dirty = false
    return ok({ path = target, manifest = paths.join(target, "app.json"), ui = paths.join(target, "ui.json") })
  end

  function service.preview()
    local project = service.current().data
    return ok({ title = project.name, components = project.components, window = project.window, script = project.script })
  end

  function service.start() return ok(true) end

  return service
end

return M
