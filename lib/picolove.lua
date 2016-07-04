-- These functions were taken from picolove
-- <https://github.com/ftsf/picolove>

-- Copyright (c) 2015 Jez Kabanov <thesleepless@gmail.com>
-- 
-- This software is provided 'as-is', without any express or implied
-- warranty. In no event will the authors be held liable for any damages
-- arising from the use of this software.
-- 
-- Permission is granted to anyone to use this software for any purpose,
-- including commercial applications, and to alter it and redistribute it
-- freely, subject to the following restrictions:
-- 
-- 1. The origin of this software must not be misrepresented; you must not
--    claim that you wrote the original software. If you use this software
--    in a product, an acknowledgement in the product documentation would be
--    appreciated but is not required.
-- 2. Altered source versions must be plainly marked as such, and must not be
--    misrepresented as being the original software.
-- 3. This notice may not be removed or altered from any source distribution.

local picolove = {}

local lineMesh = love.graphics.newMesh(128, "points")

function flr(n)
  return math.floor(n)
end

function picolove.line(x0,y0,x1,y1, loveColor)
  love.graphics.setPointSize(1)
  if loveColor then
    love.graphics.setColor(loveColor)
  end

  if x0 ~= x0 or y0 ~= y0 or x1 ~= x1 or y1 ~= y1 then
    warning("line has NaN value")
    return
  end

  x0 = flr(x0)
  y0 = flr(y0)
  x1 = flr(x1)
  y1 = flr(y1)


  local dx = x1 - x0
  local dy = y1 - y0
  local stepx, stepy

  local points = {{x0,y0}}

  if dx == 0 then
    -- simple case draw a vertical line
    points = {}
    if y0 > y1 then y0,y1 = y1,y0 end
    for y=y0,y1 do
      table.insert(points,{x0,y})
    end
  elseif dy == 0 then
    -- simple case draw a horizontal line
    points = {}
    if x0 > x1 then x0,x1 = x1,x0 end
    for x=x0,x1 do
      table.insert(points,{x,y0})
    end
  else
    if dy < 0 then
      dy = -dy
      stepy = -1
    else
      stepy = 1
    end

    if dx < 0 then
      dx = -dx
      stepx = -1
    else
      stepx = 1
    end

    if dx > dy then
      local fraction = dy - bit.rshift(dx, 1)
      while x0 ~= x1 do
        if fraction >= 0 then
          y0 = y0 + stepy
          fraction = fraction - dx
        end
        x0 = x0 + stepx
        fraction = fraction + dy
        table.insert(points,{flr(x0),flr(y0)})
      end
    else
      local fraction = dx - bit.rshift(dy, 1)
      while y0 ~= y1 do
        if fraction >= 0 then
          x0 = x0 + stepx
          fraction = fraction - dy
        end
        y0 = y0 + stepy
        fraction = fraction + dx
        table.insert(points,{flr(x0),flr(y0)})
      end
    end
  end
  --lineMesh:setVertices(points)
  --lineMesh:setDrawRange(1,#points)
  --love.graphics.draw(lineMesh)
  for i = 1, #points do
    local p = points[i]
    love.graphics.points(p[1] + 0.5, p[2] + 0.5)
  end
end

return picolove
