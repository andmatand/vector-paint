local utf8 = require('utf8')
local bit = require('bit')
local picolove = require('lib.picolove')
--local inspect = require('lib.inspect')
require('class.colorflash')

-- define global constants
MODES = {
  NORMAL = 1,
  SAVE = 2,
  EDIT_FILL_PATTERN = 3,
}
TOOLS = {
  BG_IMAGE = 1,
  CHANGE_COLOR = 2,
  CHANGE_FILL_PATTERN = 3,
  DRAW = 4,
  MOVE = 5,
  SELECT_POINT = 6,
  SELECT_SHAPE = 7,
}
TOOL_NAMES = {
  [TOOLS.BG_IMAGE] = 'adjust backgroud image',
  [TOOLS.CHANGE_COLOR] = 'change shape color',
  [TOOLS.CHANGE_FILL_PATTERN] = 'change shape fill-pattern index',
  [TOOLS.DRAW] = 'draw',
  [TOOLS.MOVE] = 'move',
  [TOOLS.SELECT_POINT] = 'select point(s)',
  [TOOLS.SELECT_SHAPE] = 'select shape(s)',
}
MAX_UNDO = 500
MAX_FILL_PATTERN_INDEX = 3
FILL_PATTERN_SCANCODES = {
  ['1'] = 1,
  ['2'] = 2,
  ['3'] = 3,
  ['4'] = 4,
  ['q'] = 5,
  ['w'] = 6,
  ['e'] = 7,
  ['r'] = 8,
  ['a'] = 9,
  ['s'] = 10,
  ['d'] = 11,
  ['f'] = 12,
  ['z'] = 13,
  ['x'] = 14,
  ['c'] = 15,
  ['v'] = 16,
}

function love.load(arg)
  CANVAS_W = 128
  CANVAS_H = 128
  PATTERN_SWATCH_CANVAS_W = 10
  PATTERN_SWATCH_CANVAS_H = 38
  PATTERN_SWATCH_W = 8
  PATTERN_SWATCH_H = 8
  PATTERN_SWATCH_ROW_H = 10
  love.graphics.setFont(love.graphics.newFont(14))

  POINT_MIN_X = 0
  POINT_MAX_X = 255
  POINT_MIN_Y = -1
  POINT_MAX_Y = 254

  MAX_POLYGONS = 256
  MAX_POLYGON_POINTS = 64

  canvasMargin = 50

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

  -- convert palette colors to 0-1 scale for LÖVE 11.0+
  for _, p in pairs(palette) do
    for c = 1, 3 do
      p[c] = p[c] / 255
    end
  end

  -- create a table to store positions of palette color boxes in the UI
  paletteBox = {}

  -- create a data structures for storing positions of the fill-pattern
  -- selector UI
  fillPatternSelector = {
    boxes = { [0] = {}, [1] = {}, [2] = {}, [3] = {} },
    outlineMargin = 2
  }

  fillPatterns = {}
  for i = 1, MAX_FILL_PATTERN_INDEX do
    fillPatterns[i] = create_default_fill_pattern()
  end

  -- make sure we get ALL the pixels
  love.graphics.setDefaultFilter('nearest', 'nearest')
  love.graphics.setLineStyle('rough')

  -- create a canvas to draw on
  canvas = love.graphics.newCanvas(CANVAS_W, CANVAS_H)

  -- create a canvas for the tools overlay
  toolsCanvas = love.graphics.newCanvas(CANVAS_W, CANVAS_H)

  -- create a canvas for the fill-pattern swatches
  fillPatternSwatchCanvas = love.graphics.newCanvas(
    PATTERN_SWATCH_CANVAS_W,
    PATTERN_SWATCH_CANVAS_H)

  canvasOpacity = 1
  bg = {
    image = nil,
    offset = {x = 0, y = 0},
    scale = 1,
  }

  cursor = {
    x = math.floor(CANVAS_W / 2),
    y = math.floor(CANVAS_H / 2),
    vx = 0,
    vy = 0,
    tool = TOOLS.DRAW,
    color = 14,
    bgColor = 10,
    patternIndex = 0,
    isVisible = true
  }

  cursor.flash = ColorFlash.new(.25, {
    palette[0],
    palette[5],
    palette[6],
    palette[7]
  })

  selectedShapes = {}
  selectedPoints = {}

  drawingPoints = {}

  hoverFlash = ColorFlash.new(.1, {
    {1, 1, 1, .25},
    {1, 1, 1,  .5},
    {1, 1, 1, .75},
    {1, 1, 1,  .5},
    {1, 1, 1, .25},
    {1, 1, 1,   0},
    {0, 0, 0, .25},
    {0, 0, 0,  .5},
    {0, 0, 0, .75},
    {0, 0, 0,  .5},
    {0, 0, 0, .25},
    {1, 1, 1,   0},
  })

  selectionFlash = ColorFlash.new(.5, {
    {1, 1, 1, .5},
    {1, 1, 1,  0},
    {0, 0, 0, .5},
    {1, 1, 1,  0},
  })

  patternSelectionFlash = ColorFlash.new(.5, {
    {1, 1, 1},
    {0, 0, 0},
  })

  mode = MODES.NORMAL
  mouseOnlyMode = true
  currentFilename = ''

  polygons = {}
  undoHistory = {}
  undoIndex = 1
  redoStack = {}
  status = {
    byteCount = 0
  }

  find_best_canvas_scale()

  -- If a command-line argument is given, treat it as a filename to load
  if #arg > 0 then
    load_painting(arg[1])
  end
end

