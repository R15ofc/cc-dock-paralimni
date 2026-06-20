local M = {}

local function ok(data) return { ok = true, data = data } end
local function err(message, code) return { ok = false, error = tostring(message), code = code or "MENU_ERROR" } end

local function clone_items(items)
  local out = {}
  for _, item in ipairs(items or {}) do
    table.insert(out, {
      id = tostring(item.id or item.label or "action"),
      label = tostring(item.label or item.id or "Action"),
      enabled = item.enabled ~= false,
      handler = item.handler,
    })
  end
  return out
end

function M.new()
  local service = { menus = {} }

  local defaults = {
    ["dock.files"] = {
      { id = "new", label = "File" },
      { id = "edit", label = "Edit" },
      { id = "view", label = "View" },
      { id = "go", label = "Go" },
      { id = "window", label = "Window" },
    },
    ["dock.settings"] = {
      { id = "view", label = "View" },
      { id = "window", label = "Window" },
    },
    ["dock.studio"] = {
      { id = "file", label = "File" },
      { id = "edit", label = "Edit" },
      { id = "insert", label = "Insert" },
      { id = "build", label = "Build" },
      { id = "window", label = "Window" },
    },
  }

  function service.set(app_id, items)
    if type(items) ~= "table" then return err("items must be table", "INVALID_ITEMS") end
    service.menus[tostring(app_id)] = clone_items(items)
    return ok(service.menus[tostring(app_id)])
  end

  function service.append(app_id, item)
    local id = tostring(app_id)
    service.menus[id] = service.menus[id] or clone_items(defaults[id] or defaults["dock.files"])
    table.insert(service.menus[id], clone_items({ item })[1])
    return ok(service.menus[id])
  end

  function service.menuFor(app_id)
    local id = tostring(app_id or "")
    return ok(clone_items(service.menus[id] or defaults[id] or {
      { id = "file", label = "File" },
      { id = "edit", label = "Edit" },
      { id = "view", label = "View" },
      { id = "window", label = "Window" },
    }))
  end

  function service.dispatch(app_id, action_id, payload)
    local items = service.menus[tostring(app_id)] or {}
    for _, item in ipairs(items) do
      if item.id == action_id and type(item.handler) == "function" then
        local ok_call, result = pcall(item.handler, payload)
        if ok_call then return ok(result) end
        return err(result, "HANDLER_FAILED")
      end
    end
    return ok(false)
  end

  function service.start() return ok(true) end

  return service
end

return M
