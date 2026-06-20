local M = {}

function M.encode(value)
  if textutils and textutils.serializeJSON then
    local ok, encoded = pcall(textutils.serializeJSON, value)
    if ok and encoded then
      return encoded
    end
  end
  if textutils and textutils.serialize then
    return textutils.serialize(value)
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
