-- Radial Lines Generator for Aseprite
-- Creates evenly spaced rays from a chosen center point.
-- Tested against the current Aseprite Lua scripting API.

local sprite = app.sprite
if not sprite then
  app.alert("Open a sprite before running this script.")
  return
end

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

-- Finds where a ray starting at (cx, cy) intersects the sprite boundary.
local function rayToCanvasEdge(cx, cy, dx, dy, width, height)
  local bestT = math.huge

  if dx > 0 then
    bestT = math.min(bestT, (width - 1 - cx) / dx)
  elseif dx < 0 then
    bestT = math.min(bestT, (0 - cx) / dx)
  end

  if dy > 0 then
    bestT = math.min(bestT, (height - 1 - cy) / dy)
  elseif dy < 0 then
    bestT = math.min(bestT, (0 - cy) / dy)
  end

  if bestT == math.huge or bestT < 0 then
    bestT = 0
  end

  return cx + dx * bestT, cy + dy * bestT
end

local defaultRadius = math.floor(math.sqrt(
  sprite.width * sprite.width + sprite.height * sprite.height
) / 2)

local dlg = Dialog("Radial Lines Generator")

dlg:number{
  id = "centerX",
  label = "Center X:",
  text = tostring(math.floor((sprite.width - 1) / 2)),
  decimals = 0
}

dlg:number{
  id = "centerY",
  label = "Center Y:",
  text = tostring(math.floor((sprite.height - 1) / 2)),
  decimals = 0
}

dlg:number{
  id = "lineCount",
  label = "Number of lines:",
  text = "48",
  decimals = 0
}

dlg:number{
  id = "startAngle",
  label = "Start angle:",
  text = "0",
  decimals = 1
}

dlg:number{
  id = "arcAngle",
  label = "Arc angle:",
  text = "360",
  decimals = 1
}

dlg:combobox{
  id = "lengthMode",
  label = "Line length:",
  option = "Canvas edge",
  options = { "Canvas edge", "Fixed radius" }
}

dlg:number{
  id = "radius",
  label = "Radius:",
  text = tostring(defaultRadius),
  decimals = 0
}

dlg:number{
  id = "thickness",
  label = "Thickness:",
  text = "1",
  decimals = 0
}

dlg:color{
  id = "lineColor",
  label = "Color:",
  color = app.fgColor
}

dlg:check{
  id = "newLayer",
  label = "Output:",
  text = "Create new layer",
  selected = true
}

dlg:check{
  id = "drawCenter",
  label = "Center marker:",
  text = "Draw center pixel",
  selected = true
}

dlg:button{ id = "ok", text = "Draw", focus = true }
dlg:button{ id = "cancel", text = "Cancel" }

dlg:show()

local data = dlg.data
if not data.ok then
  return
end

local cx = clamp(math.floor(data.centerX + 0.5), 0, sprite.width - 1)
local cy = clamp(math.floor(data.centerY + 0.5), 0, sprite.height - 1)
local lineCount = math.max(1, math.floor(data.lineCount + 0.5))
local startAngle = tonumber(data.startAngle) or 0
local arcAngle = tonumber(data.arcAngle) or 360
local radius = math.max(1, math.floor(data.radius + 0.5))
local thickness = math.max(1, math.floor(data.thickness + 0.5))
local lineColor = data.lineColor
local createNewLayer = data.newLayer
local drawCenter = data.drawCenter

-- For a full circle, avoid drawing the first direction twice.
local divisor
if math.abs(arcAngle) >= 360 then
  divisor = lineCount
else
  divisor = math.max(1, lineCount - 1)
end

app.transaction("Generate Radial Lines", function()
  local layer = app.layer

  if createNewLayer then
    layer = sprite:newLayer()
    layer.name = "Radial Lines"
  elseif not layer or layer.isGroup or layer.isTilemap then
    error("Select a normal editable image layer.")
  end

  local frame = app.frame
  local cel = layer:cel(frame)

  if not cel then
    cel = sprite:newCel(layer, frame)
  end

  local brush = Brush{ size = thickness }

  for i = 0, lineCount - 1 do
    local fraction = (divisor == 0) and 0 or (i / divisor)
    local angleDegrees = startAngle + arcAngle * fraction
    local angle = math.rad(angleDegrees)

    local dx = math.cos(angle)
    local dy = math.sin(angle)
    local x2, y2

    if data.lengthMode == "Canvas edge" then
      x2, y2 = rayToCanvasEdge(
        cx, cy, dx, dy, sprite.width, sprite.height
      )
    else
      x2 = cx + dx * radius
      y2 = cy + dy * radius
    end

    x2 = math.floor(x2 + 0.5)
    y2 = math.floor(y2 + 0.5)

    app.useTool{
      tool = "line",
      color = lineColor,
      brush = brush,
      points = {
        Point(cx, cy),
        Point(x2, y2)
      },
      cel = cel
    }
  end

  if drawCenter then
    app.useTool{
      tool = "pencil",
      color = lineColor,
      brush = Brush{ size = math.max(1, thickness) },
      points = { Point(cx, cy) },
      cel = cel
    }
  end
end)

app.refresh()
