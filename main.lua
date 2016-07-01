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
    vx = 0,
    vy = 0,
    tool = 'draw',
    color = 9,
    selectedPolygons = {},
    selectedPoints = {}
  }

  drawingPoints = {}

  selectionFlash = {
    time = 0,
    isOn = true
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

  undoHistory = {}
end

function copy_table(t)
  local t2 = {}

  for k, v in pairs(t) do
    if type(v) == 'table' then
      t2[k] = copy_table(v)
    else
      t2[k] = v
    end
  end

  return t2
end

function update_cursor()
  local delta = .25
  local friction = .80

  if not cursor.fineMode then
    if love.keyboard.isDown('left') then
      cursor.vx = cursor.vx - delta
    elseif love.keyboard.isDown('right') then
      cursor.vx = cursor.vx + delta
    elseif love.keyboard.isDown('up') then
      cursor.vy = cursor.vy - delta
    elseif love.keyboard.isDown('down') then
      cursor.vy = cursor.vy + delta
    end
  end

  -- apply cursor velocity
  cursor.x = cursor.x + cursor.vx
  cursor.y = cursor.y + cursor.vy

  -- apply friction
  cursor.vx = cursor.vx * friction
  cursor.vy = cursor.vy * friction

  -- enforce cursor boundaries
  if cursor.x < 0 then
    cursor.x = 0
  elseif cursor.x > CANVAS_W - 1 then
    cursor.x = CANVAS_W - 1
  end
  if cursor.y < 0 then
    cursor.y = 0
  elseif cursor.y > CANVAS_H - 1 then
    cursor.y = CANVAS_H - 1
  end

  cursor.hoveredPolygon = nil
  cursor.hoveredPoint = nil

  if cursor.tool == 'select polygon' then
    -- find the top polygon under the cursor
    local topPoly = find_top_poly(cursor)
    if topPoly then
      cursor.hoveredPolygon = topPoly
    end
  elseif cursor.tool == 'select point' then
    -- find the top point under the cursor
    local point, poly = find_nearest_point(cursor)
    if point then
      cursor.hoveredPoint = point
      cursor.hoveredPoly = poly
    end
  end

  if love.timer.getTime() > selectionFlash.time + .5 then
    selectionFlash.time = love.timer.getTime()
    selectionFlash.isOn = not selectionFlash.isOn
  end
end

function reset_selection_flash()
  selectionFlash.time = love.timer.getTime()
  selectionFlash.isOn = true
end

function find_top_poly(point)
  for i = #polygons, 1, -1 do
    local poly = polygons[i]

    if point_in_polygon(point, poly) then
      return poly
    end
  end
end

function manhattan_distance(a, b)
  return math.abs(a.x - b.x) + math.abs(b.y - a.y)
end

function find_nearest_point(cursorPos)
  local maxDist = 5
  local closest

  for i, poly in pairs(polygons) do
    for j, point in pairs(poly.points) do
      local dist = manhattan_distance(cursorPos, point)

      if dist <= maxDist then
        if closest == nil or dist < closest.dist then
          closest = {
            dist = dist,
            point = point,
            poly = poly,
            index = j
          }
        end
      end
    end
  end

  if closest then
    return closest.point, closest.poly, closest.index
  end
end

function love.keypressed(key)
  -- toggle cursor fine-movement mode
  if key == 'f' then
    cursor.fineMode = not cursor.fineMode

    if not cursor.fineMode then
      -- halt the cursor's current momentum
      cursor.vx = 0
      cursor.vy = 0
    end
  end

  if cursor.fineMode then
    if key == 'left' then
      cursor.x = cursor.x - 1
    elseif key == 'right' then
      cursor.x = cursor.x + 1
    elseif key == 'up' then
      cursor.y = cursor.y - 1
    elseif key == 'down' then
      cursor.y = cursor.y + 1
    end
  end

  if love.keyboard.isDown('lctrl') or love.keyboard.isDown('rctrl') then
    if key == 'q' then
      love.event.quit()
    end
  end

  if key == 'f11' then
    local fs = love.window.getFullscreen()

    love.window.setFullscreen(not fs, 'desktop')
    find_best_canvas_scale()
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

  if key == 'z' or key == 'space' then
    push_primary_button()
  elseif key == 'return' then
    push_secondary_button()
  end

  if key == 'f5' or (love.keyboard.isDown('lctrl') and key == 'r') then
    -- force re-render
    render_polygons()
  end

  if key == 'd' then
    cursor.tool = 'draw'
    cursor.selectedPolygons = {}
    cursor.selectedPoints = {}
  elseif key == 's' then
    cursor.tool = 'select polygon'
  elseif key == 'p' then
    cursor.tool = 'select point'
  end

  if key == 'delete' or key == 'backspace' then
    save_undo_state()
    polygons = remove_values_from_table(cursor.selectedPolygons, polygons)
    cursor.selectedPolygons = {}
  end

  if key == 'u' then
    undo()
  end
end

function push_primary_button()
  local shiftIsDown = (love.keyboard.isDown('lshift') or
    love.keyboard.isDown('rshift'))

  if cursor.tool == 'draw' then
    draw_point()
  elseif cursor.tool == 'select polygon' then
    if cursor.hoveredPolygon then
      if shiftIsDown then
        table.insert(cursor.selectedPolygons, cursor.hoveredPolygon)
      else
        cursor.selectedPolygons = {cursor.hoveredPolygon}
      end
    else
      cursor.selectedPolygons = {}
    end
  elseif cursor.tool == 'select point' then
    if cursor.hoveredPoint then
      if shiftIsDown then
        table.insert(cursor.selectedPoints, cursor.hoveredPoint)
      else
        cursor.selectedPoints = {cursor.hoveredPoint}
      end
    else
      cursor.selectedPoints = {}
    end
  end
end

function push_secondary_button()
  if cursor.tool == 'draw' then
    finalize_drawing_points()
  end
end

function remove_values_from_table(values, t)
  local t2 = {}
  for i, v in pairs(t) do
    local valueIsOkay = true
    for j, badValue in pairs(values) do
      if badValue == v then
        valueIsOkay = false
        break
      end
    end

    if valueIsOkay then
      table.insert(t2, v)
    end
  end

  return t2
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
    if mouseIsOnCanvas then
      push_primary_button()
      return
    end

    local color = get_color_under_mouse(x, y)
    if color ~= nil then
      cursor.color = color
    end
  end

  if button == 2 then
    if mouseIsOnCanvas then
      push_secondary_button()
      return
    end
  end
end

function finalize_drawing_points()
  if #drawingPoints < 3 then
    return
  end

  -- finalize the WIP polygon
  table.insert(polygons,
    {
      points = drawingPoints,
      color = cursor.color
    })

  -- clear the WIP points
  drawingPoints = {}

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

function point_in_polygon(point, poly)
  local points = poly.points
  local x = point.x
  local y = point.y

  local i = 1
  local j = #points
  local c = false

  while i <= #points do
    if ( ((points[i].y > y) ~= (points[j].y > y)) and
          (x < (points[j].x - points[i].x) * (y - points[i].y) /
            (points[j].y - points[i].y) + points[i].x
          )
       ) then
       c = not c
    end

    j = i
    i = i + 1
  end

  return c
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
function fillpoly(poly, rgba, outline)
  love.graphics.setColor(rgba)
  love.graphics.setPointSize(1)
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

      if outline then
        love.graphics.points(x1, y, x2, y)
      else
        love.graphics.line(x1, y, x2, y)
      end
    end
  end
end

function render_polygons()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0)

  for _, poly in pairs(polygons) do
    fillpoly(poly, palette[poly.color])
  end

  love.graphics.setCanvas()
