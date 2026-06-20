local paths = require("dock.system.paths")
local safe_io = require("dock.system.safe_io")

local M = {}

local function ok(data) return { ok = true, data = data } end
local function err(message, code) return { ok = false, error = tostring(message), code = code or "APP_RUNTIME_ERROR" } end

local function starts_with(value, prefix)
  value = tostring(value or "")
  prefix = tostring(prefix or "")
  return value == prefix or value:sub(1, #prefix + 1) == prefix .. "/"
end

local function normalize(path)
  return fs.combine("", tostring(path or ""))
end

local function list_copy(value)
  local out = {}
  for _, item in ipairs(value or {}) do table.insert(out, item) end
  return out
end

local function path_arg(first, second)
  if type(first) == "table" then return second end
  return first
end

local function data_arg(first, second, third)
  if type(first) == "table" then return third end
  return second
end

function M.new(ctx)
  local service = {
    ctx = ctx,
    instances = {},
    next_instance = 1,
  }

  local function app_data_dir(app_id)
    local path = paths.appData("default", app_id)
    safe_io.ensureDir(path)
    return path
  end

  local function app_cache_dir(app_id)
    local path = paths.appCache("default", app_id)
    safe_io.ensureDir(path)
    return path
  end

  local function check_permission(app_id, permission)
    if not ctx.permission_service then return ok(true) end
    return ctx.permission_service.require(app_id, permission)
  end

  local function ensure_user_write_path(path)
    path = normalize(path)
    local home = normalize(paths.userHome("default"))
    local tmp = normalize(paths.tmp)
    if starts_with(path, home) or starts_with(path, tmp) then return ok(path) end
    return err("write outside user space: " .. path, "PATH_DENIED")
  end

  local function ensure_read_path(path, app)
    path = normalize(path)
    local home = normalize(paths.userHome("default"))
    local source = normalize(app.source_dir)
    local assets = normalize(paths.assets)
    if starts_with(path, home) or starts_with(path, source) or starts_with(path, assets) then return ok(path) end
    return err("read outside app/user space: " .. path, "PATH_DENIED")
  end

  local function sandbox_fs(app)
    local app_id = app.manifest.id
    local api = {}

    function api.dataPath(name)
      if name then return paths.join(app_data_dir(app_id), tostring(name)) end
      return app_data_dir(app_id)
    end

    function api.cachePath(name)
      if name then return paths.join(app_cache_dir(app_id), tostring(name)) end
      return app_cache_dir(app_id)
    end

    function api.exists(path)
      local permission = check_permission(app_id, "fs.read")
      if not permission.ok then return false end
      local allowed = ensure_read_path(path or app_data_dir(app_id), app)
      if not allowed.ok then return false end
      return fs.exists(allowed.data)
    end

    function api.list(path)
      local permission = check_permission(app_id, "fs.read")
      if not permission.ok then return permission end
      local allowed = ensure_read_path(path or app_data_dir(app_id), app)
      if not allowed.ok then return allowed end
      if not fs.exists(allowed.data) or not fs.isDir(allowed.data) then return err("directory not found", "NOT_FOUND") end
      return ok(fs.list(allowed.data))
    end

    function api.read(path)
      local permission = check_permission(app_id, "fs.read")
      if not permission.ok then return permission end
      local allowed = ensure_read_path(path or app_data_dir(app_id), app)
      if not allowed.ok then return allowed end
      return safe_io.readFile(allowed.data)
    end

    function api.write(path, data)
      local permission = check_permission(app_id, "fs.write")
      if not permission.ok then return permission end
      local allowed = ensure_user_write_path(path or app_data_dir(app_id))
      if not allowed.ok then return allowed end
      return safe_io.writeFile(allowed.data, data or "")
    end

    function api.delete(path)
      local permission = check_permission(app_id, "fs.delete")
      if not permission.ok then return permission end
      local allowed = ensure_user_write_path(path)
      if not allowed.ok then return allowed end
      if not fs.exists(allowed.data) then return err("path not found", "NOT_FOUND") end
      fs.delete(allowed.data)
      return ok(allowed.data)
    end

    return api
  end

  local function build_app_context(app, instance)
    local manifest = app.manifest
    local app_id = manifest.id
    local app_ctx = {
      app = {
        id = app_id,
        name = manifest.name,
        version = manifest.version,
        permissions = list_copy(manifest.permissions),
        source_dir = app.source_dir,
      },
      instance = instance,
      version = ctx.version,
      fs = sandbox_fs(app),
      fs_service = {
        listDirectory = function(first, second) return app_ctx.fs.list(path_arg(first, second)) end,
        readFile = function(first, second) return app_ctx.fs.read(path_arg(first, second)) end,
        writeFile = function(first, second, third) return app_ctx.fs.write(path_arg(first, second), data_arg(first, second, third)) end,
        createFile = function(first, second, third) return app_ctx.fs.write(path_arg(first, second), data_arg(first, second, third) or "") end,
      },
      settings = {},
      storage = {},
      events = {},
      ipc = {},
      notification = {},
      process = {},
      ui = {},
      user_service = {
        getCurrentUser = function() return ctx.user_service.getCurrentUser() end,
        getHome = function() return ctx.user_service.getHome() end,
      },
      device_service = {
        getCapabilities = function() return ctx.device_service.getCapabilities() end,
        listPeripherals = function()
          local allowed = check_permission(app_id, "peripheral.access")
          if not allowed.ok then return allowed end
          return ctx.device_service.listPeripherals()
        end,
      },
      shell_service = {
        printHelp = function() if ctx.shell_service then return ctx.shell_service.printHelp() end end,
      },
      studio_service = {
        current = function() return ctx.studio_service.current() end,
        newProject = function(name) return ctx.studio_service.newProject(name) end,
        addComponent = function(kind, x, y) return ctx.studio_service.addComponent(kind, x, y) end,
        selectComponent = function(index) return ctx.studio_service.selectComponent(index) end,
        moveComponent = function(index, x, y) return ctx.studio_service.moveComponent(index, x, y) end,
        resizeComponent = function(index, dw, dh) return ctx.studio_service.resizeComponent(index, dw, dh) end,
        updateSelectedField = function(field, value) return ctx.studio_service.updateSelectedField(field, value) end,
        setScript = function(script) return ctx.studio_service.setScript(script) end,
        setScriptLine = function(line, value) return ctx.studio_service.setScriptLine(line, value) end,
        insertScriptLine = function(line, value) return ctx.studio_service.insertScriptLine(line, value) end,
        deleteScriptLine = function(line) return ctx.studio_service.deleteScriptLine(line) end,
        diagnostics = function() return ctx.studio_service.diagnostics() end,
        setMode = function(mode) return ctx.studio_service.setMode(mode) end,
        setTool = function(tool, insert_kind) return ctx.studio_service.setTool(tool, insert_kind) end,
        setIcon = function(icon) return ctx.studio_service.setIcon(icon) end,
        cycleIcon = function() return ctx.studio_service.cycleIcon() end,
        loadExample = function(name) return ctx.studio_service.loadExample(name) end,
        save = function() return ctx.studio_service.save() end,
        exportApp = function() return ctx.studio_service.exportApp() end,
      },
    }

    local function storage_path()
      return paths.join(app_data_dir(app_id), "storage.json")
    end

    local function read_storage()
      local allowed = check_permission(app_id, "storage.app")
      if not allowed.ok then return allowed end
      return safe_io.readJson(storage_path(), {})
    end

    local function write_storage(value)
      local allowed = check_permission(app_id, "storage.app")
      if not allowed.ok then return allowed end
      return safe_io.writeJson(storage_path(), value or {})
    end

    function app_ctx.settings.get(key, default)
      local allowed = check_permission(app_id, "settings.read")
      if not allowed.ok then return allowed end
      local current = ctx.settings_service.getAppSettings(app_id).data or {}
      if current[key] == nil then return default end
      return current[key]
    end

    function app_ctx.settings.set(key, value)
      local allowed = check_permission(app_id, "settings.write")
      if not allowed.ok then return allowed end
      local current = ctx.settings_service.getAppSettings(app_id).data or {}
      current[key] = value
      return ctx.settings_service.setAppSettings(app_id, current)
    end

    function app_ctx.ipc.send(pid, kind, payload)
      local allowed = check_permission(app_id, "ipc.message")
      if not allowed.ok then return allowed end
      return ctx.ipc_service.send(app_id, pid, kind, payload)
    end

    function app_ctx.ipc.publish(channel, kind, payload)
      local allowed = check_permission(app_id, "ipc.message")
      if not allowed.ok then return allowed end
      return ctx.ipc_service.publish(app_id, channel, kind, payload)
    end

    function app_ctx.ipc.receive()
      return ctx.ipc_service.receive(instance.pid)
    end

    function app_ctx.notification.send(title, body)
      local allowed = check_permission(app_id, "notification.send")
      if not allowed.ok then return allowed end
      return ctx.notification_service.add(title or manifest.name, body or "", app_id)
    end

    function app_ctx.storage.get(key, default)
      local current = read_storage()
      if not current.ok then return current end
      local value = current.data[tostring(key or "")]
      if value == nil then value = default end
      return ok(value)
    end

    function app_ctx.storage.set(key, value)
      local current = read_storage()
      if not current.ok then return current end
      current.data[tostring(key or "")] = value
      return write_storage(current.data)
    end

    function app_ctx.storage.delete(key)
      local current = read_storage()
      if not current.ok then return current end
      current.data[tostring(key or "")] = nil
      return write_storage(current.data)
    end

    function app_ctx.storage.all()
      return read_storage()
    end

    function app_ctx.events.emit(kind, payload)
      local event_payload = payload or {}
      if type(event_payload) ~= "table" then event_payload = { value = event_payload } end
      event_payload.app_id = event_payload.app_id or app_id
      event_payload.kind = kind or event_payload.kind or "event"
      if ctx.process_manager and ctx.process_manager.dispatch then return ctx.process_manager.dispatch("dock_app_event", event_payload) end
      return ok(false)
    end

    function app_ctx.events.onAny()
      return coroutine.yield("*")
    end

    function app_ctx.process.launch(target_app_id, args)
      local allowed = check_permission(app_id, "process.spawn")
      if not allowed.ok then return allowed end
      return service.launch(target_app_id, args or {})
    end

    app_ctx.ui.menu = {
      set = function(items) return ctx.menu_service.set(app_id, items or {}) end,
      append = function(item) return ctx.menu_service.append(app_id, item or {}) end,
      get = function() return ctx.menu_service.menuFor(app_id) end,
    }

    app_ctx.ui.text = {
      focus = function(id, value, cursor) return ctx.text_input_service.focus(app_id .. ":" .. tostring(id or "input"), value, cursor) end,
      get = function(id) return ctx.text_input_service.get(app_id .. ":" .. tostring(id or "input")) end,
      set = function(id, value, cursor) return ctx.text_input_service.set(app_id .. ":" .. tostring(id or "input"), value, cursor) end,
    }

    app_ctx.ui.notify = function(body, title) return app_ctx.notification.send(title or manifest.name, body or "") end
    app_ctx.ui.emit = function(kind, payload) return app_ctx.events.emit(kind, payload) end
    app_ctx.ui.launch = function(target_app_id, args) return app_ctx.process.launch(target_app_id, args or {}) end

    return app_ctx
  end

  local function load_module(app)
    local entry_path = fs.combine(app.source_dir, app.manifest.entry)
    if not fs.exists(entry_path) then return err("entry missing: " .. entry_path, "ENTRY_MISSING") end
    local loaded, module_or_error = pcall(dofile, entry_path)
    if not loaded then return err(module_or_error, "APP_LOAD_FAILED") end
    if type(module_or_error) ~= "table" or type(module_or_error.run) ~= "function" then
      return err("app must return table with run", "INVALID_APP")
    end
    return ok(module_or_error)
  end

  local function sync_instance(instance)
    local process = ctx.process_manager.get(instance.pid).data
    if process then
      instance.state = process.status
      instance.last_error = process.last_error
      instance.updated_at = process.updated_at
    end
    return instance
  end

  function service.launch(app_id, args)
    local app = ctx.app_service.getApp(app_id)
    if not app.ok then return app end
    local permissions = ctx.permission_service and ctx.permission_service.registerApp(app.data.manifest)
    if permissions and not permissions.ok then return permissions end
    local module = load_module(app.data)
    if not module.ok then return module end
    service.next_instance = service.next_instance + 1
    local instance = {
      id = service.next_instance - 1,
      app_id = app_id,
      pid = nil,
      state = "created",
      args = args or {},
      started_at = os.clock(),
      updated_at = os.clock(),
      last_error = nil,
    }
    local process = ctx.process_manager.spawnAsync(app.data.manifest.name, function()
      local app_ctx = build_app_context(app.data, instance)
      return module.data.run(app_ctx, args or {}, app.data.manifest)
    end, { app_id = app_id, instance_id = instance.id })
    if not process.ok then return process end
    instance.pid = process.data.pid
    instance.state = process.data.status
    table.insert(service.instances, instance)
    ctx.process_manager.step()
    sync_instance(instance)
    if ctx.event_bus then ctx.event_bus.emit("app_launched", { id = app_id, instance_id = instance.id, pid = instance.pid }) end
    return ok(instance)
  end

  function service.list()
    local out = {}
    for _, instance in ipairs(service.instances) do table.insert(out, sync_instance(instance)) end
    return ok(out)
  end

  function service.stateForApp(app_id)
    local state = { app_id = app_id, running = false, loading = false, crashed = false, count = 0 }
    for _, instance in ipairs(service.instances) do
      if instance.app_id == app_id then
        sync_instance(instance)
        if instance.state == "ready" or instance.state == "running" then state.loading = true end
        if instance.state == "ready" or instance.state == "running" or instance.state == "waiting" then
          state.running = true
          state.count = state.count + 1
        elseif instance.state == "crashed" then
          state.crashed = true
        end
      end
    end
    return ok(state)
  end

  function service.get(instance_id)
    instance_id = tonumber(instance_id)
    for _, instance in ipairs(service.instances) do
      if instance.id == instance_id then return ok(sync_instance(instance)) end
    end
    return err("instance not found", "NOT_FOUND")
  end

  function service.stop(instance_or_pid)
    local target = tonumber(instance_or_pid)
    for _, instance in ipairs(service.instances) do
      if instance.id == target or instance.pid == target then
        local stopped = ctx.process_manager.stop(instance.pid)
        sync_instance(instance)
        if ctx.event_bus then ctx.event_bus.emit("app_stopped", { app_id = instance.app_id, instance_id = instance.id, pid = instance.pid }) end
        return stopped
      end
    end
    return err("instance not found", "NOT_FOUND")
  end

  function service.stopApp(app_id)
    local stopped = {}
    for _, instance in ipairs(service.instances) do
      if instance.app_id == app_id and instance.pid and instance.state ~= "stopped" and instance.state ~= "crashed" then
        local result = ctx.process_manager.stop(instance.pid)
        sync_instance(instance)
        if result.ok then table.insert(stopped, instance.id) end
      end
    end
    if ctx.event_bus then ctx.event_bus.emit("app_stopped", { app_id = app_id }) end
    return ok(stopped)
  end

  function service.start()
    return ok(true)
  end

  return service
end

return M
