function love.load()
  CANVAS_W = 61
  CANVAS_H = 101

  canvasMargin = 50
  find_best_canvas_scale()

  love.keyboard.setKeyRepeat(true)

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

  -- create a table to store positions of palette color boxes in the UI
  paletteBox = {}

  -- make sure we get ALL the pixels
  love.graphics.setDefaultFilter('nearest', 'nearest')
  love.graphics.setLineStyle('rough')

  -- create a canvas to draw on
  canvas = love.graphics.newCanvas(CANVAS_W, CANVAS_H)

  cursor = {
    x = math.floor(CANVAS_W / 2),
    y = math.floor(CANVAS_H / 2),
    tool = 'draw',
    color = 9,
  }

  wip = {
    points = {}
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
    find_best_canvas_scale()
  end

  if key == 'left' then
    if cursor.x > 0 then
      cursor.x = cursor.x - 1
    end
  elseif key == 'right' then
    if cursor.x < CANVAS_W - 1 then
      cursor.x = cursor.x + 1
    end
  elseif key == 'up' then
    if cursor.y > 0 then
      cursor.y = cursor.y - 1
    end
  elseif key == 'down' then
    if cursor.y < CANVAS_H - 1 then
      cursor.y = cursor.y + 1
    end
  end

  if key == '1' then
    if cursor.color > 0 then
      cursor.color = cursor.color - 1
    end
  elseif key == '2' then
    if cursor.color < #palette then
      cursor.color = cursor.color + 1
    end
  end

  if cursor.tool == 'draw' then
    if key == 'z' or key == 'space' then
      add_point()
    elseif key == 'return' then
      finalize_wip()
    end
  end

  if key == 'f5' or love.keyboard.isDown('lctrl') and key == 'r' then
    -- force re-render
    render_polygons()
  end
end

function love.mousemoved(x, y)
  -- transform the coordinates to canvas-space
  x = (x / canvasScale) - canvasPos.x
  y = (y / canvasScale) - canvasPos.y

  -- lock the coordinates to the canvas pixel grid
  x = math.floor(x)
  y = math.floor(y)

  -- if the cursor is inside the bounds of the canvas
  if x >= 0 and x < CANVAS_W and y >= 0 and y < CANVAS_H then
    -- move the cursor to the mouse
    cursor.x = x
    cursor.y = y

    -- hide the OS mouse cursor
    love.mouse.setVisible(false)
    mouseIsOnCanvas = true
  else
    -- show the OS mouse cursor
    love.mouse.setVisible(true)
    mouseIsOnCanvas = false
  end
end

function get_color_under_mouse(x, y)
  for i, box in pairs(paletteBox) do
    if x >= box.x and x < box.x + palettePos.colorW and
       y >= box.y and y < box.y + palettePos.colorH then
      return i
    end
  end
end

function love.mousepressed(x, y, button)
  if button == 1 then
    if cursor.tool == 'draw' and mouseIsOnCanvas then
      add_point()
    end

    local color = get_color_under_mouse(x, y)
    if color ~= nil then
      cursor.color = color
    end
  end

  if button == 2 then
    if cursor.tool == 'draw' and mouseIsOnCanvas then
      finalize_wip()
    end
  end
end

function finalize_wip()
  -- finalize the WIP polygon
  table.insert(polygons,
    {
      points = wip.points,
      color = cursor.color
    })

  -- clear the WIP points
  wip.points = {}

  -- re-render the canvas with the new polygon
  render_polygons()
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

  canvasPos = {
    x = canvasMargin / canvasScale,
    y = canvasMargin / canvasScale
  }
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

function fillpoly(poly)
  love.graphics.setColor(palette[poly.color])
  love.graphics.setLineWidth(1)

  -- find the highest y
  local x1, x2, y1, y2 = find_bounds(poly.points)

  for y = y2, y1, -1 do
    -- find intersecting nodes
    local xlist = find_intersections(poly.points, y)
    sort(xlist)

    for i = 1, #xlist - 1, 2 do
      local x1 = math.floor(xlist[i])
      local x2 = math.ceil(xlist[i + 1])
      love.graphics.line(x1, y, x2, y)
    end
  end

  if poly.isSelected then
    -- draw dots on the points
    love.graphics.setPointSize(1)
    for i, p in pairs(poly.points) do
      love.graphics.setColor(255, 255, 255)
      love.graphics.points(p.x, p.y)
    end
  end
end

function render_polygons()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0)

  for _, poly in pairs(polygons) do
    fillpoly(poly)
  end

  love.graphics.setCanvas()
