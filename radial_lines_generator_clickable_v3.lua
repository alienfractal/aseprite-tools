-- Radial Lines Generator with clickable center preview
-- Requires Aseprite 1.3+ (Dialog:canvas widget).

local sprite = app.sprite
if not sprite then
  app.alert("Open a sprite before running this script.")
  return
end

if app.apiVersion < 21 then
  app.alert("This version requires Aseprite 1.3 or newer.")
  return
end

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

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

local previewWidth = 320
local previewHeight = 240
local previewPadding = 10

local centerX = math.floor((sprite.width - 1) / 2)
local centerY = math.floor((sprite.height - 1) / 2)

-- Render the current frame as a flattened preview.
-- Image:drawSprite() composites the sprite's visible layers.
local previewImage = Image(sprite.spec)
previewImage:clear()
previewImage:drawSprite(sprite, app.frame.frameNumber)

local function getPreviewTransform()
  local availableW = previewWidth - previewPadding * 2
  local availableH = previewHeight - previewPadding * 2
  local scale = math.min(
    availableW / sprite.width,
    availableH / sprite.height
  )

  local drawW = sprite.width * scale
  local drawH = sprite.height * scale
  local offsetX = (previewWidth - drawW) / 2
  local offsetY = (previewHeight - drawH) / 2

  return scale, offsetX, offsetY, drawW, drawH
end

local defaultRadius = math.floor(math.sqrt(
  sprite.width * sprite.width + sprite.height * sprite.height
) / 2)

local dlg = Dialog("Radial Lines Generator")

dlg:label{
  text = "Click the sprite preview to choose the ray origin."
}

dlg:canvas{
  id = "pointPicker",
  width = previewWidth,
  height = previewHeight,
  hexpand = false,
  vexpand = false,

  onpaint = function(ev)
    local gc = ev.context
    local scale, ox, oy, drawW, drawH = getPreviewTransform()

    gc.color = Color{ r=35, g=35, b=35, a=255 }
    gc:fillRect(Rectangle(0, 0, previewWidth, previewHeight))

    gc:drawImage(
      previewImage,
      Rectangle(0, 0, sprite.width, sprite.height),
      Rectangle(
        math.floor(ox),
        math.floor(oy),
        math.max(1, math.floor(drawW)),
        math.max(1, math.floor(drawH))
      )
    )

    -- Sprite boundary.
    gc.color = Color{ r=180, g=180, b=180, a=255 }
    gc.strokeWidth = 1
    gc:strokeRect(Rectangle(
      math.floor(ox),
      math.floor(oy),
      math.max(1, math.floor(drawW)),
      math.max(1, math.floor(drawH))
    ))

    -- Crosshair at the selected center.
    local px = ox + (centerX + 0.5) * scale
    local py = oy + (centerY + 0.5) * scale
    local markerRadius = 7

    gc.color = Color{ r=255, g=60, b=60, a=255 }
    gc.strokeWidth = 2
    gc:beginPath()
    gc:moveTo(px - markerRadius, py)
    gc:lineTo(px + markerRadius, py)
    gc:moveTo(px, py - markerRadius)
    gc:lineTo(px, py + markerRadius)
    gc:stroke()

    gc:beginPath()
    gc:oval(Rectangle(
      px - 3,
      py - 3,
      6,
      6
    ))
    gc:stroke()

    -- Preview the center gap as a circle around the selected vanishing point.
    local previewGap = 6
    if dlg and dlg.data and dlg.data.centerGap then
      previewGap = math.max(0, dlg.data.centerGap)
    end
    local gapOnPreview = previewGap * scale
    if gapOnPreview > 0 then
      gc.strokeWidth = 1
      gc:beginPath()
      gc:oval(Rectangle(
        px - gapOnPreview,
        py - gapOnPreview,
        gapOnPreview * 2,
        gapOnPreview * 2
      ))
      gc:stroke()
    end
  end,

  onmousedown = function(ev)
    if ev.button ~= MouseButton.LEFT then
      return
    end

    local scale, ox, oy, drawW, drawH = getPreviewTransform()

    -- Ignore clicks outside the displayed sprite.
    if ev.x < ox or ev.y < oy or
       ev.x >= ox + drawW or ev.y >= oy + drawH then
      return
    end

    centerX = clamp(
      math.floor((ev.x - ox) / scale),
      0,
      sprite.width - 1
    )
    centerY = clamp(
      math.floor((ev.y - oy) / scale),
      0,
      sprite.height - 1
    )

    dlg:modify{ id="centerX", text=tostring(centerX) }
    dlg:modify{ id="centerY", text=tostring(centerY) }
    dlg:repaint()
  end
}

