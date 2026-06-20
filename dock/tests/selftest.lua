local paths = require("dock.system.paths")

return {
  run = function(ctx)
    local checks = {}
    local function check(name, condition)
      table.insert(checks, { name = name, ok = condition and true or false })
    end

    check("boot directories", fs.exists(paths.root) and fs.exists(paths.etc) and fs.exists(paths.logs))
    check("user folders", fs.exists(paths.userFolder("default", "Documents")) and fs.exists(paths.userFolder("default", "Trash")))
    ctx.settings_service.set("user.selftest", "ok")
    check("settings save/load", ctx.settings_service.get("user.selftest").data == "ok")
    local doc_path = paths.join(paths.userFolder("default", "Documents"), "selftest.txt")
    check("document create", ctx.fs_service.writeFile(doc_path, "hello").ok and fs.exists(doc_path))
    local shortcut = ctx.fs_service.createDesktopShortcut("Selftest", doc_path, "document")
    local shortcut_path = paths.join(paths.userFolder("default", "Desktop"), "Selftest.link.json")
    check("desktop shortcut", shortcut.ok and ctx.fs_service.resolveDesktopShortcut(shortcut_path).ok)
    local trash = ctx.fs_service.moveToTrash(doc_path)
    local restored = trash.ok and ctx.fs_service.restoreFromTrash(trash.data.id)
    check("trash restore", restored and restored.ok and fs.exists(doc_path))
    local apps = ctx.app_service.scanApps()
    check("app registry", apps.ok and #apps.data >= 3)
    check("manifests", ctx.app_service.getApp("dock.files").ok and ctx.app_service.getApp("dock.terminal").ok and ctx.app_service.getApp("dock.settings").ok)
    check("devices", ctx.device_service.getCapabilities().ok)
    ctx.logger.info("selftest logger check")
    check("logger", fs.exists(paths.join(paths.logs, "system.log")))
    local invalid_dir = paths.join(paths.tmp, "invalid-package")
    if fs.exists(invalid_dir) then fs.delete(invalid_dir) end
    fs.makeDir(invalid_dir)
    local rejected = ctx.package_service.installLocal(invalid_dir)
    check("package reject", not rejected.ok)
    local crash = ctx.process_manager.spawn("crash-test", function() error("expected crash") end)
    check("process crash", not crash.ok and crash.data.status == "crashed")

    local passed = 0
    for _, item in ipairs(checks) do
      print((item.ok and "PASS " or "FAIL ") .. item.name)
      if item.ok then passed = passed + 1 end
    end
    print(tostring(passed) .. "/" .. tostring(#checks) .. " checks passed")
    return { ok = passed == #checks, data = checks }
  end,
}