end

function draw_canvas()
  love.graphics.push()

  love.graphics.scale(canvasScale, canvasScale)

  love.graphics.setColor(255, 255, 255)
  love.graphics.draw(canvas, canvasPos.x, canvasPos.y)

  love.graphics.pop()
end

function draw_status()
  love.graphics.setColor(255, 255, 255)
  local x = (CANVAS_W * canvasScale) + (canvasMargin * 2)
  local y = canvasMargin
  local lineh = 14

  love.graphics.print('(' .. cursor.x .. ', ' .. cursor.y .. ')', x, y)

  love.graphics.print('current tool: ' .. cursor.tool, x, y + lineh * 2)

  if #wip.points > 0 then
    love.graphics.print('points: ' .. #wip.points, x, y + lineh * 3)
  end
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

  love.graphics.setColor(255, 255, 255)
  love.graphics.points(points)
    
  love.graphics.pop()
end

function add_point()
  table.insert(wip.points, {x = cursor.x, y = cursor.y})
end

function update_palette()
  palettePos = {
    x = (CANVAS_W * canvasScale) + (canvasMargin * 2),
    y = (canvasMargin * 3),
    colorW = 40,
    colorH = 32,
    outlineW = 4
  }

  local i = 0
  for y = 0, (palettePos.colorH * 4) - 1, palettePos.colorH do
    for x = 0, (palettePos.colorW * 4) - 1, palettePos.colorW do
      paletteBox[i] = {
        x = palettePos.x + x,
        y = palettePos.y + y
      }

      i = i + 1
      if i > #palette then
        return
      end
    end
  end
end

function draw_palette()
  for i, box in pairs(paletteBox) do
    local x = box.x
    local y = box.y

    love.graphics.setColor(palette[i])
    love.graphics.rectangle('fill', x, y, palettePos.colorW, palettePos.colorH)
  end

  -- outline the currently selected color
  local lineW = palettePos.outlineW
  love.graphics.setLineWidth(palettePos.outlineW)
  love.graphics.setColor(0, 0, 0)
  love.graphics.rectangle('line',
    paletteBox[cursor.color].x + (lineW / 2),
    paletteBox[cursor.color].y + (lineW / 2),
    palettePos.colorW - lineW,
    palettePos.colorH - lineW)

  love.graphics.setColor(255, 255, 255)
  love.graphics.rectangle('line',
    paletteBox[cursor.color].x - (lineW / 2),
    paletteBox[cursor.color].y - (lineW / 2),
    palettePos.colorW + lineW,
    palettePos.colorH + lineW)
end

function draw_tool()
  love.graphics.push()
  love.graphics.scale(canvasScale, canvasScale)
  love.graphics.translate(canvasPos.x, canvasPos.y)

  if cursor.tool == 'draw' then
    -- draw the partial polygon outline
    love.graphics.setLineWidth(1)
    for i = 1, #wip.points do
      local a = wip.points[i]
      local b
      if i < #wip.points then
        b = wip.points[i + 1]
      else
        b = {x = cursor.x, y = cursor.y}
      end

      love.graphics.setColor(palette[cursor.color])
      love.graphics.line(a.x, a.y, b.x, b.y)

      -- draw a handle on this point
      love.graphics.setColor(255, 255, 255)
      love.graphics.points(a.x, a.y)
    end
  end

  love.graphics.pop()
end

function update_input()
  --if love.keyboard.isDown('left') then
  --  cursor.x = cursor.x - 1
  --end
end

function love.update()
  update_input()
  update_palette()
end

function love.draw()
  -- clear the screen
  love.graphics.setCanvas()
  love.graphics.clear(10, 10, 10)

  -- draw the current tool's operation
  draw_tool()

  -- draw the canvas
  draw_canvas()

  -- draw status stuff
  draw_status()
  draw_palette()

  -- draw the cursor
  draw_tool()
  draw_cursor()
end
