local json = require("dock.system.json")

local M = {}

local function result(ok, data, err, code)
  if ok then
    return { ok = true, data = data }
  end
  return { ok = false, error = tostring(err or "unknown error"), code = code or "IO_ERROR" }
end

function M.ensureDir(path)
  if not path or path == "" then
    return result(false, nil, "missing path", "MISSING_PATH")
  end
  if fs.exists(path) then
    if fs.isDir(path) then
      return result(true, path)
    end
    return result(false, nil, "path is a file: " .. path, "NOT_DIRECTORY")
  end
  local ok, err = pcall(fs.makeDir, path)
  return result(ok, path, err, "MKDIR_FAILED")
end

function M.ensureParent(path)
  local dir = fs.getDir(path)
  if dir and dir ~= "" then
    return M.ensureDir(dir)
  end
  return result(true, "")
end

function M.readFile(path)
  if not fs.exists(path) or fs.isDir(path) then
    return result(false, nil, "file not found: " .. tostring(path), "NOT_FOUND")
  end
  local handle, err = fs.open(path, "r")
  if not handle then
    return result(false, nil, err, "OPEN_FAILED")
  end
  local ok, data = pcall(handle.readAll)
  handle.close()
  return result(ok, data or "", data, "READ_FAILED")
end

function M.writeFile(path, data)
  local parent = M.ensureParent(path)
  if not parent.ok then
    return parent
  end
  local tmp = fs.combine(fs.getDir(path) ~= "" and fs.getDir(path) or ".", "." .. fs.getName(path) .. ".tmp." .. tostring(os.clock()):gsub("%.", "_"))
  local handle, err = fs.open(tmp, "w")
  if not handle then
    return result(false, nil, err, "OPEN_FAILED")
  end
  local ok, write_err = pcall(function()
    handle.write(data or "")
  end)
  handle.close()
  if not ok then
    if fs.exists(tmp) then fs.delete(tmp) end
    return result(false, nil, write_err, "WRITE_FAILED")
  end
  if fs.exists(path) then
    fs.delete(path)
  end
  local moved, move_err = pcall(fs.move, tmp, path)
  if not moved then
    if fs.exists(tmp) then fs.delete(tmp) end
    return result(false, nil, move_err, "MOVE_FAILED")
  end
  return result(true, path)
end

function M.copyFile(source, target, binary)
  if not fs.exists(source) or fs.isDir(source) then
    return result(false, nil, "file not found: " .. tostring(source), "NOT_FOUND")
  end
  local parent = M.ensureParent(target)
  if not parent.ok then return parent end
  local source_mode = binary and "rb" or "r"
  local target_mode = binary and "wb" or "w"
  local input, input_err = fs.open(source, source_mode)
  if not input then return result(false, nil, input_err, "OPEN_FAILED") end
  local output, output_err = fs.open(target, target_mode)
  if not output then input.close(); return result(false, nil, output_err, "OPEN_FAILED") end
  local ok, copy_err = pcall(function()
    if binary then
      while true do
        local chunk = input.read(8192)
        if chunk == nil then break end
        output.write(chunk)
      end
    else
      output.write(input.readAll() or "")
    end
  end)
  output.close()
  input.close()
  return result(ok, target, copy_err, "COPY_FAILED")
end

function M.shouldCopyBinary(path)
  local ext = tostring(path or ""):lower():match("%.([%w_%-]+)$")
  return ext == "png" or ext == "jpg" or ext == "jpeg" or ext == "gif" or ext == "bmp" or ext == "webp" or ext == "nfp" or ext == "nft"
end

function M.appendFile(path, data)
  M.ensureParent(path)
  local handle, err = fs.open(path, "a")
  if not handle then
    return result(false, nil, err, "OPEN_FAILED")
  end
  local ok, write_err = pcall(function()
    handle.write(data or "")
  end)
  handle.close()
  return result(ok, path, write_err, "WRITE_FAILED")
end

function M.readJson(path, default)
  if not fs.exists(path) then
    return result(true, default)
  end
  local read = M.readFile(path)
  if not read.ok then
    return read
  end
  local decoded, err = json.decode(read.data)
  if decoded == nil then
    return result(false, nil, err, "JSON_DECODE_FAILED")
  end
  return result(true, decoded)
end

function M.writeJson(path, value)
  return M.writeFile(path, json.encode(value))
end

return M