end

function draw_tool()
  love.graphics.setCanvas(canvas)

  if #drawingPoints > 0 then
    -- draw the WIP polygon
    draw_wip_poly()
  end

  -- draw a lowlight overlay on the polygon we are hovering over
  if cursor.hoveredPolygon then
    fillpoly(cursor.hoveredPolygon, {255, 255, 255, 100})
  end

  -- draw a lowlight overlay on the point we are hovering over
  if cursor.hoveredPoint then
    love.graphics.setPointSize(5)
    love.graphics.setColor(255, 255, 255, 100)
    love.graphics.circle(
      'line', cursor.hoveredPoint.x, cursor.hoveredPoint.y, 2)
  end

  ---- draw a highlight overlay on the selected polygons
  --for _, poly in pairs(cursor.selectedPolygons) do
  --  if selectionFlash.isOn then
  --    fillpoly(poly, {255, 255, 255, 200})
  --  end
  --end
  -- draw an outline around the selected polygons
  if selectionFlash.isOn then
    for _, poly in pairs(cursor.selectedPolygons) do
      fillpoly(poly, {255, 255, 255, 200}, true)
    end
  end

  -- draw a highlight overlay on the point we are hovering over
  if not selectionFlash.isOn then
    love.graphics.setPointSize(5)
    love.graphics.setColor(255, 255, 255, 200)
    for _, point in pairs(cursor.selectedPoints) do
      love.graphics.circle('line', point.x, point.y, 1)
    end
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

