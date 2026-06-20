local M = {}

function M.new()
  local registry = { apps = {} }

  function registry.register(manifest, source_dir)
    registry.apps[manifest.id] = { manifest = manifest, source_dir = source_dir }
    return { ok = true, data = registry.apps[manifest.id] }
  end

  function registry.unregister(id)
    registry.apps[id] = nil
    return { ok = true }
  end

  function registry.get(id)
    local app = registry.apps[id]
    if not app then return { ok = false, error = "app not found", code = "NOT_FOUND" } end
    return { ok = true, data = app }
  end

  function registry.list()
    local list = {}
    for _, app in pairs(registry.apps) do table.insert(list, app) end
    table.sort(list, function(a, b) return a.manifest.name < b.manifest.name end)
    return { ok = true, data = list }
  end

  return registry
end

return M