dlg:number{
  id = "centerX",
  label = "Center X:",
  text = tostring(centerX),
  decimals = 0,
  onchange = function()
    centerX = clamp(
      math.floor((dlg.data.centerX or centerX) + 0.5),
      0,
      sprite.width - 1
    )
    dlg:repaint()
  end
}

dlg:number{
  id = "centerY",
  label = "Center Y:",
  text = tostring(centerY),
  decimals = 0,
  onchange = function()
    centerY = clamp(
      math.floor((dlg.data.centerY or centerY) + 0.5),
      0,
      sprite.height - 1
    )
    dlg:repaint()
  end
}

dlg:number{
  id = "lineCount",
  label = "Number of lines:",
  text = "96",
  decimals = 0
}

dlg:number{
  id = "centerGap",
  label = "Center gap radius:",
  text = "6",
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
  id = "drawCenter",
  label = "Center marker:",
  text = "Draw center pixel",
  selected = false
}

dlg:button{ id = "ok", text = "Draw", focus = true }
dlg:button{ id = "cancel", text = "Cancel" }

dlg:show()

local data = dlg.data
if not data.ok then
  return
end

centerX = clamp(math.floor((data.centerX or centerX) + 0.5), 0, sprite.width - 1)
centerY = clamp(math.floor((data.centerY or centerY) + 0.5), 0, sprite.height - 1)

-- A high upper limit keeps the dialog useful for very fine perspective guides,
-- while preventing accidental extreme values from freezing Aseprite.
local lineCount = math.max(
  1,
  math.min(2000, math.floor((data.lineCount or 1) + 0.5))
)
local centerGap = math.max(
  0,
  math.floor((data.centerGap or 0) + 0.5)
)
local startAngle = tonumber(data.startAngle) or 0
local arcAngle = tonumber(data.arcAngle) or 360
local radius = math.max(1, math.floor((data.radius or 1) + 0.5))
local thickness = math.max(1, math.floor((data.thickness or 1) + 0.5))
local lineColor = data.lineColor
local drawCenter = data.drawCenter

local divisor
if math.abs(arcAngle) >= 360 then
  divisor = lineCount
else
  divisor = math.max(1, lineCount - 1)
end

app.transaction("Generate Radial Lines", function()
  -- Every execution creates a fresh output layer.
  local layer = sprite:newLayer()

  -- Give each layer a distinct, readable name.
  local baseName = "Radial Lines"
  local layerNumber = 1
  local candidateName = baseName

  local usedNames = {}
  for _, existingLayer in ipairs(sprite.layers) do
    usedNames[existingLayer.name] = true
  end

  while usedNames[candidateName] do
    layerNumber = layerNumber + 1
    candidateName = baseName .. " " .. layerNumber
  end

  layer.name = candidateName

  local frame = app.frame
  local cel = layer:cel(frame)
  if not cel then
    cel = sprite:newCel(layer, frame)
  end

  local brush = Brush{ size = thickness }

  for i = 0, lineCount - 1 do
    local fraction = i / divisor
    local angle = math.rad(startAngle + arcAngle * fraction)
    local dx = math.cos(angle)
    local dy = math.sin(angle)
    local x2, y2

    if data.lengthMode == "Canvas edge" then
      x2, y2 = rayToCanvasEdge(
        centerX, centerY, dx, dy, sprite.width, sprite.height
      )
    else
      x2 = centerX + dx * radius
      y2 = centerY + dy * radius
    end

    -- Start each ray outside the center gap. This leaves the vanishing point
    -- and any horizon line beneath it visible.
    local startX = centerX + dx * centerGap
    local startY = centerY + dy * centerGap

    local endX = math.floor(x2 + 0.5)
    local endY = math.floor(y2 + 0.5)
    local roundedStartX = math.floor(startX + 0.5)
    local roundedStartY = math.floor(startY + 0.5)

    -- Do not draw a reversed or zero-length ray when the gap is larger than
    -- the available distance to the endpoint.
    local endDistance = math.sqrt(
      (x2 - centerX) * (x2 - centerX) +
      (y2 - centerY) * (y2 - centerY)
    )

    if endDistance > centerGap then
      app.useTool{
        tool = "line",
        color = lineColor,
        brush = brush,
        points = {
          Point(roundedStartX, roundedStartY),
          Point(endX, endY)
        },
        cel = cel
      }
    end
  end

  if drawCenter then
    app.useTool{
      tool = "pencil",
      color = lineColor,
      brush = Brush{ size = thickness },
      points = { Point(centerX, centerY) },
      cel = cel
    }
  end
end)

app.refresh()
