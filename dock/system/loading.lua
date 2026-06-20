local M = {}

local spinner_frames = { "|", "/", "-", "\\" }

local function frame_index(tick)
  tick = tonumber(tick)
  if not tick then
    tick = math.floor((os.clock and os.clock() or 0) * 8)
  end
  return (math.floor(tick) % #spinner_frames) + 1
end

function M.spinner(tick)
  return spinner_frames[frame_index(tick)]
end

function M.text(label, tick)
  return tostring(label or "Loading") .. " " .. M.spinner(tick)
end

function M.progress(percent, width)
  percent = math.max(0, math.min(100, tonumber(percent) or 0))
  width = math.max(3, tonumber(width) or 12)
  local filled = math.floor((percent / 100) * width)
  return string.rep("#", filled) .. string.rep("-", width - filled) .. " " .. string.format("%.2f%%", percent)
end

return M
