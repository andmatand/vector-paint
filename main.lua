local utf8 = require('utf8')
local bit = require('bit')
local picolove = require('lib.picolove')
require('class.colorflash')

function love.load()
  CANVAS_W = 61
  CANVAS_H = 101
  love.filesystem.setIdentity('vector-paint')
  love.graphics.setFont(love.graphics.newFont(14))

  POINT_MIN_X = 0
  POINT_MAX_X = 255
  POINT_MIN_Y = -1
  POINT_MAX_Y = 254

  MAX_POLYGONS = 256
  MAX_POLYGON_POINTS = 256

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

  -- create a canvas for the tools overlay
  toolsCanvas = love.graphics.newCanvas(CANVAS_W, CANVAS_H)

  cursor = {
    x = math.floor(CANVAS_W / 2),
    y = math.floor(CANVAS_H / 2),
    vx = 0,
    vy = 0,
    tool = 'draw',
    color = 9,
    isVisible = true
  }

  cursor.flash = ColorFlash.new(.25, {
    palette[0],
    palette[5],
    palette[6],
    palette[7]
  })

  selectedPolygons = {}
  selectedPoints = {}

  drawingPoints = {}

  hoverFlash = ColorFlash.new(.25, {
    {255, 85, 255},
    {0, 0, 0},
    {255, 255, 255, 0}
  })

  selectionFlash = ColorFlash.new(.5, {
    {255, 255, 255, 200},
    {0, 0, 0, 200},
    {255, 255, 255, 0}
  })

  mouseOnlyMode = true

  polygons = {}

  undoHistory = {}

  currentFilename = ''

  render_polygons()
end

