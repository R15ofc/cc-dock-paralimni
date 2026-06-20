local M = {}

local function clamp(value, min_value, max_value)
  value = tonumber(value) or 0
  if value < min_value then return min_value end
  if value > max_value then return max_value end
  return math.floor(value)
end

local function rect(gpu, x, y, width, height, color)
  if not gpu or width <= 0 or height <= 0 then return end
  x, y, width, height = math.floor(x), math.floor(y), math.floor(width), math.floor(height)
  if gpu.filledRectangle and pcall(gpu.filledRectangle, x, y, width, height, color) then return end
  local red = math.floor(color / 65536) % 256
  local green = math.floor(color / 256) % 256
  local blue = color % 256
  if gpu.fillRect then pcall(gpu.fillRect, x, y, width, height, red, green, blue) end
end

function M.metrics(total, visible, offset, x, y, height)
  total = math.max(0, tonumber(total) or 0)
  visible = math.max(1, tonumber(visible) or 1)
  height = math.max(1, tonumber(height) or 1)
  offset = clamp(offset, 0, math.max(0, total - visible))
  if total <= visible then
    return { enabled = false, x = x, y = y, h = height, offset = offset, max = 0 }
  end
  local thumb_h = math.max(8, math.floor(height * (visible / total)))
  local track_h = math.max(1, height - thumb_h)
  local thumb_y = y + math.floor(track_h * (offset / math.max(1, total - visible)))
  return { enabled = true, x = x, y = y, h = height, thumb_y = thumb_y, thumb_h = thumb_h, offset = offset, max = total - visible }
end

function M.draw(gpu, metrics, colors)
  if not metrics or not metrics.enabled then return end
  colors = colors or {}
  rect(gpu, metrics.x, metrics.y, 4, metrics.h, colors.track or 0xD0D4DA)
  rect(gpu, metrics.x, metrics.thumb_y, 4, metrics.thumb_h, colors.thumb or 0x737A84)
end

function M.offsetFromY(metrics, pointer_y)
  if not metrics or not metrics.enabled then return 0 end
  local track_h = math.max(1, metrics.h - metrics.thumb_h)
  local relative = clamp((tonumber(pointer_y) or metrics.y) - metrics.y - math.floor(metrics.thumb_h / 2), 0, track_h)
  return clamp(math.floor((relative / track_h) * metrics.max + 0.5), 0, metrics.max)
end

return M
