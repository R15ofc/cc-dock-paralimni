return {
  run = function(ctx, args)
    local base = args[1] or ctx.user_service.getHome()
    local result = ctx.fs_service.listDirectory(base)
    if not result.ok then print(result.error); return result end
    print("Explorer: " .. base)
    for _, item in ipairs(result.data) do
      print((item.dir and "[D] " or "[F] ") .. item.name)
    end
    return result
  end,
}
