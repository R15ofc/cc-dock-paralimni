local paths = require("dock.system.paths")
local safe_io = require("dock.system.safe_io")

local M = {}
local active = { file = paths.join(paths.logs, "system.log"), level = "debug" }

local function stamp()
  if os.epoch then
    local ok, value = pcall(os.epoch, "utc")
    if ok then return tostring(value) end
  end
  return tostring(os.clock())
end

local function write(level, message, file)
  safe_io.ensureDir(paths.logs)
  local line = "[" .. stamp() .. "] " .. level .. " " .. tostring(message) .. "\n"
  safe_io.appendFile(file or active.file, line)
end

function M.init(file)
  active.file = file or active.file
  safe_io.ensureDir(paths.logs)
  return M
end

function M.info(message, file) write("INFO", message, file) end
function M.warn(message, file) write("WARN", message, file) end
function M.error(message, file) write("ERROR", message, file) end
function M.debug(message, file) write("DEBUG", message, file) end

function M.file(name)
  return paths.join(paths.logs, name)
end

return M
