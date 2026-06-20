local args = { ... }
if shell then
  shell.run("/dock.lua", table.unpack and table.unpack(args) or unpack(args))
else
  dofile("/dock.lua")
end
