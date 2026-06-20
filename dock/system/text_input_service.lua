local M = {}

local function ok(data) return { ok = true, data = data } end
local function clamp(value, min_value, max_value)
  value = tonumber(value) or 0
  if value < min_value then return min_value end
  if value > max_value then return max_value end
  return math.floor(value)
end

local function sorted_selection(item)
  if not item.selection_anchor or item.selection_anchor == item.cursor then return nil, nil end
  return math.min(item.selection_anchor, item.cursor), math.max(item.selection_anchor, item.cursor)
end

function M.new()
  local service = { states = {}, clipboard = "" }

  local function state(id)
    id = tostring(id or "default")
    service.states[id] = service.states[id] or { id = id, value = "", cursor = 0, selection_anchor = nil }
    return service.states[id]
  end

  local function set_cursor(item, cursor, keep_selection)
    item.cursor = clamp(cursor, 0, #tostring(item.value or ""))
    if not keep_selection then item.selection_anchor = nil end
  end

  local function delete_selection(item)
    local left, right = sorted_selection(item)
    if not left then return false end
    item.value = item.value:sub(1, left) .. item.value:sub(right + 1)
    item.cursor = left
    item.selection_anchor = nil
    return true
  end

  function service.focus(id, value, cursor)
    local item = state(id)
    item.value = tostring(value or "")
    set_cursor(item, cursor == nil and #item.value or cursor, false)
    return ok(item)
  end

  function service.get(id) return ok(state(id)) end

  function service.set(id, value, cursor)
    local item = state(id)
    item.value = tostring(value or "")
    set_cursor(item, cursor == nil and math.min(item.cursor, #item.value) or cursor, item.selection_anchor ~= nil)
    return ok(item)
  end

  function service.cursorFromX(id, x, text_x, char_width, keep_selection)
    local item = state(id)
    local position = clamp(math.floor(((tonumber(x) or text_x) - (tonumber(text_x) or 0)) / (tonumber(char_width) or 6) + 0.5), 0, #item.value)
    if keep_selection and not item.selection_anchor then item.selection_anchor = item.cursor end
    set_cursor(item, position, keep_selection)
    return ok(item)
  end

  function service.insert(id, text)
    local item = state(id)
    delete_selection(item)
    text = tostring(text or "")
    item.value = item.value:sub(1, item.cursor) .. text .. item.value:sub(item.cursor + 1)
    item.cursor = item.cursor + #text
    return ok(item)
  end

  function service.backspace(id)
    local item = state(id)
    if delete_selection(item) then return ok(item) end
    if item.cursor <= 0 then return ok(item) end
    item.value = item.value:sub(1, item.cursor - 1) .. item.value:sub(item.cursor + 1)
    item.cursor = item.cursor - 1
    return ok(item)
  end

  function service.delete(id)
    local item = state(id)
    if delete_selection(item) then return ok(item) end
    if item.cursor >= #item.value then return ok(item) end
    item.value = item.value:sub(1, item.cursor) .. item.value:sub(item.cursor + 2)
    return ok(item)
  end

  function service.move(id, delta, keep_selection)
    local item = state(id)
    if keep_selection and not item.selection_anchor then item.selection_anchor = item.cursor end
    set_cursor(item, item.cursor + (tonumber(delta) or 0), keep_selection)
    return ok(item)
  end

  function service.selectAll(id)
    local item = state(id)
    item.selection_anchor = 0
    item.cursor = #item.value
    return ok(item)
  end

  function service.copy(id)
    local item = state(id)
    local left, right = sorted_selection(item)
    if left then service.clipboard = item.value:sub(left + 1, right) end
    return ok(service.clipboard)
  end

  function service.cut(id)
    local copied = service.copy(id)
    local item = state(id)
    delete_selection(item)
    return copied.ok and ok(item) or copied
  end

  function service.paste(id, text)
    return service.insert(id, text or service.clipboard or "")
  end

  function service.view(id)
    local item = state(id)
    local left, right = sorted_selection(item)
    return ok({ value = item.value, cursor = item.cursor, selection_start = left, selection_end = right })
  end

  function service.start() return ok(true) end

  return service
end

return M
