local M = {}

local function join(...)
  local parts = { ... }
  local current = tostring(parts[1] or "")
  for index = 2, #parts do
    current = fs.combine(current, tostring(parts[index] or ""))
  end
  return current
end

M.join = join
M.root = "dock"
M.system = join(M.root, "system")
M.apps = join(M.root, "apps")
M.system_apps = join(M.apps, "system")
M.installed_apps = join(M.apps, "installed")
M.users = join(M.root, "users")
M.default_user = join(M.users, "default")
M.etc = join(M.root, "etc")
M.var = join(M.root, "var")
M.logs = join(M.var, "log")
M.cache = join(M.var, "cache")
M.db = join(M.var, "db")
M.run = join(M.var, "run")
M.tmp = join(M.root, "tmp")
M.tests = join(M.root, "tests")
M.assets = join(M.root, "assets")

function M.userHome(user_id)
  return join(M.users, user_id or "default")
end

function M.userFolder(user_id, name)
  return join(M.userHome(user_id), name)
end

function M.userConfig(user_id)
  return join(M.userHome(user_id), ".config")
end

function M.appConfig(user_id, app_id)
  return join(M.userConfig(user_id), "apps", tostring(app_id) .. ".json")
end

function M.appData(user_id, app_id)
  return join(M.userHome(user_id), ".local", "share", "apps", tostring(app_id))
end

function M.appCache(user_id, app_id)
  return join(M.cache, "apps", tostring(user_id or "default"), tostring(app_id))
end

M.user_folders = {
  Desktop = "Desktop",
  Documents = "Documents",
  Downloads = "Downloads",
  Pictures = "Pictures",
  Music = "Music",
  Videos = "Videos",
  Apps = "Apps",
  Trash = "Trash",
}

M.required_dirs = {
  M.root,
  M.system,
  M.system_apps,
  M.installed_apps,
  M.users,
  M.default_user,
  M.etc,
  M.var,
  M.logs,
  M.cache,
  M.db,
  M.run,
  M.tmp,
  M.tests,
  M.assets,
  join(M.userConfig("default"), "apps"),
  join(M.userHome("default"), ".local"),
  join(M.userHome("default"), ".local", "share"),
  join(M.userHome("default"), ".local", "share", "apps"),
  join(M.userHome("default"), ".local", "share", "applications"),
  join(M.userHome("default"), ".local", "share", "metadata"),
  join(M.cache, "apps"),
}

for _, folder in pairs(M.user_folders) do
  table.insert(M.required_dirs, M.userFolder("default", folder))
end

return M