function point_to_string(point)
  return '(' .. point.x .. ', ' .. point.y .. ')'
end

function draw_status()
  love.graphics.setColor(255, 255, 255)
  local x = (CANVAS_W * canvasScale) + (canvasMargin * 2)
  local y = canvasMargin
  local lineh = 14

  love.graphics.print('FPS: ' .. love.timer.getFPS(), x + 115, y)

  local cursorDisplayPoint = {
    x = math.floor(cursor.x),
    y = math.floor(cursor.y)
  }
  love.graphics.print(point_to_string(cursorDisplayPoint), x, y)

  y = y + lineh
  love.graphics.print('current tool: ' .. cursor.tool, x, y)

  if cursor.fineMode then
    y = y + lineh
    love.graphics.print('fine cursor movement enabled', x, y)
  end

  local selectedPolys
  if #drawingPoints > 0 then
    selectedPolys = {{points = drawingPoints}}
  else
    selectedPolys = cursor.selectedPolygons
  end

  if selectedPolys then
    y = 300
    if #selectedPolys == 1 then
      love.graphics.print("selected polygon's points: ", x, y)
      for i, point in pairs(selectedPolys[1].points) do
        y = y + lineh
        love.graphics.print(i .. ': ' .. point_to_string(point), x, y)
      end
    elseif #selectedPolys > 1 then
      love.graphics.print(
        'selected polygons: ' .. #selectedPolys, x, y)
    end
  end

  if cursor.selectedPoints then
    love.graphics.print('selected point(s): ', x, y)
    for _, point in pairs(cursor.selectedPoints) do
      y = y + lineh
      love.graphics.print(point_to_string(point), x, y)
    end
  end
end

function draw_cursor()
  love.graphics.push()

  love.graphics.scale(canvasScale, canvasScale)
  love.graphics.setPointSize(canvasScale)

  local centerX = canvasPos.x + math.floor(cursor.x) + 0.5
  local centerY = canvasPos.y + math.floor(cursor.y) + 0.5

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

function draw_point()
  save_undo_state()

  table.insert(drawingPoints,
    {
      x = math.floor(cursor.x),
      y = math.floor(cursor.y)
    })
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

function draw_wip_poly()
  local points = {}

  for _, point in pairs(drawingPoints) do
    table.insert(points, point)
  end
  table.insert(points, cursor)

  love.graphics.setLineWidth(1)
  love.graphics.setPointSize(1)

  for i = 1, #points - 1 do
    local a = points[i]
    local b = points[i + 1]

    love.graphics.setColor(palette[cursor.color])
    love.graphics.line(a.x, a.y, b.x, b.y)

    -- draw a handle on this point
    love.graphics.setColor(255, 255, 255)
    love.graphics.points(a.x, a.y)
  end
end

function undo()
  -- pop the most recent saved state off the undoHistory
  local state = table.remove(undoHistory)

  if state then
    -- apply the saved state
    polygons = state.polygons
    drawingPoints = state.drawingPoints
  else
    print('no undo history remaining')
  end
end

function save_undo_state()
  local state = {}
  state.polygons = copy_table(polygons)
  state.drawingPoints = copy_table(drawingPoints)

  table.insert(undoHistory, state)
end

function love.update()
  update_cursor()
  update_palette()
end

function love.draw()
  -- clear the screen
  love.graphics.setCanvas()
  love.graphics.clear(10, 10, 10)

  -- render all the polygons to the canvas
  render_polygons()

  -- draw the current tool overlays
  draw_tool()

  -- draw the canvas
  draw_canvas()

  -- draw status stuff
  draw_status()
  draw_palette()

  -- draw the cursor
  draw_cursor()
end