function optimize_unused_fill_patterns(shapes, fillPatterns)
  local usedFillPatterns = {}

  for _, shape in pairs(shapes) do
    if shape.patternIndex > 0 then
      local pattern = fillPatterns[shape.patternIndex]
      if not pattern.isUsed then
        pattern.isUsed = true
        pattern.oldIndex = shape.patternIndex
        table.insert(usedFillPatterns, pattern)
      end
    end
  end

  print('used fill-pattern count: ' .. #usedFillPatterns)

  -- Sort the used patterns by current index so the order is deterministic
  table.sort(usedFillPatterns, function (a, b)
    return a.oldIndex < b.oldIndex
  end)

  if #usedFillPatterns > 0 then
    local patternIndexTranslationTable = {}
    for i, pattern in pairs(usedFillPatterns) do
      patternIndexTranslationTable[pattern.oldIndex] = i
    end

    -- update shapes' pattern indexes
    for _, shape in pairs(shapes) do
      if shape.patternIndex > 0 then
        shape.patternIndex = patternIndexTranslationTable[shape.patternIndex]
      end
    end
  end

  return usedFillPatterns
end

function get_painting_data()
  local bytes = {}

  local shapes = copy_table(polygons)
  local fillPatterns = copy_table(fillPatterns)
  local usedFillPatterns = optimize_unused_fill_patterns(shapes, fillPatterns)

  -- add each shape
  for _, shape in ipairs(shapes) do
    assert(shape.patternIndex <= MAX_FILL_PATTERN_INDEX)
    assert(#shape.points <= MAX_POLYGON_POINTS)

    -- add the shape's fill-pattern index and point count
    local byte1 = bit.bor(bit.lshift(shape.patternIndex, 6), #shape.points)
    table.insert(bytes, byte1)

    -- add the shape's color
    if shape.patternIndex == 0 then
      -- bgColor is not used, so write zeros (which is more compressable)
      shape.bgColor = 0
    end
    table.insert(bytes, bit.bor(bit.lshift(shape.bgColor, 4), shape.color))

    -- add each point
    for j = 1, #shape.points do
      local point = shape.points[j]
      table.insert(bytes, point.x)
      table.insert(bytes, point.y + 1) -- add 1 to y to allow -1 without sign
    end
  end

  if #usedFillPatterns > 0 then
    -- add used fill-patterns
    for _, fillPattern in ipairs(usedFillPatterns) do
      local patternBytes = convert_pattern_array_to_bytes(fillPattern.pattern)
      local byte1 = bit.rshift(
        bit.band(patternBytes, 0b1111111100000000),
        8)
      local byte2 = bit.band(patternBytes, 0b0000000011111111)

      table.insert(bytes, byte1)
      table.insert(bytes, byte2)
    end

    -- add transparency bits for fill-patterns
    local transparencyByte = 0
    for i, fillPattern in ipairs(usedFillPatterns) do
      if fillPattern.isTransparent then
        local newBit = bit.rshift(0b10000000, i - 1)
        transparencyByte = bit.band(transparencyByte, newBit)
      end
    end
    table.insert(bytes, transparencyByte)
  end

  return convert_to_hex(bytes)
end

function convert_to_hex(bytes)
  local hex = ''
  for i = 1, #bytes do
    hex = hex .. bit.tohex(bytes[i], 2)
  end
  return hex
end

function convert_pattern_array_to_bytes(pattern)
  local bytes = 0
  for i, pbit in ipairs(pattern) do
    if pbit == 1 then
      local mask = bit.rshift(0b1000000000000000, i - 1)
      bytes = bit.bor(bytes, mask)
    end
  end
  return bytes
end

function convert_pattern_bytes_to_array(pattern)
  local array = {}
  for i = 1, 16 do
    local mask = bit.rshift(0b1000000000000000, i - 1)
    local b = bit.rshift(bit.band(mask, pattern), 16 - i)
    table.insert(array, b)
  end
  return array
end

function load_painting(filename)
  print('loading painting from "' .. filename .. '"')

  local data = love.filesystem.read(filename)
  if data then
    load_painting_data(data)
    set_current_filename(filename)
  end
end

function set_current_filename(filename)
  currentFilename = filename

  -- remove all but the filename
  currentFilename = currentFilename:match("([^/]+)$")
end

function save_painting(filename)
  local data = get_painting_data()

  local success, msg = love.filesystem.write(filename, data)

  if success then
    print('saved to ' .. love.filesystem.getSaveDirectory() .. '/' .. filename)
  else
    love.window.showMessageBox('nooooo :(', 'ERROR SAVING: ' .. msg, 'error')
  end
end

function create_painting_reader(data)
  return {
    i = 1,
    data = data,

    get_next_byte = function(self)
      local byte = ('0x' .. string.sub(self.data, self.i, self.i + 1)) + 0
      self.i = self.i + 2
      return byte
    end,

    is_at_end = function(self)
      return (self.i > #data)
    end,

    is_at_end_of_shapes = function(self, patternCount)
      return patternCount > 0 and self.i == #data - (patternCount * 4) - 1
    end
  }
end

function rtrim(s)
  local n = #s
  while n > 0 and s:find("^%s", n) do
    n = n - 1
  end
  return s:sub(1, n)
end

function load_painting_data(data)
  data = rtrim(data)

  if #data == 0 then
    love.window.showMessageBox('hey!', 'that file is empty; nothing to load!')
    return
  end

  save_undo_state()

  -- clear the existing painting
  polygons = {}
  selectedShapes = {}
  selectedPoints = {}

  local reader = create_painting_reader(data)
  polygons, fillPatterns = parse_painting(reader)

  -- convert patterns to editing format (i.e. array of 1s and 0s)
  for i, fillPattern in pairs(fillPatterns) do
    fillPattern.pattern = convert_pattern_bytes_to_array(fillPattern.pattern)
  end

  -- add any missing fill-patterns to make a total of 3
  for i = #fillPatterns, 3 do
    table.insert(fillPatterns, create_default_fill_pattern())
  end

  -- re-render all polygons
  set_dirty_flag()
end

function parse_painting(reader)
  local shapes = {}
  local fillPatterns = {}
  local patternCount = 0

  -- read each shape
  repeat
    local shape = {
      points = {}
    }

    -- read the fill-pattern index and point count
    local byte1 = reader:get_next_byte()
    shape.patternIndex = bit.rshift(bit.band(byte1, 0b11000000), 6)
    local pointCount = bit.band(byte1, 0b00111111)

    -- update running pattern count
    patternCount = math.max(patternCount, shape.patternIndex)
    assert(patternCount >= 0 and patternCount <= MAX_FILL_PATTERN_INDEX)

    -- read the color
    local colorByte = reader:get_next_byte()
    shape.color = bit.band(colorByte, 0b00001111)
    shape.bgColor = bit.rshift(bit.band(colorByte, 0b11110000), 4)

    -- read each point
    for i = 1, pointCount do
      local x = reader:get_next_byte()
      local y = reader:get_next_byte()

      -- adjust y back to its actual value since it is saved 1 higher than its
      -- actual value to allow for -1 without needing a sign bit
      y = y - 1

      table.insert(shape.points, {x = x, y = y})
    end

    table.insert(shapes, shape)
  until reader:is_at_end_of_shapes(patternCount) or reader:is_at_end()

  if patternCount > 0 then
    for i = 1, patternCount do
      local byte1 = reader:get_next_byte()
      local byte2 = reader:get_next_byte()
      local pattern = bit.bor(bit.lshift(byte1, 8), byte2)
      table.insert(fillPatterns, {pattern = pattern})
    end
    local byte = reader:get_next_byte()
    for i = 1, patternCount do
      local b = bit.band(bit.rshift(0b10000000, i - 1))
      fillPatterns[i].isTransparent = (b == 1 and true or false)
    end
  end

  return shapes, fillPatterns
end

function create_default_fill_pattern()
  return {
    pattern = {1, 0, 1, 0, 0, 1, 0, 1, 1, 0, 1, 0, 0, 1, 0, 1},
    isTransparent = false
  }
end

function set_dirty_flag()
  canvasIsDirty = true
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
  if mode == MODES.NORMAL then
    selectionFlash:update()
    hoverFlash:update()
  elseif mode == MODES.EDIT_FILL_PATTERN then
    patternSelectionFlash:update()
  end

  local delta = .25
  local friction = .80

  if not mouseOnlyMode then
    cursor.isVisible = true

    if not cursor.fineMode and cursor.tool ~= TOOLS.MOVE and
       cursor.tool ~= TOOLS.BG_IMAGE then
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
    if cursor.tool == TOOLS.SELECT_SHAPE or shift_is_down() then
      -- find the top polygon under the cursor
      local topPoly = find_top_poly(cursor)
      if topPoly then
        cursor.hoveredPolygon = topPoly
      end
    elseif cursor.tool == TOOLS.SELECT_POINT then
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
  elseif #selectedPoints == 0 and #selectedShapes > 0 then
    for _, poly in pairs(selectedShapes) do
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

      set_dirty_flag()
    end
  end
end

function set_selected_shapes(shapes)
  selectedShapes = shapes
  selectedPoints = {}
  selectionFlash:reset()

  if #shapes > 0 then
    oldSelectedShapes = shapes
  end
end

function set_selected_points(pointRefs)
  selectedPoints = pointRefs
  selectedShapes = {}
  selectionFlash:reset()
end

function choose_existing_file()
  -- TODO
  --local pressed = love.window.showMessageBox
  --return filenames[pressed]
end

function copy(shapes)
  -- make sure the shapes are in the same order as the source shapes' indicies
  local indexesAndShapes = {}
  for _, shape in pairs(shapes) do
    local index = find_polygon_index(shape)
    local copiedShape = copy_table(shape)
    table.insert(indexesAndShapes, {index = index, shape = copiedShape})
  end

  table.sort(indexesAndShapes, function (a, b)
    return a.index < b.index
  end)

  clipboard = {}
  for _, entry in ipairs(indexesAndShapes) do
    table.insert(clipboard, entry.shape)
  end

  print('copied ' .. #clipboard .. ' shapes')
end

-- paste so that the top-left point is at (x,y)
function paste(x, y)
  -- Find the point which is farthest to the top-left
  local topLeft = {x = CANVAS_W, y = CANVAS_H}
  for _, shape in pairs(clipboard) do
    local x1, _, y1, _ = find_bounds(shape.points)

    topLeft.x = math.min(x1, topLeft.x)
    topLeft.y = math.min(y1, topLeft.y)
  end

  -- Copy each shape in the clipboard and shift it over based on the target
  -- position
  local newShapes = {}
  for _, shape in pairs(clipboard) do
    local newShape = copy_table(shape)
    for _, point in pairs(newShape.points) do
      point.x = point.x - topLeft.x + x
      point.y = point.y - topLeft.y + y
    end
    table.insert(newShapes, newShape)
    table.insert(polygons, newShape)
  end

  set_selected_shapes(newShapes)
  print('pasted ' .. #newShapes .. ' shapes')
  set_dirty_flag()
end

function find_center(points)
  local sum = {x = 0, y = 0}

  for _, p in pairs(points) do
    sum.x = sum.x + p.x
    sum.y = sum.y + p.y
  end

  return {
    x = sum.x / #points,
    y = sum.y / #points
  }
end

function round(n)
  return math.floor(n + 0.5)
end

function scale_shapes(shapes, scale)
  for _, shape in pairs(shapes) do
    local center = find_center(shape.points)
    for _, p in pairs(shape.points) do
      p.x = round((scale * (p.x - center.x)) + center.x)
      p.y = round((scale * (p.y - center.y)) + center.y)
    end
  end

  set_dirty_flag()
end

function love.textinput(t)
  if mode == MODES.SAVE then
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

function ctrl_is_down()
  if love.system.getOS() == 'OS X' then
    if love.keyboard.isDown('lgui', 'rgui') then
      return true
    end
  end

  return love.keyboard.isDown('lctrl', 'rctrl')
end

function get_file_extension(filename)
  return filename:match("^.+(%..+)$")
end

function love.filedropped(file)
  local filename = file:getFilename()
  print('received dropped file "' .. filename .. '"')

  local ext = get_file_extension(filename)
  if ext then
    ext = string.sub(ext, 2, #ext)
  end

  file:open('r')
  local data = file:read()
  file:close()

  if ext == 'jpg' or ext == 'jpeg' or ext == 'png' then
    print('loading dropped file as background image')
    save_undo_state()
    bg.image = love.graphics.newImage(
      love.image.newImageData(
        love.filesystem.newFileData(data, filename)
      )
    )
    canvasOpacity = 0.5
  else
    print('loading dropped file as painting')
    if data then
      load_painting_data(data)
      set_current_filename(file:getFilename())
    end
  end
end

function set_mouse_only_mode(enabled)
  mouseOnlyMode = enabled

  if mouseOnlyMode then
    -- halt the cursor's current momentum
    cursor.vx = 0
    cursor.vy = 0
  end
end

function love.keypressed(key, scancode)
  local shiftIsDown = shift_is_down()
  local ctrlIsDown = ctrl_is_down()

  if ctrlIsDown and key == 'q' then
    love.event.quit()
  end
  if key == 'f11' then
    toggle_fullscreen()
  end

  if mode == MODES.SAVE then
    if key == 'return' then
      currentFilename = rtrim(currentFilename)

      save_painting(currentFilename)
      mode = MODES.NORMAL
    elseif key == 'escape' then
      mode = MODES.NORMAL
    elseif key == 'backspace' and #currentFilename > 0 then
      local byteoffset = utf8.offset(currentFilename, -1)
      if byteoffset then
        currentFilename = string.sub(currentFilename, 1, byteoffset - 1)
      end
    end

    return
  end

  if ctrlIsDown and shiftIsDown and key == 'c' then
    love.system.setClipboardText(get_painting_data())
  end

  -- allow certain commands during EDIT_FILL_PATTERN mode
  if not ctrlIsDown then
    if key == '9' then
      if cursor.patternIndex > 0 then
        set_fill_pattern(cursor.patternIndex - 1)
      end
    elseif key == '0' then
      if cursor.patternIndex < MAX_FILL_PATTERN_INDEX then
        set_fill_pattern(cursor.patternIndex + 1)
      end
    end
    if key == 'u' then
      if shiftIsDown then
        redo()
      else
        undo()
      end
    end
  end

  if mode == MODES.EDIT_FILL_PATTERN then
    local pbit = FILL_PATTERN_SCANCODES[scancode]
    if pbit then
      save_undo_state()
      toggle_pattern_bit(pbit)
      set_dirty_flag()
    end

    if key == 't' then
      save_undo_state()
      toggle_pattern_transparency()
      set_dirty_flag()
    end

    if key == 'escape' then
      mode = MODES.NORMAL
    end

    return
  end

  if ctrlIsDown then
    if key == 'n' then
      -- todo: confirm here, but window.showMessageBox with buttons is bugged

      save_undo_state()

      currentFilename = ''
      polygons = {}
      selectedShapes = {}
      selectedPoints = {}

      set_dirty_flag()
    elseif key == 's' then
      mode = MODES.SAVE

      -- don't let this key trigger anything else below
      return
    elseif key == 'c' and #selectedShapes > 0 then
      copy(selectedShapes)
    elseif key == 'v' and clipboard then
      save_undo_state()
      if mouseIsOnCanvas then
        paste(cursor.x, cursor.y)
      else
        paste(0, 0)
      end
    elseif key == 'f' then
      mode = MODES.EDIT_FILL_PATTERN
      return
    end
  elseif not shiftIsDown then
    -- switch tools
    if key == 'd' then
      cursor.tool = TOOLS.DRAW
      set_selected_shapes({})
      set_selected_points({})
    elseif key == 's' then
      cursor.tool = TOOLS.SELECT_SHAPE
    elseif key == 'p' then
      cursor.tool = TOOLS.SELECT_POINT
    elseif key == 'm' then
      cursor.tool = TOOLS.MOVE
    elseif key == 'c' then
      cursor.tool = TOOLS.CHANGE_COLOR
      update_color_change_tool()
    elseif key == 'f' then
      cursor.tool = TOOLS.CHANGE_FILL_PATTERN
      update_fill_pattern_change_tool()
    elseif key == 'b' then
      cursor.tool = TOOLS.BG_IMAGE
    end

    if tool ~= TOOLS.BG_IMAGE and #selectedShapes > 0 then
      local scaleDelta = .2
      if key == '-' or key == '_' then
        save_undo_state()
        scale_shapes(selectedShapes, 1 - scaleDelta)
      elseif key == '+' or key == '=' then
        save_undo_state()
        scale_shapes(selectedShapes, 1 + scaleDelta)
      end
    end

    if key == 'k' then
      set_mouse_only_mode(not mouseOnlyMode)
    end

    if key == 'z' or key == 'space' then
      push_primary_button()
    elseif key == 'return' then
      push_secondary_button()
    elseif key == 'i' then
      insert_point()
    elseif key == 'h' then
      selectionFlash:set_enabled(not selectionFlash:is_enabled())
    end
  end

  if bg.image then
    -- control background image opacity (actually shape canvas opacity)
    local oldCanvasOpacity = canvasOpacity
    if key == '<' or key == ',' then
      canvasOpacity = canvasOpacity + .1
    elseif key == '>' or key == '.' then
      canvasOpacity = canvasOpacity - .1
    end
    if canvasOpacity ~= oldCanvasOpacity then
      canvasOpacity = mid(0, canvasOpacity, 1)
      print('set canvas opacity to ' .. canvasOpacity)
    end
  end

  if cursor.tool == TOOLS.BG_IMAGE and bg.image then
    -- control background image scale
    local oldScale = bg.scale
    local delta = ctrlIsDown and .01 or .1
    if key == '0' then
      save_undo_state()
      bg.scale = 1
    elseif key == '-' or key == '_' then
      save_undo_state()
      bg.scale = bg.scale - delta
    elseif key == '+' or key == '=' then
      save_undo_state()
      bg.scale = bg.scale + delta
    end
    if bg.scale ~= oldScale then
      print('set background image scale to ' .. bg.scale)
    end
  end

  -- toggle fine-movement mode for the keyboard-cursor
  if key == 'k' and shiftIsDown then
    if mouseOnlyMode then
      set_mouse_only_mode(false)
      cursor.fineMode = true
    else
      cursor.fineMode = not cursor.fineMode
    end

    if not cursor.fineMode then
      -- halt the cursor's current momentum
      cursor.vx = 0
      cursor.vy = 0
    end
  end

  if key == 'left' or key == 'right' or key == 'up' or key == 'down' then
    push_direction(key)
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

  if key == 'q' then
    if cursor.bgColor > 0 then
      set_bg_color(cursor.bgColor - 1)
    end
  elseif key == 'w' then
    if cursor.bgColor < #palette then
      set_bg_color(cursor.bgColor + 1)
    end
  end

  if key == 'f5' then
    -- force re-render all polygons
    set_dirty_flag()
  end

  if key == '[' then
    -- push the selected polygons back by one in the stack
    local polys = get_target_polygons()
    for i = 1, #polys do
      push_polygon_back(polys[i])
    end
    set_dirty_flag()
  elseif key == ']' then
    -- pull the selected polygons forward by one in the stack
    local polys = get_target_polygons()
    for i = 1, #polys do
      pull_polygon_forward(polys[i])
    end
    set_dirty_flag()
  end

  if key == 'tab' then
    if cursor.tool ~= TOOLS.SELECT_POINT then
      if #selectedShapes == 0 then
        if #selectedPoints == 1 then
          local poly = selectedPoints[1].poly
          set_selected_shapes({poly})
        else
          local oldSelectionIsValid = false

          if oldSelectedShapes then
            oldSelectionIsValid = true
            for _, oldShape in pairs(oldSelectedShapes) do
              if not find_polygon_index(oldShape) then
                oldSelectionIsValid = false
                break
              end
            end
          end

          if oldSelectionIsValid then
            set_selected_shapes(oldSelectedShapes)
          else
            set_selected_shapes({polygons[1]})
          end
        end
      elseif #selectedShapes == 1 then
        local index = find_polygon_index(selectedShapes[1])

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

          set_selected_shapes({polygons[nextIndex]})
        end
      end
    end

    if cursor.tool == TOOLS.SELECT_POINT or
       (cursor.tool ~= TOOLS.SELECT_SHAPE and #selectedPoints > 0) then
      if #selectedPoints == 0 and #selectedShapes == 1 then
        local sp = {
          point = selectedShapes[1].points[1],
          poly = selectedShapes[1]
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
    set_selected_shapes({})
    set_selected_points({})
  end

  if key == 'delete' or key == 'backspace' then
    if #selectedShapes > 0 then
      save_undo_state()
      polygons = remove_values_from_table(selectedShapes, polygons)
      set_selected_shapes({})
      set_dirty_flag()
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

      set_dirty_flag()
    end
  end
end

function mid(min, n, max)
  return math.min(math.max(min, n), max)
end

function toggle_pattern_bit(i)
  local fillPattern = fillPatterns[cursor.patternIndex]
  local pattern = fillPattern.pattern

  if pattern[i] == 1 then
    pattern[i] = 0
  else
    pattern[i] = 1
  end
end

function toggle_pattern_transparency()
  local fillPattern = fillPatterns[cursor.patternIndex]
  fillPattern.isTransparent = not fillPattern.isTransparent
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

function push_direction(key)
  if cursor.tool == TOOLS.BG_IMAGE then
    save_undo_state()
    if key == 'left' then
      bg.offset.x = bg.offset.x - 1
    elseif key == 'right' then
      bg.offset.x = bg.offset.x + 1
    elseif key == 'up' then
      bg.offset.y = bg.offset.y - 1
    elseif key == 'down' then
      bg.offset.y = bg.offset.y + 1
    end
  elseif cursor.tool == TOOLS.MOVE or mouseOnlyMode then
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
end

function shift_is_down()
  return love.keyboard.isDown('lshift', 'rshift')
end

function push_primary_button()
  if not cursor.isVisible then
    return
  end

  local shiftIsDown = shift_is_down()

  if cursor.tool == TOOLS.SELECT_SHAPE or shiftIsDown then
    if cursor.hoveredPolygon then
      if shiftIsDown and #selectedShapes > 0 then
        -- look for this shape in the selectedShapes table
        local existingIndex = table_has_value(selectedShapes,
          cursor.hoveredPolygon)

        -- If this shape is already in the selectedShapes table
        if existingIndex then
          local newSelectedShapes = shallow_copy_table(selectedShapes)
          table.remove(newSelectedShapes, existingIndex)
          set_selected_shapes(newSelectedShapes)
        else
          local newSelectedShapes = shallow_copy_table(selectedShapes)
          table.insert(newSelectedShapes, cursor.hoveredPolygon)
          set_selected_shapes(newSelectedShapes)
        end
      else
        set_selected_shapes({cursor.hoveredPolygon})
      end
    elseif not shiftIsDown then
      set_selected_shapes({})
    end
  elseif cursor.tool == TOOLS.DRAW then
    draw_point()
  elseif cursor.tool == TOOLS.SELECT_POINT then
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
    elseif not shiftIsDown then
      set_selected_points({})
    end
  end
end

function push_secondary_button()
  if not cursor.isVisible then
    return
  end

  if cursor.tool == TOOLS.DRAW then
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

function get_fill_pattern_under_mouse(x, y)
  for i, box in pairs(fillPatternSelector.boxes) do
    if x >= box.x and x < box.x + box.w and
       y >= box.y and y < box.y + box.h then
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

  if #selectedShapes > 0 then
    targetPolys = selectedShapes
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

function set_bg_color(color)
  cursor.bgColor = color
  update_color_change_tool()
end

function set_color(color)
  cursor.color = color
  update_color_change_tool()
end

function update_color_change_tool()
  if not (cursor.tool == TOOLS.CHANGE_COLOR or #selectedShapes > 0) then
    return
  end

  local targetShapes = get_target_polygons()

  local anyColorsWillChange = false
  for _, shape in pairs(targetShapes) do
    if shape.color ~= cursor.color or shape.bgColor then
      anyColorsWillChange = true
      break
    end
  end

  if anyColorsWillChange then
    save_undo_state()

    -- change the color of all target shapes
    for _, shape in pairs(targetShapes) do
      shape.color = cursor.color
      shape.bgColor = cursor.bgColor
    end

    set_dirty_flag()
  end
end

function set_fill_pattern(index)
  cursor.patternIndex = index
  update_fill_pattern_change_tool()
  patternSelectionFlash:reset()
end

function update_fill_pattern_change_tool()
  if not (cursor.tool == TOOLS.CHANGE_FILL_PATTERN or #selectedShapes > 0) then
    return
  end

  local targetShapes = get_target_polygons()

  local anyPatternsIndiciesWillChange = false
  for _, shape in pairs(targetShapes) do
    if shape.patternIndex ~= cursor.patternIndex then
      anyPatternsIndiciesWillChange = true
      break
    end
  end

  if anyPatternsIndiciesWillChange then
    save_undo_state()

    -- change the pattern index of all target shapes
    for _, shape in pairs(targetShapes) do
      shape.patternIndex = cursor.patternIndex
    end

    set_dirty_flag()
  end
end

function table_has_value(t, value)
  for k, v in pairs(t) do
    if v == value then
      return k
    end
  end

  return false
end

function love.mousepressed(x, y, button)
  if mode == MODES.NORMAL then
    if button == 1 then
      if mouseIsOnCanvas then
        push_primary_button()
        return
      end

      local color = get_color_under_mouse(x, y)
      if color then
        set_color(color)
      end
    elseif button == 2 then
      if mouseIsOnCanvas then
        push_secondary_button()
        return
      end

      local color = get_color_under_mouse(x, y)
      if color then
        set_bg_color(color)
      end
    end
  end

  if mode == MODES.NORMAL or mode == MODES.EDIT_FILL_PATTERN then
    if button == 1 then
      local patternIndex = get_fill_pattern_under_mouse(x, y)
      if patternIndex then
        set_fill_pattern(patternIndex)
      end
    end
  end
end

function finalize_drawing_points()
  if #drawingPoints < 1 then
    return
  end

  save_undo_state()

  -- finalize the WIP polygon
  table.insert(polygons, {
    points = drawingPoints,
    color = cursor.color,
    bgColor = cursor.bgColor,
    patternIndex = cursor.patternIndex
  })

  if #selectedShapes == 0 then
    set_selected_shapes({polygons[#polygons]})
  end

  -- clear the WIP points
  drawingPoints = {}

  set_dirty_flag()
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

  set_dirty_flag()
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

function draw_shape(poly, rgba, disableFillPattern)
  love.graphics.setColor(rgba)
  love.graphics.setPointSize(1)
  love.graphics.setLineWidth(1)
  love.graphics.setLineStyle('rough')

  if #poly.points == 1 then
    -- draw a point
    love.graphics.points(poly.points[1].x + 0.5, poly.points[1].y + 0.5)
  elseif #poly.points == 2 then
    -- draw a line
    picolove.line(
      poly.points[1].x, poly.points[1].y,
      poly.points[2].x, poly.points[2].y)
  else
    -- draw a polygon
    fill_polygon(poly, disableFillPattern)
  end
end

function fill_polygon(poly, disableFillPattern)
  -- find the bounds of the polygon
  local x1, x2, y1, y2 = find_bounds(poly.points)

  for y = y2, y1, -1 do
    -- find intersecting nodes
    local xlist = find_intersections(poly.points, y)
    table.sort(xlist)

    for i = 1, #xlist - 1, 2 do
      local x1 = math.floor(xlist[i])
      local x2 = math.ceil(xlist[i + 1])

      if poly.patternIndex > 0 and not disableFillPattern then
        for x = x1, x2 do
          pset(x, y, poly.color, poly.bgColor, fillPatterns[poly.patternIndex])
        end
      else
        picolove.line(x1, y, x2, y)
      end
    end
  end
end

function get_pattern_bit(pattern, x, y)
  x = x % 4
  y = y % 4

  local index = ((4 * y) + x) + 1
  return pattern[index]
end

function pset(x, y, color, bgColor, fillPattern)
  local bit = get_pattern_bit(fillPattern.pattern, x, y)
  if bit == 1 then
    love.graphics.setColor(palette[color])
    love.graphics.points(x + 0.5, y + 0.5)
  elseif not fillPattern.isTransparent then
    love.graphics.setColor(palette[bgColor])
    love.graphics.points(x + 0.5, y + 0.5)
  end
end

function render_polygons()
  print('re-rendering all (' .. #polygons .. ') polygons')

  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 1)

  for i = 1, #polygons do
    local shape = polygons[i]
    draw_shape(shape, palette[shape.color])
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
    draw_shape(cursor.hoveredPolygon, hoverFlash:get_color(), true)
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

  if mode == MODES.NORMAL then
    -- draw a flashing overlay over the selected polygons
    for _, poly in pairs(selectedShapes) do
      draw_shape(poly, selectionFlash:get_color(), true)
    end
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

  love.graphics.setColor(1, 1, 1, canvasOpacity)

  -- draw the polygon canvas
  love.graphics.draw(canvas, canvasPos.x, canvasPos.y)

  love.graphics.setColor(1, 1, 1, 1)

  -- draw the tools cavnas on top of the polygon canvas
  love.graphics.draw(toolsCanvas, canvasPos.x, canvasPos.y)

  love.graphics.pop()
end

function point_to_string(point)
  return '(' .. point.x .. ', ' .. point.y .. ')'
end

function round1(n)
  return math.floor(n * 10) / 10
end

function draw_status()
  love.graphics.setColor(1, 1, 1)
  local x = (CANVAS_W * canvasScale) + (canvasMargin * 2)
  local y = canvasMargin
  local lineh = love.graphics.getFont():getHeight()

  love.graphics.print(#polygons .. ' shapes  ' ..
    '(' .. status.byteCount .. ' bytes)', x, y)
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

  if mode == MODES.EDIT_FILL_PATTERN then
    y = y + lineh
    love.graphics.print('current mode: ' .. 'edit fill-pattern', x, y)
  end

  y = y + lineh
  if mode == MODES.EDIT_FILL_PATTERN then
    love.graphics.setColor(.5, .5, .5)
  end
  love.graphics.print('current tool: ' .. TOOL_NAMES[cursor.tool], x, y)
  if mode == MODES.EDIT_FILL_PATTERN then
    love.graphics.setColor(1, 1, 1)
  end

  if not mouseOnlyMode then
    y = y + lineh

    if cursor.fineMode then
      love.graphics.print('fine keyboard-cursor movement enabled', x, y)
    else
      love.graphics.print('keyboard-friendly mode enabled', x, y)
    end
  end

  if cursor.tool == TOOLS.BG_IMAGE and bg.image then
    y = y + lineh
    love.graphics.print(
      'position: ' ..  point_to_string(bg.offset) .. '  ' ..
      'opacity: ' .. round1(1 - canvasOpacity) .. '  ' ..
      'scale: ' .. bg.scale,
      x, y)
  end

  if not selectionFlash:is_enabled() then
    y = y + lineh
    love.graphics.print('selection highlight disabled', x, y)
  end

  if cursor.hoveredPolygon then
    local index = find_polygon_index(cursor.hoveredPolygon)
    y = y + lineh
    love.graphics.print('hovered shape index: ' .. index, x, y)
  end

  local selectedPolys
  local selectionLabel = 'selected shape:'
  if #drawingPoints > 0 then
    selectedPolys = {{
        points = drawingPoints,
        color = cursor.color,
        bgColor = cursor.bgColor,
        patternIndex = cursor.patternIndex
    }}
    selectionLabel = 'drawing shape:'
  else
    selectedPolys = selectedShapes
  end

  y = 300

  if mode == MODES.EDIT_FILL_PATTERN then
    local indexString = cursor.patternIndex
    if cursor.patternIndex == 0 then
      indexString = 'none'
    end
    love.graphics.print('selected fill-pattern: ' .. indexString, x, y)
    y = y + lineh

    if cursor.patternIndex > 0 then
      local fillPattern = fillPatterns[cursor.patternIndex]
      local yn = fillPattern.isTransparent and 'yes' or 'no'
      love.graphics.print('  transparent secondary color: ' .. yn, x, y)
      y = y + lineh
    end
  elseif selectedPolys then
    if #selectedPolys == 1 then
      local shape = selectedPolys[1]

      love.graphics.print(selectionLabel, x, y)
      y = y + lineh

      local index = find_polygon_index(shape)
      if index then
        love.graphics.print('  index: ' .. find_polygon_index(shape),
          x, y)
        y = y + lineh
      end

      if shape.color then
        local colorTxt = {
          {1, 1, 1}, '  color: ',
          palette[shape.color], shape.color,
        }

        if shape.patternIndex > 0 then
          table.insert(colorTxt, palette[shape.bgColor])
          table.insert(colorTxt, ' ' .. shape.bgColor)
        end

        love.graphics.print(colorTxt, x, y)
        y = y + lineh

        love.graphics.print('  pattern index: ' .. shape.patternIndex, x, y)
        y = y + lineh
      end

      love.graphics.print('  points: ' .. #selectedPolys[1].points ..
        ' (' .. shape_type(selectedPolys[1]) .. ')', x, y)
      y = y + lineh
      local x2, y2 = x, y
      for i, point in pairs(selectedPolys[1].points) do
        local _, graphicsHeight = love.graphics.getDimensions()
        if y2 > graphicsHeight - (lineh * 2) then
          y2 = y
          x2 = x2 + 125
        end
        love.graphics.print('    ' .. i .. ': ' .. point_to_string(point),
          x2, y2)
        y2 = y2 + lineh
      end
    elseif #selectedPolys > 1 then
      love.graphics.print(
        'selected shapes: ' .. #selectedPolys, x, y)
      for _, shape in ipairs(selectedPolys) do
        local shapeType = shape_type(shape)
        local index = find_polygon_index(shape)
        y = y + lineh
        love.graphics.print('  ' .. shapeType .. ' ' .. index, x, y)
      end
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
      local shapeType = shape_type(groups[key][1].poly)

      love.graphics.print('  from ' .. shapeType .. ' ' .. key .. ':', x, y)
      y = y + lineh

      for j = 1, #groups[key] do
        local sp = groups[key][j]
        local index = find_point_index(sp.point, sp.poly)
        love.graphics.print('    ' .. index .. ' ' ..
          point_to_string(sp.point), x, y)
        y = y + lineh
      end
    end
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

function shape_type(shape)
  if #shape.points == 1 then
    return 'dot'
  elseif #shape.points == 2 then
    return 'line'
  end

  return 'polygon'
end

function draw_cursor()
  if cursor.isVisible == false or cursor.tool == TOOLS.MOVE then
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

  love.graphics.setColor(1, 1, 1)
  love.graphics.rectangle('line',
    paletteBox[cursor.color].x - (lineW / 2),
    paletteBox[cursor.color].y - (lineW / 2),
    paletteDisplay.colorW + lineW,
    paletteDisplay.colorH + lineW)
end

function render_fill_pattern_swatches()
  love.graphics.push()
  love.graphics.setCanvas(fillPatternSwatchCanvas)
  love.graphics.clear(0, 0, 0, 0)

  local startY = PATTERN_SWATCH_ROW_H
  for i, pattern in ipairs(fillPatterns) do
    love.graphics.push()
    love.graphics.translate(0, startY)

    for y = 0, PATTERN_SWATCH_H - 1 do
      for x = 0, PATTERN_SWATCH_W - 1 do
        pset(x, y, cursor.color, cursor.bgColor, pattern)
      end
    end

    startY = startY + PATTERN_SWATCH_ROW_H
    love.graphics.pop()
  end

  love.graphics.pop()
  love.graphics.setCanvas()
end

function update_fill_pattern_selector_position()
  local sel = fillPatternSelector

  sel.x = paletteDisplay.x + (paletteDisplay.colorW * 4) + (canvasScale * 2)
  sel.y = paletteDisplay.y
  sel.outlineW = (canvasScale * PATTERN_SWATCH_W) + (sel.outlineMargin * 2)
  sel.outlineH = (canvasScale * PATTERN_SWATCH_H) + (sel.outlineMargin * 2)

  for i = 0, MAX_FILL_PATTERN_INDEX do
    local y = sel.y + (i * PATTERN_SWATCH_ROW_H * canvasScale)

    sel.boxes[i].x = sel.x - sel.outlineMargin
    sel.boxes[i].y = y - sel.outlineMargin
    sel.boxes[i].w = sel.outlineW
    sel.boxes[i].h = sel.outlineH
  end
end

function draw_fill_pattern_selector()
  local sel = fillPatternSelector

  love.graphics.push()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.scale(canvasScale, canvasScale)
  love.graphics.draw(fillPatternSwatchCanvas,
    sel.x / canvasScale,
    sel.y / canvasScale)
  love.graphics.pop()

  -- Outline the patterns
  love.graphics.push()
  love.graphics.setLineWidth(1)
  love.graphics.setLineStyle('rough')

  for i, box in pairs(sel.boxes) do
    if i == cursor.patternIndex then
      if mode == MODES.EDIT_FILL_PATTERN then
        love.graphics.setColor(patternSelectionFlash:get_color())
      else
        love.graphics.setColor(1, 1, 1)
      end
    else
      love.graphics.setColor(.5, .5, .5)
    end

    if i == 0 then
      -- Draw a slash to indicate no fill pattern is here
      love.graphics.line(box.x, box.y,
        box.x + box.w - sel.outlineMargin,
        box.y + box.h - sel.outlineMargin)
    end

    love.graphics.rectangle('line', box.x, box.y, box.w, box.h)
  end

  love.graphics.pop()
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
    picolove.line(a.x, a.y, b.x, b.y)--, fillPatterns[cursor.patternIndex])

    -- draw a flashing handle on this point
    love.graphics.setColor(selectionFlash:get_color())
    love.graphics.points(a.x + 0.5, a.y + 0.5)
  end
end

-- apply a saved undo state
function apply_state(state)
  polygons = state.polygons
  drawingPoints = state.drawingPoints
  cursor.color = state.cursorColor
  cursor.tool = state.cursorTool
  bg = state.bg
  fillPatterns = state.fillPatterns
end

function undo()
  if undoIndex == 1 then
    print('no undo history remaining')
    return
  end

  if not undoHistory[undoIndex] then
    -- allow for redo
    table.insert(undoHistory, get_state())
  end

  undoIndex = undoIndex - 1
  local state = undoHistory[undoIndex]
  apply_state(state)

  -- clear selections because they point to non-existant objects now
  set_selected_shapes({})
  set_selected_points({})

  set_dirty_flag()
end

function redo()
  print(undoIndex)
  print(#undoHistory)

  if undoIndex < #undoHistory then
    undoIndex = undoIndex + 1
    local state = undoHistory[undoIndex]
    print('loaded undo state ' .. undoIndex)

    apply_state(state)

    set_selected_shapes({})
    set_selected_points({})
    set_dirty_flag()
  else
    print('no redo stack remaining')
  end
end

function get_state()
  local state = {}
  state.polygons = copy_table(polygons)
  state.drawingPoints = copy_table(drawingPoints)
  state.cursorColor = cursor.color
  state.cursorTool = cursor.tool
  state.bg = copy_table(bg)
  state.fillPatterns = copy_table(fillPatterns)

  return state
end

function save_undo_state()
  if #undoHistory == MAX_UNDO then
    table.remove(undoHistory, 1)
  else
    -- clear later states
    for i = undoIndex + 1, #undoHistory do
      table.remove(undoHistory, i)
    end
  end

  print('saving to undo slot ' .. undoIndex)
  undoHistory[undoIndex] = get_state()

  -- undoIndex points to the next undo slot which will be saved to
  undoIndex = undoIndex + 1
end

function toggle_fullscreen()
  local w, h, flags = love.window.getMode()
  if not flags.fullscreen then
    lastWindowMode = {
      w = w,
      h = h,
      flags = flags
    }
  end

  if flags.fullscreen then
    if lastWindowMode then
      love.window.setMode(
      lastWindowMode.w,
      lastWindowMode.h,
      lastWindowMode.flags)
    end
  else
    love.window.setFullscreen(not flags.fullscreen, 'desktop')
  end

  find_best_canvas_scale()
end

function draw_background_image()
  love.graphics.setColor(1, 1, 1)

  local imageSize = math.max(bg.image:getWidth(), bg.image:getHeight())
  local canvasSize = math.max(CANVAS_W, CANVAS_H)
  local baseScale = (canvasSize / imageSize) * canvasScale
  local scale = baseScale * bg.scale

  love.graphics.setScissor(
    canvasPos.x * canvasScale,
    canvasPos.y * canvasScale,
    CANVAS_W * canvasScale,
    CANVAS_H * canvasScale)

  love.graphics.draw(bg.image,
    (canvasPos.x * canvasScale) + bg.offset.x,
    (canvasPos.y * canvasScale) + bg.offset.y,
    0, scale, scale)

  love.graphics.setScissor()
end

function love.update()
  if not bg.image then
    canvasOpacity = 1
  end

  update_cursor()
  update_palette_display()
  update_fill_pattern_selector_position()
end

function love.draw()
  -- clear the screen
  love.graphics.setCanvas()
  love.graphics.clear(.04, .04, .04)

  if mode == MODES.SAVE then
    love.graphics.setColor(1, 1, 1)
    love.graphics.print('Enter filename to save to:', 20, 20)
    if currentFilename then
      love.graphics.print(currentFilename, 20, 40)
    end
    return
  end

  -- draw the current tool on the tools canvas
  draw_tool()

  if bg.image then
    draw_background_image()
  end

  if canvasIsDirty then
    -- update the total byte count
    status.byteCount = string.len(get_painting_data()) / 2

    -- redraw all shapes onto the painting canvas
    render_polygons()
    canvasIsDirty = false
  end

  -- draw the canvases onto the screen
  draw_canvases()

  -- draw status stuff
  draw_status()
  draw_palette()
  render_fill_pattern_swatches() -- debug
  draw_fill_pattern_selector()

  -- draw the cursor
  draw_cursor()
end
