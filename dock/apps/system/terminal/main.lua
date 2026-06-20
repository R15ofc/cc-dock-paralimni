return {
  run = function(ctx)
    print("DockOS Terminal")
    ctx.shell_service.printHelp()
    return { ok = true }
  end,
}
