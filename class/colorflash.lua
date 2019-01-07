ColorFlash = {}
ColorFlash.__index = ColorFlash

function ColorFlash.new(delay, colors)
  local obj = {
    time = 0,
    delay = delay,
    colors = colors,
    colorIndex = 1,
    enabled = true
  }
  setmetatable(obj, ColorFlash)

  return obj
end

function ColorFlash:is_enabled()
  return self.enabled
end

function ColorFlash:set_enabled(enabled)
  self.enabled = enabled
end

function ColorFlash:reset()
  self.time = love.timer.getTime()
  self.colorIndex = 1
  self.enabled = true
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
  if self.enabled then
    return self.colors[self.colorIndex]
  end

  return {0, 0, 0, 0}
end
