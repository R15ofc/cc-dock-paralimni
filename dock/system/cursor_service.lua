local loading = require("dock.system.loading")
local cursor_pack = require("dock.system.cursor_pack")

local M = {}

local function ok(data) return { ok = true, data = data } end

function M.new()
  local service = {
    x = 8,
    y = 8,
    kind = "default",
    visible = true,
    busy = {},
  }

  local clickable = {
    system_menu = true, about = true, about_close = true, lock_screen = true, reboot = true, shutdown = true,
    dock_app = true, dock_keep = true,
    explorer_sidebar = true, explorer_row = true, explorer_search = true, explorer_rename = true,
    explorer_back = true, explorer_forward = true, explorer_up = true, explorer_refresh = true,
    explorer_new_folder = true, explorer_new_file = true, explorer_copy = true, explorer_cut = true,
    explorer_paste = true, explorer_trash = true, explorer_scroll_up = true, explorer_scroll_down = true,
    settings_back = true, settings_forward = true, settings_nav = true, settings_sub = true,
    settings_theme = true, settings_update_install = true, settings_login_toggle = true, settings_password_clear = true,
    settings_cloud_register = true, settings_cloud_login = true, settings_cloud_logout = true, settings_cloud_avatar = true,
    studio_new = true, studio_save = true, studio_run = true, studio_export = true, studio_example = true, studio_icon = true, studio_insert = true, studio_field = true,
    studio_mode = true, studio_open_project = true, studio_tool = true, studio_duplicate = true, studio_delete = true,
    studio_resize = true, studio_code_panel = true,
    studio_component = true, app_component_button = true,
    top_menu = true, window_close = true, window_min = true, window_full = true,
  }

  local text_inputs = { login_password = true, explorer_search = true, explorer_rename = true, settings_password_field = true, settings_cloud_field = true, studio_code_line = true, studio_prop_field = true }
  local draggable = { window_drag = true, dock_app = true, studio_splitter = true, studio_component = true }
  local denied = { dock_divider = true }

  function service.setPosition(x, y)
    service.x = math.max(1, math.floor(tonumber(x) or service.x or 1))
    service.y = math.max(1, math.floor(tonumber(y) or service.y or 1))
    return ok({ x = service.x, y = service.y })
  end

  function service.setBusy(id, value)
    if value then service.busy[tostring(id)] = true else service.busy[tostring(id)] = nil end
    return ok(service.busy)
  end

  function service.infer(hit, dragging)
    if dragging then return "drag" end
    if hit and hit.payload and type(hit.payload) == "string" and service.busy[hit.payload] then return "loading" end
    if hit and denied[hit.id] then return "denied" end
    if hit and draggable[hit.id] then return "drag" end
    if hit and text_inputs[hit.id] then return "text" end
    if hit and clickable[hit.id] then return "click" end
    return "default"
  end

  function service.draw(gpu, kind, frame)
    if not service.visible then return ok(false) end
    kind = kind or service.kind or "default"
    local x, y = service.x, service.y
    cursor_pack.draw(gpu, kind, x, y, frame, loading.spinner(frame))
    return ok(kind)
  end

  function service.start() return ok(true) end

  return service
end

return M
