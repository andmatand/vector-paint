function love.load()
  CANVAS_W = 61
  CANVAS_H = 101

  canvasMargin = 50
  find_best_canvas_scale()

  palette = {}
  palette[0] = {0, 0, 0}
  palette[1] = {29, 43, 83}
  palette[2] = {126, 37, 83}
  palette[3] = {0, 135, 81}
  palette[4] = {171, 82, 54}
  palette[5] = {95, 87, 79}
  palette[6] = {194, 195, 199}
  palette[7] = {255, 241, 232}
  palette[8] = {255, 0, 77}
  palette[9] = {255, 163, 0}
  palette[10] = {255, 236, 39}
  palette[11] = {0, 228, 54}
  palette[12] = {41, 173, 255}
  palette[13] = {131, 118, 156}
  palette[14] = {255, 119, 168}
  palette[15] = {255, 204, 170}

  -- make sure we get ALL the pixels
  love.graphics.setDefaultFilter('nearest', 'nearest')
  love.graphics.setLineStyle('rough')

  -- create a canvas to draw on
  canvas = love.graphics.newCanvas(CANVAS_W, CANVAS_H)

  cursor = {
    x = CANVAS_W / 2,
    y = CANVAS_H / 2,
    tool = 'draw',
    color = 9,
  }

  polygons = {}
  polygons[1] = {
    color = 8,
    points = {
      {x = 10, y = 8},
      {x = 20, y = 10},
      {x = 15, y = 29},
      {x = 30, y = 44},
      {x = 14, y = 53}
    }
  }

  -- draw on the canvas
  render_polygons()
end

function love.keypressed(key)
  if love.keyboard.isDown('lctrl') then
    if key == 'q' then
      love.event.quit()
    end
  end

  if key == 'f11' then
    local fs = love.window.getFullscreen()

    love.window.setFullscreen(not fs, 'desktop')
  end

  find_best_canvas_scale()
end

function love.resize()
  find_best_canvas_scale()
end

function get_window_height()
  local w, h = love.window.getMode()
  return h
end

function find_best_canvas_scale()
  local scale = 1

  while true do
    scale = scale + 1

    local w = CANVAS_W * scale
    if w + (canvasMargin * 3) >= love.graphics.getWidth() then
      break
    end

    local h = (CANVAS_H * scale) + (canvasMargin * 2)
    if h >= love.graphics.getHeight() then
      break
    end
  end

  if canvasScale ~= scale -1 then
    canvasScale = scale - 1
    print('canvas scale: ' .. canvasScale)
  end
end

function find_bounds(points)
  local x1 = CANVAS_W - 1
  local x2 = 0
  local y1 = CANVAS_H - 1
  local y2 = 0
  for i, point in pairs(points) do
    if point.x < x1 then
      x1 = point.x
    elseif point.x > x2 then
      x2 = point.x
    end

    if point.y < y1 then
      y1 = point.y
    elseif point.y > y2 then
      y2 = point.y
    end
  end

  return x1, x2, y1, y2
end

function min(a, b)
  if a < b then
    return a
  else
    return b
  end
end

function max(a, b)
  if a > b then
    return a
  else
    return b
  end
end

function find_intersections(points, y)
  local xlist = {}
  local j = #points

  for i, a in pairs(points) do
    local b = points[j]

    if (a.y < y and b.y >= y) or (b.y < y and a.y >= y) then
      local x = a.x + (((y - a.y) / (b.y - a.y)) * (b.x - a.x))
      x = math.floor(x)

      table.insert(xlist, x)
    end

    j = i
  end

  return xlist
end

function sort(t)
  for i = 2, #t do
    local j = i
    while j > 1 and t[j - 1] > t[j] do
      -- swap j and j - 1
      t[j - 1], t[j] = t[j], t[j - 1]
      j = j - 1
    end
  end
end

function fillpoly(points, color)
  -- debug: draw a line between the first two points of the polygon
  --love.graphics.setColor(palette[10])
  --love.graphics.line(
  --  points[1].x, points[1].y,
  --  points[2].x, points[2].y)

  love.graphics.setColor(palette[color])

  -- find the highest y
  local x1, x2, y1, y2 = find_bounds(points)

  for y = y2, y1, -1 do
    -- find intersecting nodes
    local xlist = find_intersections(points, y)
    sort(xlist)

    for i = 1, #xlist - 1, 2 do
      love.graphics.line(xlist[i], y, xlist[i + 1], y)
    end
  end

  -- debug: draw the points of the polygon
  for i, p in pairs(points) do
    love.graphics.setColor(255, 255, 255)
    love.graphics.points(p.x, p.y)
  end

end

function render_polygons()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0)

  for i, poly in pairs(polygons) do
    fillpoly(poly.points, poly.color)
  end

  love.graphics.setCanvas()
end

function draw_canvas()
  love.graphics.push()

  love.graphics.scale(canvasScale, canvasScale)

  love.graphics.draw(canvas, canvasPos.x, canvasPos.y)

  love.graphics.pop()
end

function draw_status()
  love.graphics.setColor(255, 255, 255)
  local x = (CANVAS_W * canvasScale) + (canvasMargin * 2)
  local y = canvasMargin
  love.graphics.print('current tool: ' .. cursor.tool, x, y)
end

function draw_cursor()
  love.graphics.push()

  love.graphics.scale(canvasScale, canvasScale)
  love.graphics.setPointSize(canvasScale)

  local centerX = canvasPos.x + cursor.x + 0.5
  local centerY = canvasPos.y + cursor.y + 0.5

  local points = {
    {centerX, centerY - 1},
    {centerX - 1, centerY},
    {centerX + 1, centerY},
    {centerX, centerY + 1},
  }

  love.graphics.points(points)
    
  love.graphics.pop()
end

function love.update()
  canvasPos = {
    x = canvasMargin / canvasScale,
    y = canvasMargin / canvasScale
  }
end

function love.draw()
  -- clear the screen
  love.graphics.setCanvas()
  love.graphics.clear(10, 10, 10)

  -- draw the partial outline of the polygon in progress
  --draw_wip()

  -- draw the canvas
  draw_canvas()

  -- draw the cursor
  draw_cursor()

  -- draw status stuff
  draw_status()
end
