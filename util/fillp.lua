function get_pattern_bit(pattern, x, y)
  x = x % 4
  y = y % 4

  local index = ((4 * y) + x) + 1
  return pattern[index]
end

function apply_pattern_to_points(points, fillPattern)
  if not fillPattern then
    return points, {}
  end

  local fgColorPoints = {}
  local bgColorPoints = {}

  for _, p in pairs(points) do
    local x, y = p[1], p[2]
    local bit = get_pattern_bit(fillPattern.pattern, x - 0.5, y - 0.5)
    if bit == 0 then
      table.insert(fgColorPoints, p)
    elseif not fillPattern.isTransparent then
      table.insert(bgColorPoints, p)
    end
  end

  return fgColorPoints, bgColorPoints
end

function draw_pattern_points(fgColorPoints, bgColorPoints, fgLoveColor, bgLoveColor)
  love.graphics.setPointSize(1)

  love.graphics.setColor(fgLoveColor)
  love.graphics.points(fgColorPoints)

  love.graphics.setColor(bgLoveColor)
  love.graphics.points(bgColorPoints)
end
