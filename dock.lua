local args = { ... }
local ok, boot = pcall(require, "dock.system.boot")
if not ok then
  print("DockOS boot module missing: " .. tostring(boot))
  return
end
if #args == 0 then
  boot.start({ mode = "desktop" })
else
  boot.command(args)
end
