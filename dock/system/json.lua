local M = {}

local function clone_json_safe(value, seen)
  local value_type = type(value)
  if value_type ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return nil end
  seen[value] = true
  local out = {}
  for key, item in pairs(value) do
    local key_type = type(key)
    if key_type == "string" or key_type == "number" then
      local cloned = clone_json_safe(item, seen)
      if cloned ~= nil then out[key] = cloned end
    end
  end
  seen[value] = nil
  return out
end

function M.encode(value)
  local safe_value = clone_json_safe(value)
  if textutils and textutils.serializeJSON then
    local ok, encoded = pcall(textutils.serializeJSON, safe_value)
    if ok and encoded then
      return encoded
    end
  end
  if textutils and textutils.serialize then
    local ok, encoded = pcall(textutils.serialize, safe_value)
    if ok and encoded then return encoded end
  end
  return "{}"
end

function M.decode(data)
  if type(data) ~= "string" or data == "" then
    return nil, "empty data"
  end
  if textutils and textutils.unserializeJSON then
    local ok, decoded = pcall(textutils.unserializeJSON, data)
    if ok and decoded ~= nil then
      return decoded
    end
  end
  if textutils and textutils.unserialize then
    local ok, decoded = pcall(textutils.unserialize, data)
    if ok and decoded ~= nil then
      return decoded
    end
  end
  return nil, "decode failed"
end

return M
