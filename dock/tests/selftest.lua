local paths = require("dock.system.paths")
local json = require("dock.system.json")
local loading = require("dock.system.loading")
local scrollbar = require("dock.system.scrollbar")
local splash = require("dock.system.splash")

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
    local notified = ctx.notification_service.add("Selftest", "Body", "selftest.app")
    check("notification app state", notified.ok and ctx.notification_service.recentForApp("selftest.app", 5).data ~= nil)
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
    ctx.explorer_service.startRename(explorer_id)
    ctx.explorer_service.setRenameText(explorer_id, "renamed/illegal:name.txt")
    local renamed = ctx.explorer_service.commitRename(explorer_id)
    check("explorer rename keeps extension", renamed.ok and fs.getName(renamed.data) == "renamedillegalname.txt")
    file = renamed
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
    check("loading helper", loading.spinner(0) == "|" and loading.progress(50, 4):match("^##%-%-") ~= nil)
    local scroll_metrics = scrollbar.metrics(10, 4, 2, 1, 1, 40)
    check("scrollbar helper", scroll_metrics.enabled and scrollbar.offsetFromY(scroll_metrics, scroll_metrics.thumb_y) >= 0)
    local fake_gpu = {
      filledRectangle = function() end,
      drawText = function() end,
      getSize = function() return 128, 64 end,
      sync = function() end,
    }
    local splash_ok = pcall(function() splash.draw(fake_gpu, { message = "Selftest", progress = 50 }) end)
    check("splash helper", splash_ok)
    check("update service", ctx.update_service.status().ok and ctx.update_service.beginCheck().ok)
    check("cursor service", ctx.cursor_service.infer({ id = "dock_app", payload = "dock.settings" }, false) == "click")
    local text_id = "selftest-input"
    ctx.text_input_service.focus(text_id, "hello", 5)
    ctx.text_input_service.move(text_id, -2)
    ctx.text_input_service.insert(text_id, "!")
    check("text input service", ctx.text_input_service.view(text_id).data.value == "hel!lo")
    local menu_set = ctx.menu_service.set("selftest.app", { { id = "build", label = "Build" } })
    check("menu service", menu_set.ok and ctx.menu_service.menuFor("selftest.app").data[1].label == "Build")
    local studio_new = ctx.studio_service.newProject("Selftest Studio App")
    local studio_add = ctx.studio_service.addComponent("input")
    local studio_move = ctx.studio_service.moveComponent(1, 30, 30)
    local studio_source = ctx.studio_service.sourceCode()
    local studio_icon = ctx.studio_service.setIcon("placeholder")
    local studio_example = ctx.studio_service.loadExample("notify")
    local studio_export = ctx.studio_service.exportApp()
    check("studio service", studio_new.ok and studio_add.ok and studio_move.ok and studio_source.ok and studio_icon.ok and studio_example.ok and studio_export.ok and fs.exists(studio_export.data.manifest) and fs.exists(studio_export.data.ui) and studio_export.data.path:match("%.app$") ~= nil)
    ctx.app_service.scanApps()
    local studio_app_id = ctx.studio_service.current().data.id
    check("app bundle registry", ctx.app_service.getApp(studio_app_id).ok)
    local studio_runtime = ctx.app_runtime_service.launch(studio_app_id, {})
    if studio_runtime.ok then ctx.process_manager.dispatch("dock_app_event", { app_id = studio_app_id, kind = "button", action = "notify", message = "Selftest event" }) end
    check("app bundle runtime", studio_runtime.ok and ctx.notification_service.recentForApp(studio_app_id, 5).data ~= nil)
    ctx.app_runtime_service.stopApp(studio_app_id)

    local passed = 0
    for _, item in ipairs(checks) do
      print((item.ok and "PASS " or "FAIL ") .. item.name)
      if item.ok then passed = passed + 1 end
    end
    print(tostring(passed) .. "/" .. tostring(#checks) .. " checks passed")
    return { ok = passed == #checks, data = checks }
  end,
}
