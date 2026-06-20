local paths = require("dock.system.paths")
local safe_io = require("dock.system.safe_io")

local M = {}

function M.new(ctx)
  local service = { ctx = ctx, current = { id = "default", name = "Default User", home = paths.userHome("default") } }

  function service.ensureUserFolders()
    for _, path in ipairs(paths.required_dirs) do
      local ok = safe_io.ensureDir(path)
      if not ok.ok then return ok end
    end
    return { ok = true }
  end

  function service.getCurrentUser()
    return service.current
  end

  function service.getHome()
    return service.current.home
  end

  function service.getUserPath(category)
    local folder = paths.user_folders[category] or category
    return paths.userFolder(service.current.id, folder)
  end

  function service.getUserConfig()
    return safe_io.readJson(paths.join(paths.userConfig(service.current.id), "user.json"), {})
  end

  function service.setUserConfig(value)
    return safe_io.writeJson(paths.join(paths.userConfig(service.current.id), "user.json"), value or {})
  end

  service.ensureUserFolders()
  return service
end

return M
