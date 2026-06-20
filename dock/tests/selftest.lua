local paths = require("dock.system.paths")
local json = require("dock.system.json")

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
    ctx.time_service.setTimezone(3)
    check("time service", ctx.time_service.clockText():match("^%d%d:%d%d$") ~= nil and ctx.time_service.timezoneText() == "UTC+3")
    ctx.window_service.restore(384, 192)
    local window = ctx.window_service.open("dock.files", { x = 20, y = 20, w = 120, h = 80 })
    check("window service", window.ok and ctx.window_service.focus(window.data.id).ok and ctx.window_service.close(window.data.id).ok)
    local async = ctx.process_manager.spawnAsync("async-test", function(_, process)
      process.ready = true
      coroutine.yield("selftest_event")
      process.received = true
    end)
    ctx.process_manager.step()
    ctx.process_manager.dispatch("selftest_event")
    check("async process", async.ok and async.data.ready == true and async.data.received == true)
    local receiver = ctx.process_manager.spawnAsync("ipc-receiver", function(_, process)
      coroutine.yield("never")
      return process
    end)
    local sent = receiver.ok and ctx.ipc_service.send("selftest", receiver.data.pid, "ping", { text = "hello" })
    check("ipc service", sent and sent.ok and ctx.ipc_service.receive(receiver.data.pid).data.kind == "ping")
    local permission = ctx.permission_service.check("dock.files", "fs.read")
    check("permission service", permission.ok and permission.data == true and not ctx.permission_service.validateManifest({ id = "bad", permissions = { "unknown.permission" } }).ok)
    local repeated = { "fs.read" }
    check("json repeated table", type(json.encode({ requested = repeated, granted = repeated })) == "string")
    local granted = ctx.permission_service.grant("selftest.app", "ipc.message")
    check("permission grant", granted.ok and ctx.permission_service.check("selftest.app", "ipc.message").data == true)
    local runtime = ctx.app_runtime_service.launch("dock.files", {})
    check("app runtime", runtime.ok and runtime.data.pid ~= nil and runtime.data.app_id == "dock.files")
    local explorer_root = paths.join(paths.userFolder("default", "Documents"), "ExplorerSelftest")
    if fs.exists(explorer_root) then fs.delete(explorer_root) end
    ctx.fs_service.createDirectory(explorer_root)
    local explorer_id = "selftest-explorer"
    check("explorer navigate", ctx.explorer_service.navigate(explorer_id, explorer_root).ok)
    local folder = ctx.explorer_service.createFolder(explorer_id, "Folder")
    local file = ctx.explorer_service.createFile(explorer_id, "note.txt")
    local listed = ctx.explorer_service.list(explorer_id)
    check("explorer create/list", folder.ok and file.ok and listed.ok and #listed.data.rows >= 2)
    ctx.explorer_service.select(explorer_id, file.data)
    local copied = ctx.explorer_service.copySelected(explorer_id)
    local pasted = ctx.explorer_service.paste(explorer_id)
    check("explorer copy/paste", copied.ok and pasted.ok and fs.exists(pasted.data))
    ctx.explorer_service.select(explorer_id, pasted.data)
    local cut = ctx.explorer_service.cutSelected(explorer_id)
    ctx.explorer_service.navigate(explorer_id, folder.data)
    local moved = ctx.explorer_service.paste(explorer_id)
    check("explorer cut/paste", cut.ok and moved.ok and fs.exists(moved.data))
    ctx.explorer_service.setSearch(explorer_id, "note")
    check("explorer search", #ctx.explorer_service.list(explorer_id).data.rows >= 1)
    ctx.explorer_service.select(explorer_id, moved.data)
    local trashed = ctx.explorer_service.trashSelected(explorer_id)
    local restored_explorer = trashed.ok and ctx.fs_service.restoreFromTrash(trashed.data.id)
    check("explorer trash/restore", restored_explorer and restored_explorer.ok and fs.exists(moved.data))

    local passed = 0
    for _, item in ipairs(checks) do
      print((item.ok and "PASS " or "FAIL ") .. item.name)
      if item.ok then passed = passed + 1 end
    end
    print(tostring(passed) .. "/" .. tostring(#checks) .. " checks passed")
    return { ok = passed == #checks, data = checks }
  end,
}
