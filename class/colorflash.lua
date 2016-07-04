ColorFlash = {}
ColorFlash.__index = ColorFlash

function ColorFlash.new(delay, colors)
  local obj = {
    time = 0,
    delay = delay,
    colors = colors,
    colorIndex = 1
  }
  setmetatable(obj, ColorFlash)

  return obj
end

function ColorFlash:reset()
  self.time = love.timer.getTime()
  self.colorIndex = 1
end

function ColorFlash:update()
  if love.timer.getTime() >= self.time + self.delay then
    self.time = love.timer.getTime()

    self.colorIndex = self.colorIndex + 1
    if self.colorIndex > #self.colors then
      self.colorIndex = 1
    end
  end
end

function ColorFlash:get_color()
  return self.colors[self.colorIndex]
end
