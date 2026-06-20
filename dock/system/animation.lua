local M = {}

local function clamp(value, min_value, max_value)
  value = tonumber(value) or min_value
  if value < min_value then return min_value end
  if value > max_value then return max_value end
  return value
end

function M.dockBounce(frame, loading, notification_age)
  frame = tonumber(frame) or 0
  if loading then return math.floor(1 + math.abs(math.sin(frame * 0.42)) * 5) end
  if notification_age then
    local age = clamp(notification_age, 0, 2.2)
    local strength = 1 - (age / 2.2)
    return math.floor(math.abs(math.sin(frame * 0.75)) * 5 * strength)
  end
  return 0
end

function M.timerInterval(active)
  return active and 0.08 or 0.25
end

return M
