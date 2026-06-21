local json = require("dock.system.json")
local safe_io = require("dock.system.safe_io")

local M = {}

local function result(ok, data, err, code)
  if ok then return { ok = true, data = data } end
  return { ok = false, error = tostring(err or "cloud error"), code = code or "CLOUD_ERROR" }
end

local function trim(value)
  return tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalize_url(value)
  local url = trim(value)
  if url == "" then url = "http://127.0.0.1:8000" end
  url = url:gsub("/+$", "")
  return url
end

local function url_encode(value)
  value = tostring(value or "")
  if textutils and textutils.urlEncode then return textutils.urlEncode(value) end
  return (value:gsub("([^%w%-_%.~])", function(char)
    return string.format("%%%02X", string.byte(char))
  end))
end

local function read_all(handle)
  local ok, data = pcall(handle.readAll)
  if handle.close then handle.close() end
  if ok then return data or "" end
  return ""
end

function M.new(ctx)
  local service = { ctx = ctx, account_cache = nil, last_error = nil }

  local function server_url()
    return normalize_url(ctx.settings_service.get("user.cloud.server_url", "http://127.0.0.1:8000").data)
  end

  local function token()
    return trim(ctx.settings_service.get("user.cloud.token", "").data)
  end

  local function set_token(value)
    ctx.settings_service.set("user.cloud.token", value or "")
  end

  local function headers(authorized)
    local out = { ["Content-Type"] = "application/json", ["Accept"] = "application/json" }
    if authorized and token() ~= "" then out["Authorization"] = "Bearer " .. token() end
    return out
  end

  local function parse_response(handle)
    if not handle then return result(false, nil, "request failed", "REQUEST_FAILED") end
    local status = 200
    if handle.getResponseCode then
      local ok, code = pcall(handle.getResponseCode)
      if ok and code then status = tonumber(code) or status end
    end
    local body = read_all(handle)
    local decoded = nil
    if body ~= "" then decoded = json.decode(body) end
    if status < 200 or status >= 300 then
      local error_text = type(decoded) == "table" and (decoded.error or decoded.message) or body
      return result(false, decoded, error_text or ("HTTP " .. tostring(status)), "HTTP_" .. tostring(status))
    end
    if type(decoded) ~= "table" then return result(false, nil, "invalid server response", "BAD_RESPONSE") end
    if decoded.ok == false then return result(false, decoded, decoded.error or "cloud request failed", decoded.code or "REMOTE_ERROR") end
    return result(true, decoded)
  end

  local function request(method, path, payload, authorized)
    if not http then return result(false, nil, "HTTP API disabled", "HTTP_DISABLED") end
    local url = server_url() .. path
    local ok, handle_or_error
    if method == "GET" then
      ok, handle_or_error = pcall(http.get, url, headers(authorized))
    else
      ok, handle_or_error = pcall(http.post, url, json.encode(payload or {}), headers(authorized))
    end
    if not ok then return result(false, nil, handle_or_error, "REQUEST_FAILED") end
    if not handle_or_error then return result(false, nil, "server unavailable", "UNAVAILABLE") end
    return parse_response(handle_or_error)
  end

  local function save_account(data)
    if type(data) == "table" and type(data.account) == "table" then
      service.account_cache = data.account
      ctx.settings_service.set("user.cloud.username", data.account.username or "")
      ctx.settings_service.set("user.cloud.display_name", data.account.display_name or "")
    end
  end

  function service.configure(url)
    ctx.settings_service.set("user.cloud.server_url", normalize_url(url))
    return service.status()
  end

  function service.status()
    return result(true, {
      server_url = server_url(),
      token_present = token() ~= "",
      username = ctx.settings_service.get("user.cloud.username", "").data or "",
      display_name = ctx.settings_service.get("user.cloud.display_name", "").data or "",
      account = service.account_cache,
      last_error = service.last_error,
    })
  end

  function service.register(username, password, display_name)
    local response = request("POST", "/auth/register", { username = username, password = password, display_name = display_name or username }, false)
    if response.ok then
      set_token(response.data.token or "")
      save_account(response.data)
      service.last_error = nil
    else
      service.last_error = response.error
    end
    return response
  end

  function service.login(username, password)
    local response = request("POST", "/auth/login", { username = username, password = password }, false)
    if response.ok then
      set_token(response.data.token or "")
      save_account(response.data)
      service.last_error = nil
    else
      service.last_error = response.error
    end
    return response
  end

  function service.logout()
    request("POST", "/auth/logout", {}, true)
    set_token("")
    service.account_cache = nil
    return result(true, true)
  end

  function service.me()
    local response = request("GET", "/me", nil, true)
    if response.ok then save_account(response.data); service.last_error = nil else service.last_error = response.error end
    return response
  end

  function service.avatarUrl(url)
    local response = request("POST", "/me/avatar-url", { url = url }, true)
    if response.ok then save_account(response.data); service.last_error = nil else service.last_error = response.error end
    return response
  end

  function service.list()
    local response = request("GET", "/cloud/list", nil, true)
    if response.ok then service.last_error = nil else service.last_error = response.error end
    return response
  end

  function service.upload(local_path, remote_path)
    local read = safe_io.readFile(local_path)
    if not read.ok then return read end
    local response = request("POST", "/cloud/upload", { path = remote_path or local_path, content = read.data or "" }, true)
    if response.ok then service.last_error = nil else service.last_error = response.error end
    return response
  end

  function service.download(remote_path, local_path)
    local response = request("GET", "/cloud/download?path=" .. url_encode(remote_path), nil, true)
    if not response.ok then service.last_error = response.error; return response end
    local data = response.data.content
    if data == nil then return result(false, nil, "binary download is not supported by this client yet", "BINARY_UNSUPPORTED") end
    local write = safe_io.writeFile(local_path or remote_path, data)
    if not write.ok then return write end
    service.last_error = nil
    return result(true, { path = local_path or remote_path, remote_path = remote_path })
  end

  function service.delete(remote_path)
    local response = request("POST", "/cloud/delete", { path = remote_path }, true)
    if response.ok then service.last_error = nil else service.last_error = response.error end
    return response
  end

  function service.start()
    return result(true, true)
  end

  return service
end

return M
