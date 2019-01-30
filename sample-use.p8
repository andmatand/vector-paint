pico-8 cartridge // http://www.pico-8.com
version 16
__lua__

function _init()
  -- step 1: store data somewhere in cart rom.
  -- do this in your build process, e.g. in a separate build-cart, not in your
  -- distributable cart
  local data = '8403137964796d671c670c0438061c0a091b05330a4d245f4165645973417125600e45054c9a390c1f0f0f1e0d331049285b415f5f556d4169275d12430c4782221d1e1f1c25202b292c30252b1e4782203a1c3f1f472b4832412f3a293747823d463948374e3b5444554b4e46474782553651384f3e53445c45633e5e3747824b164718451e49245225591e541747823f2b3b2d39333d39463a4d33482c080e1c7d216a226b276b2a70287320731e7d040e2e75306c326b3075080e376c396a436b3b74427341753675406d8403236d21712771266e040e3069326933663167080e486c4a6a546b4c74537352754775516d0f0e596c5a6a5f69626e6275637761775f765a7658755a6f5f6e616c5c6b5a6c86035b725c715f705f725e745b74efbffff500'
  local len = #data / 2
  local addr = 0x1000 -- bottom half of gfx/map
  store_painting(data, addr)
  -- permanently store to dist cart
  --cstore(addr, addr, length, 'game.p8')

  -- step 2: read the previously stored data
  -- include this (and library code in tab 1) in your dist cart.
  -- address and length must be known.
  local reader = new_painting_reader(addr, len)
  shapes, patterns = parse_painting(reader)
end

function _update()
  -- disable scanline caching,
  -- and then uncomment for a
  -- surprise :)
  --wiggle(shapes)
end

function _draw()
  cls()

  -- draw all the shapes
  for shape in all(shapes) do
    draw_shape(shape, true) -- true enables scanline caching
  end

  print('cpu: ' .. stat(1) * 100 .. '%', 1, 1, 8)
  print('mem: ' .. stat(0) .. '/2048', 1, 7, 8)
end

function store_painting(hexstr, dest)
  local i = 1

  while i <= #hexstr do
    local byte = ('0x' .. sub(hexstr, i, i + 1)) + 0
    i = i + 2
    poke(dest, byte)
    dest += 1
  end
end

function wiggle(shapes)
  for _, s in pairs(shapes) do
    for p in all(s.points) do
      if not p.ox then
        p.ox = p.x
        p.oy = p.y
      end
      p.x = p.ox + rnd(2) - 1
      p.y = p.oy + rnd(2) - 1
    end
  end
end
-->8
-- vector-paint dist library

function draw_shape(shape, enablecache)
  local points = shape.points
  color(shape.col)
  fillp(patterns[shape.pi])

  if #points == 1 then
    pset(points[1].x, points[1].y)
  elseif #points == 2 then
    line(points[1].x, points[1].y, points[2].x, points[2].y)
  elseif #points >= 3 then
    fill_polygon(shape, enablecache)
  end
end

function find_bounds(points)
  local x1 = 32767
  local x2 = 0
  local y1 = 32767
  local y2 = 0
  for _, point in pairs(points) do
    x1 = min(x1, point.x)
    x2 = max(x2, point.x)
    y1 = min(y1, point.y)
    y2 = max(y2, point.y)
  end

  return x1, x2, y1, y2
end

function find_intersections(points, y)
  local xlist = {}
  local j = #points

  for i = 1, #points do
    local a = points[i]
    local b = points[j]

    if (a.y < y and b.y >= y) or (b.y < y and a.y >= y) then
      local x = a.x + (((y - a.y) / (b.y - a.y)) * (b.x - a.x))

      add(xlist, x)
    end

    j = i
  end

  return xlist
end

function fill_polygon(p, enablecache)
  if not p.linecache then
    p.linecache = {}

    local x1, x2, y1, y2 = find_bounds(p.points)
    for y = y2, y1, -1 do
      local xlist = find_intersections(p.points, y)
      sort(xlist)

      for i = 1, #xlist - 1, 2 do
        local x1 = flr(xlist[i])
        local x2 = ceil(xlist[i + 1])
        add(p.linecache, {x1 = x1, x2 = x2, y = y})
      end
    end
  end

  -- draw the cached scanlines
  for _, l in pairs(p.linecache) do
    line(l.x1, l.y, l.x2, l.y, p.col)
  end

  if not enablecache then
    p.linecache = nil
  end
end

function sort(t)
  for i = 2, #t do
    local j = i
    while j > 1 and t[j - 1] > t[j] do
      t[j - 1], t[j] = t[j], t[j - 1]
      j -= 1
    end
  end
end

function new_painting_reader(addr, len)
  return {
    offset = 0,
    addr = addr,
    len = len,

    get_next_byte = function(self)
      local byte = peek(self.addr + self.offset)
      self.offset += 1
      return byte
    end,

    eof = function(self)
      return self.offset >= self.len
    end,

    end_of_shapes = function(self, patterncount)
      if patterncount > 0 then
        return self.offset == self.len - (patterncount * 2) - 1
      else
        return self:eof()
      end
    end
  }
end

function parse_painting(reader)
  local shapes = {}
  local patterns = {}
  local maxpat = 0

  -- read each shape
  repeat
    local shape = {
      points = {}
    }

    -- read the fill-pattern index and point count
    local b1 = reader:get_next_byte()
    shape.pi = shr(band(b1, 0b11000000), 6)
    local pointcount = band(b1, 0b00111111)

    -- update running pattern count
    maxpat = max(maxpat, shape.pi)

    -- read the color
    shape.col = reader:get_next_byte()

    -- read each point
    for i = 1, pointcount do
      local x = reader:get_next_byte()
      local y = reader:get_next_byte() - 1
      add(shape.points, {x = x, y = y})
    end

    add(shapes, shape)
  until reader:end_of_shapes(maxpat)

  if maxpat > 0 then
    for i = 1, maxpat do
      local b1 = reader:get_next_byte()
      local b2 = reader:get_next_byte()
      local pattern = bor(shl(b1, 8), b2)
      add(patterns, pattern)
    end
    local tb = reader:get_next_byte()
    for i = 1, maxpat do
      local mask = shr(0b10000000, i - 1)
      if band(tb, mask) > 0 then
        patterns[i] += 0x0.8
      end
    end
  end

  return shapes, patterns
end

