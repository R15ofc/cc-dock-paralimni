return {
  run = function(ctx)
    ctx.ui.menu.set({
      { id = "file", label = "File" },
      { id = "edit", label = "Edit" },
      { id = "insert", label = "Insert" },
      { id = "build", label = "Build" },
      { id = "window", label = "Window" },
    })
    local project = ctx.studio_service and ctx.studio_service.current()
    if project and project.ok then
      print("App Studio: " .. project.data.name)
    else
      print("App Studio")
    end
    return { ok = true }
  end,
}