function get_painting_data()
  -- Potentially smaller format if I end up needing more space:
  -- 
  -- POLYGON FORMAT
  --    bits  | description
  --   =====================
  --        6 | point count - 3 (i.e. 0 is considered to mean 3 points)
  --        4 | color
  --   to end | 3 or more POINTs
  --
  -- POINT FORMAT
  --    bits | description
  --   =====================
  --       6 | x
  --       7 | y

  local bytes = {}

  -- add each polygon
  for i = 1, #polygons do
    local poly = polygons[i]

    table.insert(bytes, #poly.points) -- point count
    table.insert(bytes, poly.color)   -- color

    -- add each point
    for j = 1, #poly.points do
      local point = poly.points[j]
      table.insert(bytes, point.x)
      table.insert(bytes, point.y + 1) -- add 1 to y to allow -1 without sign
    end
  end

  local hex = ''
  for i = 1, #bytes do
    hex = hex .. bit.tohex(bytes[i], 2)
  end

  return hex
end

function save_painting(filename)
  local data = get_painting_data()

  local success = love.filesystem.write(filename, data)

  if success then
    print('saved to ' .. love.filesystem.getSaveDirectory() .. '/' .. filename)
  else
    love.window.showMessageBox('nooooo', 'ERROR SAVING :(', 'error')
  end
end

function load_painting(filename)
  local data = love.filesystem.read(filename)

  -- parse and apply the painting data
  parse_painting_data(data)
end

function create_painting_reader(data)
  local obj = {
    i = 1,
    data = data,

    get_next_byte = function(self)
      local byte = ('0x' .. string.sub(self.data, self.i, self.i + 1)) + 0
      self.i = self.i + 2
      return byte
    end,

    is_at_end = function(self)
      return (self.i > #data)
    end
  }

  return obj
end

function parse_painting_data(data)
  if #data == 0 then
    love.window.showMessageBox('hey!', 'that file is empty; nothing to load!')
    return
  end

  save_undo_state()

  -- clear the existing painting
  polygons = {}
  selectedPolygons = {}
  selectedPoints = {}
  --undoHistory = {}

  local reader = create_painting_reader(data)

  -- read each polygon
  repeat
    local polygon = {
      points = {}
    }

    -- read the point count
    local pointCount = reader:get_next_byte()

    -- read the color
    polygon.color = reader:get_next_byte()

    -- read each point
    for i = 1, pointCount do
      local x = reader:get_next_byte()
      local y = reader:get_next_byte()

      -- adjust y back to its actual value since it is saved 1 higher than its
      -- actual value to allow for -1 without needing a sign bit
      y = y - 1

      table.insert(polygon.points, {x = x, y = y})
    end

    table.insert(polygons, polygon)
  until reader:is_at_end()

  -- re-render all polygons
  render_polygons()
end

function shallow_copy_table(t)
  local t2 = {}

  for k, v in pairs(t) do
    t2[k] = v
  end

  return t2
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
  cursor.flash:update()
  selectionFlash:update()
  hoverFlash:update()

  local delta = .25
  local friction = .80

  if not mouseOnlyMode then
    cursor.isVisible = true

    if not cursor.fineMode and cursor.tool ~= 'move' then
      if love.keyboard.isDown('left') then
        cursor.vx = cursor.vx - delta
      end
      if love.keyboard.isDown('right') then
        cursor.vx = cursor.vx + delta
      end
      if love.keyboard.isDown('up') then
        cursor.vy = cursor.vy - delta
      end
      if love.keyboard.isDown('down') then
        cursor.vy = cursor.vy + delta
      end
    end

    -- apply cursor velocity
    cursor.x = cursor.x + cursor.vx
    cursor.y = cursor.y + cursor.vy

    -- apply friction
    cursor.vx = cursor.vx * friction
    cursor.vy = cursor.vy * friction
  end

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

  if cursor.isVisible then
    if cursor.tool == 'select polygon' then
      -- find the top polygon under the cursor
      local topPoly = find_top_poly(cursor)
      if topPoly then
        cursor.hoveredPolygon = topPoly
      end
    elseif cursor.tool == 'select point' then
      -- find the top point under the cursor
      local point, poly = find_nearest_point(cursor)
      if poly then
        cursor.hoveredPoint = {
          point = point,
          poly = poly
        }
        cursor.hoveredPoly = poly
      end
    end
  end
end

function point_on_line(point, a, b)
  local dist1 = distance(a, point) + distance(point, b)
  local dist2 = distance(a, b)

  -- compensate for floating point inaccuracy
  if math.abs(dist1 - dist2) <= .025 then
    return true
  end
end

function points_are_equal(a, b)
  if a.x == b.x and a.y == b.y then
    return true
  end
end

function find_top_poly(point)
  for i = #polygons, 1, -1 do
    local poly = polygons[i]

    if #poly.points == 1 then
      if points_are_equal(point, poly.points[1]) then
        return poly
      end
    elseif #poly.points == 2 then
      if point_on_line(point, poly.points[1], poly.points[2]) then
        return poly
      end
    else
      if point_in_polygon(point, poly) then
        return poly
      end
    end
  end
end

function distance(a, b)
  return math.sqrt(((a.x - b.x) ^ 2) + (a.y - b.y) ^ 2)
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
            poly = poly
          }
        end
      end
    end
  end

  if closest then
    return closest.point, closest.poly
  end
end

function move_selected_points(xDelta, yDelta)
  local pointsToMove = {}

  if #selectedPoints > 0 then
    for _, sp in pairs(selectedPoints) do
      table.insert(pointsToMove, sp.point)
    end
  -- if there are no specifically selected points, but there are whole polygons
  -- selected, move all points in the selected polygons
  elseif #selectedPoints == 0 and #selectedPolygons > 0 then
    for _, poly in pairs(selectedPolygons) do
      for _, point in pairs(poly.points) do
        table.insert(pointsToMove, point)
      end
    end
  end

  if #pointsToMove > 0 then
    if xDelta ~= 0 or yDelta ~= 0 then
      -- make sure this movement would not result in any values outside the
      -- range which can be saved
      for _, point in pairs(pointsToMove) do
        if point.x + xDelta < POINT_MIN_X or point.x + xDelta > POINT_MAX_X or
           point.y + yDelta < POINT_MIN_Y or point.y + yDelta > POINT_MAX_Y
          then
          return
        end
      end

      save_undo_state()
      for _, point in pairs(pointsToMove) do
        point.x = point.x + xDelta
        point.y = point.y + yDelta
      end

      -- re-render all polygons
      render_polygons()
    end
  end
end

function set_selected_polygons(points)
  selectedPolygons = points
  selectedPoints = {}
  selectionFlash:reset()
end

function set_selected_points(pointRefs)
  selectedPoints = pointRefs
  selectedPolygons = {}
  selectionFlash:reset()
end

function choose_existing_file()
  --local pressed = love.window.showMessageBox

  --return filenames[pressed]
end

function love.textinput(t)
  if mode == 'save' then
    if not currentFilename then
      currentFilename = ''
    end

    currentFilename = currentFilename .. t
  end
end

function rtrim(s)
  local n = #s
  while n > 0 and s:find("^%s", n) do n = n - 1 end
  return s:sub(1, n)
end

function love.filedropped(file)
  file:open('r')
  local data = file:read()
  file:close()

  if data then
    currentFilename = file:getFilename()
    
    -- remove all but the filename
    currentFilename = currentFilename:match( "([^/]+)$" )

    -- parse and apply the painting data
    parse_painting_data(data)
  end
end

function love.keypressed(key)
  if mode == 'save' then
    if key == 'return' then
      currentFilename = rtrim(currentFilename)

      save_painting(currentFilename)
      mode = nil
    elseif key == 'escape' then
      mode = nil
    elseif key == 'backspace' and #currentFilename > 0 then
      local byteoffset = utf8.offset(currentFilename, -1)
      if byteoffset then
        currentFilename = string.sub(currentFilename, 1, byteoffset - 1)
      end
    end

    return
  end

  local shiftIsDown = (love.keyboard.isDown('lshift') or
    love.keyboard.isDown('rshift'))

  if love.keyboard.isDown('lctrl') or love.keyboard.isDown('rctrl') then
    if key == 'n' then
      -- todo: confirm here, but window.showMessageBox with buttons is bugged

      save_undo_state()

      currentFilename = ''
      polygons = {}
      selectedPolygons = {}
      selectedPoints = {}

      -- re-render all polygons
      render_polygons()
    elseif key == 's' then
      mode = 'save'

      -- don't let this key trigger anything else below
      return
    end
  end

  if key == 'k' then
    -- toggle between mouse-only mode (in which the arrow keys always move
    -- points, even if the move tool is not selected) and keyboard-friendly
    -- mode
    
    mouseOnlyMode = not mouseOnlyMode

    if mouseOnlyMode then
      -- halt the cursor's current momentum
      cursor.vx = 0
      cursor.vy = 0
    end
  end

  -- toggle fine-movement mode for the keyboard-cursor
  if key == 'f' then
    cursor.fineMode = not cursor.fineMode

    if not cursor.fineMode then
      -- halt the cursor's current momentum
      cursor.vx = 0
      cursor.vy = 0
    end
  end

  if cursor.tool == 'move' or mouseOnlyMode then
    if key == 'left' then
      move_selected_points(-1, 0)
    elseif key == 'right' then
      move_selected_points(1, 0)
    elseif key == 'up' then
      move_selected_points(0, -1)
    elseif key == 'down' then
      move_selected_points(0, 1)
    end
  else
    if cursor.fineMode and not mouseOnlyMode then
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
      set_color(cursor.color - 1)
    end
  elseif key == '2' then
    if cursor.color < #palette then
      set_color(cursor.color + 1)
    end
  end

  if key == 'z' or key == 'space' then
    push_primary_button()
  elseif key == 'return' then
    push_secondary_button()
  end

  if key == 'f5' or (love.keyboard.isDown('lctrl') and key == 'r') then
    -- force re-render all polygons
    render_polygons()
  end

  -- switch tools
  if key == 'd' then
    cursor.tool = 'draw'
    set_selected_polygons({})
    set_selected_points({})
  elseif key == 's' then
    cursor.tool = 'select polygon'
  elseif key == 'p' then
    cursor.tool = 'select point'
  elseif key == 'm' then
    cursor.tool = 'move'
  elseif key == 'c' then
    cursor.tool = 'change color'
    set_color(cursor.color)
  end

  if key == '[' then
    -- push the selected polygons back by one in the stack
    local polys = get_target_polygons()
    for i = 1, #polys do
      push_polygon_back(polys[i])
    end
  elseif key == ']' then
    -- pull the selected polygons forward by one in the stack
    local polys = get_target_polygons()
    for i = 1, #polys do
      pull_polygon_forward(polys[i])
    end
  end

  if key == 'tab' then
    if cursor.tool == 'select polygon' or
       (cursor.tool ~= 'select point' and #selectedPolygons > 0) then
      if #selectedPolygons == 0 then
        if #selectedPoints == 1 then
          local poly = selectedPoints[1].poly
          set_selected_polygons({poly})
        else
          set_selected_polygons({polygons[1]})
        end
      elseif #selectedPolygons == 1 then
        local index = find_polygon_index(selectedPolygons[1])

        if index then
          local nextIndex
          if shiftIsDown then
            nextIndex = index - 1
          else
            nextIndex = index + 1
          end
          if nextIndex < 1 then
            nextIndex = #polygons
          elseif nextIndex > #polygons then
            nextIndex = 1
          end

          set_selected_polygons({polygons[nextIndex]})
        end
      end
    end

    if cursor.tool == 'select point' or
       (cursor.tool ~= 'select polygon' and #selectedPoints > 0) then
      if #selectedPoints == 0 and #selectedPolygons == 1 then
        local sp = {
          point = selectedPolygons[1].points[1],
          poly = selectedPolygons[1]
        }

        set_selected_points({sp})
      elseif #selectedPoints == 1 then
        local dir = 1
        if shiftIsDown then
          dir = -1
        end

        select_next_point(selectedPoints[1], dir)
      end
    end
  end

  if key == 'escape' then
    drawingPoints = {}
    set_selected_polygons({})
    set_selected_points({})
  end

  if key == 'delete' or key == 'backspace' then
    if #selectedPolygons > 0 then
      save_undo_state()

      polygons = remove_values_from_table(selectedPolygons, polygons)
      set_selected_polygons({})

      -- re-render all polygons
      render_polygons()
    end

    if #selectedPoints > 0 then
      save_undo_state()

      local pointsToDelete = shallow_copy_table(selectedPoints)

      if #selectedPoints == 1 and #selectedPoints[1].poly.points > 1 then
        select_next_point(selectedPoints[1], 1)
      else
        set_selected_points({})
      end

      for _, sp in pairs(pointsToDelete) do
        -- remove the point from its polygon
        local index = find_point_index(sp.point, sp.poly)
        table.remove(sp.poly.points, index)

        -- if this point's polygon has no points now, delete it
        if #sp.poly.points == 0 then
          polygons = remove_values_from_table({sp.poly}, polygons)
        end
      end

      -- re-render all polygons
      render_polygons()
    end
  end

  if key == 'i' then
    insert_point()
  end

  if key == 'u' then
    undo()
  end
end

function insert_point()
  -- If there are exactly two points selected, from the same polygon
  if #selectedPoints == 2 and
     selectedPoints[1].poly == selectedPoints[2].poly then

    -- Get the indices of the two selected points
    local i = find_point_index(selectedPoints[1].point,
      selectedPoints[1].poly)
    local j = find_point_index(selectedPoints[2].point,
      selectedPoints[2].poly)

    local polygon = selectedPoints[1].poly

    if #polygon.points >= MAX_POLYGON_POINTS then
      love.window.showMessageBox('so many!',
        'this polygon has ' .. MAX_POLYGON_POINTS ..
        ' points; no more can be added')
      return
    end

    -- Put the two indices in ascending order
    if j < i then
      j, i = i, j
    end

    -- if the indices are consecutive
    if j == i + 1 or (i == 1 and j == #polygon.points) then
      -- find the midpoint between the two points
      local midpoint = midpoint(polygon.points[i], polygon.points[j])

      midpoint.x = math.floor(midpoint.x)
      midpoint.y = math.floor(midpoint.y)

      save_undo_state()

      if i == 1 then
        newIndex = 1
      else
        newIndex = j
      end

      -- insert the midpoint as a new point in the polygon
      table.insert(polygon.points, newIndex, midpoint)

      -- select the new point
      selectedPoints = {
        {
          point = polygon.points[newIndex],
          poly = polygon
        }
      }
    end
  end
end

function midpoint(a, b)
  return {
    x = (a.x + b.x) / 2,
    y = (a.y + b.y) / 2
  }
end

function select_next_point(sp, direction)
  -- Cycle through points in the same polygon as the currently selected
  -- point
  local index = find_point_index(sp.point, sp.poly)
  local poly = sp.poly

  local nextIndex = index + direction
  if nextIndex < 1 then
    nextIndex = #poly.points
  elseif nextIndex > #poly.points then
    nextIndex = 1
  end

  local newSelectedPoint = {
    point = poly.points[nextIndex],
    poly = poly
  }

  set_selected_points({newSelectedPoint})
end

function push_polygon_back(poly)
  -- find the index of this polygon
  local index = find_polygon_index(poly)

  if index and index > 1 then
    -- swap the poly with the one before it
    polygons[index - 1], polygons[index] = polygons[index], polygons[index - 1]
  end
end

function find_polygon_index(poly)
  for i = 1, #polygons do
    if polygons[i] == poly then
      return i
    end
  end
end

-- find a point's index within its parent polygon
function find_point_index(point, polygon)
  for i = 1, #polygon.points do
    if polygon.points[i] == point then
      return i
    end
  end
end

function pull_polygon_forward(poly)
  -- find the index of this polygon
  local index = find_polygon_index(poly)

  if index and index < #polygons then
    -- swap the poly with the one after it
    polygons[index + 1], polygons[index] = polygons[index], polygons[index + 1]
  end
end

function push_primary_button()
  if not cursor.isVisible then
    return
  end

  local shiftIsDown = (love.keyboard.isDown('lshift') or
    love.keyboard.isDown('rshift'))

  if cursor.tool == 'draw' then
    draw_point()
  elseif cursor.tool == 'select polygon' then
    if cursor.hoveredPolygon then
      if shiftIsDown then
        table.insert(selectedPolygons, cursor.hoveredPolygon)
      else
        set_selected_polygons({cursor.hoveredPolygon})
      end
    else
      set_selected_polygons({})
    end
  elseif cursor.tool == 'select point' then
    if cursor.hoveredPoint then
      if shiftIsDown then
        -- look for this point in the selectedPoints table
        local existingIndex
        for i, sp in pairs(selectedPoints) do
          if cursor.hoveredPoint.point == sp.point then
            existingIndex = i
          end
        end

        -- if this point is already in the selectedPoints table
        if existingIndex then
          table.remove(selectedPoints, existingIndex)
        else
          -- otherwise add the point to the table of selected points
          table.insert(selectedPoints, cursor.hoveredPoint)
        end
      else
        set_selected_points({cursor.hoveredPoint})
      end
    else
      set_selected_points({})
    end
  end
end

function push_secondary_button()
  if not cursor.isVisible then
    return
  end

  if cursor.tool == 'draw' then
    finalize_drawing_points()
  end
end

function remove_point_from_table(point, t)
  local t2 = {}
  for i = 1, #t do
    p = t[i]

    if p.x ~= point.x or p.y ~= point.y then
      table.insert(t2, p)
    end
  end

  return t2
end

function remove_values_from_table(values, t)
  local t2 = {}
  for i = 1, #t do
    local v = t[i]

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
    cursor.isVisible = true
  else
    -- show the OS mouse cursor
    love.mouse.setVisible(true)
    mouseIsOnCanvas = false

    if mouseOnlyMode then
      -- hide the canvas cursor
      cursor.isVisible = false
      cursor.hoveredPolygon = nil
      cursor.hoveredPoint = nil
    end
  end
end

function get_color_under_mouse(x, y)
  for i, box in pairs(paletteBox) do
    if x >= box.x and x < box.x + paletteDisplay.colorW and
       y >= box.y and y < box.y + paletteDisplay.colorH then
      return i
    end
  end
end

-- get a table of all polygons selected or partially selected in any way (i.e.
-- regardness of whether the the whole polygon is selected, via "select
-- polygons" tool, or only a point of the polygon is selected, via the "select
-- points" tool)
function get_target_polygons()
  local targetPolys = {}

  if #selectedPolygons > 0 then
    targetPolys = selectedPolygons
  elseif #selectedPoints > 0 then
    -- add each polygon that has any point selected
    for _, sp in pairs(selectedPoints) do
      if not table_has_value(targetPolys, sp.poly) then
        table.insert(targetPolys, sp.poly)
      end
    end
  end

  return targetPolys
end

function set_color(color)
  cursor.color = color

  if cursor.tool == 'change color' then
    save_undo_state()

    local targetPolys = get_target_polygons()

    -- change the color of all target polygons
    for _, poly in pairs(targetPolys) do
      poly.color = color
    end

    -- re-render all polygons
    render_polygons()
  end
end

function table_has_value(t, value)
  for k, v in pairs(t) do
    if v == value then
      return true
    end
  end

  return false
end

function love.mousepressed(x, y, button)
  if button == 1 then
    if mouseIsOnCanvas then
      push_primary_button()
      return
    end

    local color = get_color_under_mouse(x, y)
    if color ~= nil then
      set_color(color)
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
  if #drawingPoints < 1 then
    return
  end

  --local points = {}

  --if #drawingPoints <= 3 then
  --  points = copy_table(drawingPoints)
  --  table.remove(points, #points)
  --else
  --  points = copy_table(drawingPoints)
  --end

  -- finalize the WIP polygon
  table.insert(polygons,
    {
      points = drawingPoints,
      color = cursor.color
    })

  -- clear the WIP points
  drawingPoints = {}

  -- re-render all polygons
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
  local x1 = POINT_MAX_X
  local x2 = POINT_MIN_X
  local y1 = POINT_MAX_Y
  local y2 = POINT_MIN_Y
  for _, point in pairs(points) do
    if point.x < x1 then
      x1 = point.x
    end
    if point.x > x2 then
      x2 = point.x
    end

    if point.y < y1 then
      y1 = point.y
    end
    if point.y > y2 then
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

-- round a 32-bit float to be like PICO-8's fixed 16:16
function fix_float(x)
  return math.floor(x * 65536) / 65536
end

function find_intersections(points, y)
  local xlist = {}
  local j = #points

  for i = 1, #points do
    local a = points[i]
    local b = points[j]

    if (a.y < y and b.y >= y) or (b.y < y and a.y >= y) then
      local x = a.x + fix_float(
        fix_float((y - a.y) / (b.y - a.y)) * (b.x - a.x)
      )

      table.insert(xlist, x)
    end

    j = i
  end

  return xlist
end

function point_in_polygon(point, poly)
  if #poly.points < 3 then
    return false
  end

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

function fillpoly(poly, rgba, outline)
  love.graphics.setColor(rgba)
  love.graphics.setPointSize(1)
  love.graphics.setLineWidth(1)
  love.graphics.setLineStyle('rough')

  if #poly.points == 1 then
    -- draw a point instead of a polygon
    love.graphics.points(poly.points[1].x + 0.5, poly.points[1].y + 0.5)
    return
  elseif #poly.points == 2 then
    -- draw a line
    picolove.line(
      poly.points[1].x, poly.points[1].y,
      poly.points[2].x, poly.points[2].y)
    return
  end

  -- find the bounds of the polygon
  local x1, x2, y1, y2 = find_bounds(poly.points)

  for y = y2, y1, -1 do
    -- find intersecting nodes
    local xlist = find_intersections(poly.points, y)
    table.sort(xlist)

    for i = 1, #xlist - 1, 2 do
      local x1 = math.floor(xlist[i])
      local x2 = math.ceil(xlist[i + 1])

      -- DEBUG: make sure the line's pixels are in the correct spot
      --love.graphics.points(x1 + 0.5, y + 0.5)

      picolove.line(x1, y, x2, y)
    end
  end
end

function render_polygons()
  print('re-rendering all (' .. #polygons .. ') polygons')

  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0)

  for i = 1, #polygons do
    local poly = polygons[i]

    fillpoly(poly, palette[poly.color])
  end

  love.graphics.setCanvas()
end

function draw_tool()
  love.graphics.setCanvas(toolsCanvas)
  love.graphics.setColor(0, 0, 0, 0)
  love.graphics.clear()

  if #drawingPoints > 0 then
    -- draw the WIP polygon
    draw_wip_poly()
  end

  -- draw a overlay on the polygon we are hovering over
  if cursor.hoveredPolygon then
    fillpoly(cursor.hoveredPolygon, hoverFlash:get_color())
  end

  -- draw a rectangle around the point we are hovering over
  if cursor.hoveredPoint then
    love.graphics.setLineWidth(1)
    love.graphics.setLineStyle('rough')
    love.graphics.setColor(hoverFlash:get_color())

    local point = cursor.hoveredPoint.point
    local x = point.x + 0.5
    local y = point.y + 0.5
    love.graphics.rectangle('line', x - 1, y - 1, 2, 2)
  end

  -- draw an flashing overlay over the selected polygons
  for _, poly in pairs(selectedPolygons) do
    fillpoly(poly, selectionFlash:get_color())
  end

  -- draw a flashing overlay on the selected points
  love.graphics.setPointSize(1)
  love.graphics.setColor(selectionFlash:get_color())
  for _, sp in pairs(selectedPoints) do
    love.graphics.points(sp.point.x + 0.5, sp.point.y + 0.5)
  end

  love.graphics.setCanvas()
end

function draw_canvases()
  love.graphics.push()

  love.graphics.scale(canvasScale, canvasScale)

  love.graphics.setColor(255, 255, 255)

  -- draw the polygon canvas
  love.graphics.draw(canvas, canvasPos.x, canvasPos.y)

  -- draw the tools cavnas on top of the polygon canvas
  love.graphics.draw(toolsCanvas, canvasPos.x, canvasPos.y)

  love.graphics.pop()
end

function point_to_string(point)
  return '(' .. point.x .. ', ' .. point.y .. ')'
end

function draw_status()
  love.graphics.setColor(255, 255, 255)
  local x = (CANVAS_W * canvasScale) + (canvasMargin * 2)
  local y = canvasMargin
  local lineh = love.graphics.getFont():getHeight()

  love.graphics.print('total polygons: ' .. #polygons, x, y)

  love.graphics.print('FPS: ' .. love.timer.getFPS(), x + 215, y)


  y = y + lineh
  if cursor.isVisible then
    -- show the cursor's current position
    local cursorDisplayPoint = {
      x = math.floor(cursor.x),
      y = math.floor(cursor.y)
    }
    love.graphics.print(point_to_string(cursorDisplayPoint), x, y)
  end

  y = y + lineh
  love.graphics.print('current tool: ' .. cursor.tool, x, y)

  if not mouseOnlyMode then
    y = y + lineh

    if cursor.fineMode then
      love.graphics.print('fine keyboard-cursor movement enabled', x, y)
    else
      love.graphics.print('keyboard-friendly mode enabled', x, y)
    end
  end

  local selectedPolys
  if #drawingPoints > 0 then
    selectedPolys = {{points = drawingPoints}}
  else
    selectedPolys = selectedPolygons
  end

  if selectedPolys then
    y = 300
    if #selectedPolys == 1 then
      love.graphics.print('selected polygon:', x, y)
      y = y + lineh

      local index = find_polygon_index(selectedPolys[1])
      if index then
        love.graphics.print('  index: ' .. find_polygon_index(selectedPolys[1]),
          x, y)
        y = y + lineh
      end

      love.graphics.print('  points:', x, y)
      for i, point in pairs(selectedPolys[1].points) do
        y = y + lineh
        love.graphics.print('    ' .. i .. ': ' .. point_to_string(point),
          x, y)
      end

    elseif #selectedPolys > 1 then
      love.graphics.print(
        'selected polygons: ' .. #selectedPolys, x, y)
    end
  end

  if #selectedPoints > 0 then
    love.graphics.print('selected point(s): ', x, y)
    y = y + lineh

    -- Group the points by parent polygon
    local groups = {}
    for _, sp in pairs(selectedPoints) do
      local index = find_polygon_index(sp.poly)

      if not groups[index] then
        groups[index] = {}
      end

      table.insert(groups[index], sp)
    end

    local sortedKeys = get_sorted_keys(groups)

    for i = 1, #sortedKeys do
      local key = sortedKeys[i]

      love.graphics.print('  polygon ' .. key .. ':', x, y)
      y = y + lineh

      for j = 1, #groups[key] do
        local sp = groups[key][j]
        local index = find_point_index(sp.point, sp.poly)
        love.graphics.print('    ' .. index .. ' ' ..
          point_to_string(sp.point), x, y)
        y = y + lineh
      end
    end

    --for i = 1, #selectedPoints do
    --  local point = selectedPoints[i].point
    --  y = y + lineh
    --  love.graphics.print(point_to_string(point) .. ' polygon ' .. , x, y)
    --end
  end
end

function get_sorted_keys(t)
  local keys = {}
  for k, v in pairs(t) do
    table.insert(keys, k)
  end

  table.sort(keys)

  return keys
end

function draw_cursor()
  if cursor.isVisible == false or cursor.tool == 'move' then
    return
  end

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

  love.graphics.setColor(cursor.flash:get_color())
  love.graphics.points(points)
    
  love.graphics.pop()
end

function draw_point()
  if #polygons == MAX_POLYGONS then
    love.window.showMessageBox('so many!',
      'this painting has the maximum ' .. MAX_POLYGONS .. ' polygons; ' ..
      'no more can be added')
    return
  end

  save_undo_state()

  table.insert(drawingPoints,
    {
      x = math.floor(cursor.x),
      y = math.floor(cursor.y)
    })
end

function update_palette_display()
  paletteDisplay = {
    x = (CANVAS_W * canvasScale) + (canvasMargin * 2),
    y = (canvasMargin * 3),
    colorW = 40,
    colorH = 32,
    outlineW = 4
  }

  local i = 0
  for y = 0, (paletteDisplay.colorH * 4) - 1, paletteDisplay.colorH do
    for x = 0, (paletteDisplay.colorW * 4) - 1, paletteDisplay.colorW do
      paletteBox[i] = {
        x = paletteDisplay.x + x,
        y = paletteDisplay.y + y
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
    love.graphics.rectangle('fill', x, y,
      paletteDisplay.colorW, paletteDisplay.colorH)
  end

  -- outline the currently selected color
  local lineW = paletteDisplay.outlineW
  love.graphics.setLineWidth(paletteDisplay.outlineW)
  love.graphics.setColor(0, 0, 0)
  love.graphics.rectangle('line',
    paletteBox[cursor.color].x + (lineW / 2),
    paletteBox[cursor.color].y + (lineW / 2),
    paletteDisplay.colorW - lineW,
    paletteDisplay.colorH - lineW)

  love.graphics.setColor(255, 255, 255)
  love.graphics.rectangle('line',
    paletteBox[cursor.color].x - (lineW / 2),
    paletteBox[cursor.color].y - (lineW / 2),
    paletteDisplay.colorW + lineW,
    paletteDisplay.colorH + lineW)
end

function draw_wip_poly()
  local points = {}

  for i = 1, #drawingPoints do
    points[i] = {
      x = drawingPoints[i].x,
      y = drawingPoints[i].y
    }
  end
  points[#points + 1] = {x = cursor.x, y = cursor.y}

  love.graphics.setLineWidth(1)
  love.graphics.setPointSize(1)

  for i = 1, #points - 1 do
    local a = points[i]
    local b = points[i + 1]

    love.graphics.setColor(palette[cursor.color])
    picolove.line(a.x, a.y, b.x, b.y)

    -- draw a flashing handle on this point
    love.graphics.setColor(selectionFlash:get_color())
    love.graphics.points(a.x + 0.5, a.y + 0.5)
  end
end

function undo()
  -- pop the most recent saved state off the undoHistory
  local state = table.remove(undoHistory)

  if state then
    -- apply the saved state
    polygons = state.polygons
    drawingPoints = state.drawingPoints
    cursor.color = state.cursorColor
    cursor.tool = state.cursorTool

    -- clear selections because they point to non-existant objects now
    set_selected_polygons({})
    set_selected_points({})

    -- re-render all polygons
    render_polygons()
  else
    print('no undo history remaining')
  end
end

function save_undo_state()
  if #undoHistory == MAX_UNDO then
    table.remove(undoHistory, 1)
  end

  local state = {}
  state.polygons = copy_table(polygons)
  state.drawingPoints = copy_table(drawingPoints)
  state.cursorColor = cursor.color
  state.cursorTool = cursor.tool

  table.insert(undoHistory, state)
end

function love.update()
  update_cursor()
  update_palette_display()
end

function love.draw()
  -- clear the screen
  love.graphics.setCanvas()
  love.graphics.clear(10, 10, 10)

  if mode == 'save' then
    love.graphics.setColor(255, 255, 255)
    love.graphics.print('Enter filename to save to:', 20, 20)
    if currentFilename then
      love.graphics.print(currentFilename, 20, 40)
    end
    return
  end

  -- draw the current tool on the tools canvas
  draw_tool()

  -- draw the canvases
  draw_canvases()

  -- draw status stuff
  draw_status()
  draw_palette()

  -- draw the cursor
  draw_cursor()
end
