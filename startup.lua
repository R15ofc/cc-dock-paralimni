local ok, boot = pcall(require, "dock.system.boot")
if not ok then
  print("DockOS boot module missing: " .. tostring(boot))
  return
end
boot.start({ mode = "desktop" })
