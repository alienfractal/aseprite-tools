-- BMF Text Renderer for Aseprite
-- Parses the Bytemap Font format used by bmf.wz.cz (versions through 1.1).

local MAGIC = { 0xE1, 0xE6, 0xD5, 0x1A }

local function readFile(filename)
  local handle, err = io.open(filename, "rb")
  if not handle then error("Cannot open BMF file: " .. tostring(err)) end
  local data = handle:read("*a")
  handle:close()
  return data
end

local Reader = {}
Reader.__index = Reader

function Reader.new(data)
  return setmetatable({ data = data, position = 1 }, Reader)
end

function Reader:u8()
  local value = string.byte(self.data, self.position)
  if value == nil then error("Unexpected end of BMF file") end
  self.position = self.position + 1
  return value
end

function Reader:s8()
  local value = self:u8()
  return value >= 128 and value - 256 or value
end

function Reader:u16le()
  local low, high = self:u8(), self:u8()
  return low + high * 256
end

function Reader:u32le()
  local b1, b2, b3, b4 = self:u8(), self:u8(), self:u8(), self:u8()
  return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

function Reader:bytes(length)
  if length < 0 or self.position + length - 1 > #self.data then
    error("Unexpected end of BMF file")
  end
  local result = self.data:sub(self.position, self.position + length - 1)
  self.position = self.position + length
  return result
end

local function parseBmf(filename)
  local reader = Reader.new(readFile(filename))
  for index = 1, 4 do
    if reader:u8() ~= MAGIC[index] then
      error("Not a Bytemap Font file (BMF signature missing)")
    end
  end

  local font = {
    version = reader:u8(),
    lineHeight = reader:u8(),
    sizeOver = reader:s8(),
    sizeUnder = reader:s8(),
    addSpace = reader:s8(),
    sizeInner = reader:s8(),
    usedColors = reader:u8(),
    highestColor = reader:u8(),
    reserved = reader:u32le(),
    colors = reader:u8(),
    palette = {},
    glyphs = {}
  }

  if font.version > 0x11 then
    error(string.format("Unsupported BMF version 0x%02X", font.version))
  end

  for index = 0, font.colors - 1 do
    font.palette[index] = {
      math.min(255, reader:u8() * 4),
      math.min(255, reader:u8() * 4),
      math.min(255, reader:u8() * 4)
    }
  end

  local titleLength = reader:u8()
  font.title = reader:bytes(titleLength)
  font.characterCount = reader:u16le()
  if font.characterCount > 256 then error("Invalid BMF character count") end

  for _ = 1, font.characterCount do
    local code = reader:u8()
    local glyph = {
      width = reader:u8(),
      height = reader:u8(),
      relx = reader:s8(),
      rely = reader:s8(),
      shift = reader:u8()
    }
    glyph.pixels = reader:bytes(glyph.width * glyph.height)
    font.glyphs[code] = glyph
  end
  return font
end

local function textBytes(text)
  -- Aseprite/Lua strings are UTF-8. BMF character IDs are single bytes.
  -- ASCII is direct; bytes 128-255 can be pasted if they use the expected codepage.
  local result = {}
  for index = 1, #text do result[#result + 1] = string.byte(text, index) end
  return result
end

local function layout(font, text, letterGap, lineGap, padding)
  local penX, penY = 0, 0
  local minX, minY = 0, 0
  local maxX, maxY = 1, math.max(1, font.lineHeight)
  local placements = {}
  local fallback = font.glyphs[string.byte("?")]

  for _, code in ipairs(textBytes(text)) do
    if code == 10 then
      penX = 0
      penY = penY + font.lineHeight + lineGap
      maxY = math.max(maxY, penY + font.lineHeight)
    elseif code ~= 13 then
      local glyph = font.glyphs[code] or fallback
      if glyph then
        placements[#placements + 1] = { glyph = glyph, x = penX + glyph.relx, y = penY + glyph.rely }
        minX = math.min(minX, penX + glyph.relx)
        minY = math.min(minY, penY + glyph.rely)
        maxX = math.max(maxX, penX + glyph.relx + glyph.width)
        maxY = math.max(maxY, penY + glyph.rely + glyph.height)
        penX = penX + glyph.shift + font.addSpace + letterGap
      else
        penX = penX + font.addSpace + letterGap
      end
      maxX = math.max(maxX, penX)
    end
  end

  return {
    placements = placements,
    minX = minX - padding,
    minY = minY - padding,
    width = math.max(1, maxX - minX + padding * 2),
    height = math.max(1, maxY - minY + padding * 2)
  }
end

local function render(font, text, letterGap, lineGap, padding, scale)
  local plan = layout(font, text, letterGap, lineGap, padding)
  local image = Image(plan.width * scale, plan.height * scale, ColorMode.RGB)
  image:clear(app.pixelColor.rgba(0, 0, 0, 0))

  for _, placement in ipairs(plan.placements) do
    local glyph = placement.glyph
    for y = 0, glyph.height - 1 do
      for x = 0, glyph.width - 1 do
        local colorIndex = string.byte(glyph.pixels, y * glyph.width + x + 1)
        if colorIndex and colorIndex ~= 0 then
          local color = font.palette[colorIndex]
          if color then
            local pixel = app.pixelColor.rgba(color[1], color[2], color[3], 255)
            local destinationX = (placement.x - plan.minX + x) * scale
            local destinationY = (placement.y - plan.minY + y) * scale
            for scaleY = 0, scale - 1 do
              for scaleX = 0, scale - 1 do
                image:putPixel(destinationX + scaleX, destinationY + scaleY, pixel)
              end
            end
          end
        end
      end
    end
  end
  return image
end

local function createSprite(font, text, letterGap, lineGap, padding, scale, outputFile)
  local image = render(font, text, letterGap, lineGap, padding, scale)
  local sprite = Sprite(image.width, image.height, ColorMode.RGB)
  sprite.cels[1].image = image
  sprite.layers[1].name = font.title ~= "" and font.title or "BMF Text"
  sprite.filename = ""
  app.refresh()
  if outputFile and outputFile ~= "" then
    sprite:saveCopyAs(outputFile)
  end
  return sprite
end

if not app.isUIAvailable then
  error("BMF Text Renderer requires Aseprite's user interface")
end

local dialog = Dialog("Render Bytemap Font")
dialog:file{
  id = "fontFile", label = "BMF file:", title = "Choose a Bytemap Font",
  open = true, filetypes = { "bmf" }
}
dialog:entry{ id = "text", label = "Text:", text = "HELLO WORLD" }
dialog:label{ text = "Use \\n inside Text for a new line." }
dialog:number{ id = "letterGap", label = "Letter gap:", text = "0", decimals = 0 }
dialog:number{ id = "lineGap", label = "Line gap:", text = "0", decimals = 0 }
dialog:number{ id = "padding", label = "Padding:", text = "1", decimals = 0 }
dialog:number{ id = "scale", label = "Pixel scale:", text = "1", decimals = 0 }
dialog:file{
  id = "outputFile", label = "Optional PNG:", title = "Export PNG",
  save = true, filetypes = { "png" }
}
dialog:button{
  id = "render", text = "Render",
  onclick = function()
    local values = dialog.data
    if not values.fontFile or values.fontFile == "" then
      app.alert("Choose a .bmf file first.")
      return
    end
    local ok, result = pcall(function()
      local font = parseBmf(values.fontFile)
      local text = (values.text or ""):gsub("\\n", "\n")
      return createSprite(
        font, text,
        math.floor(tonumber(values.letterGap) or 0),
        math.floor(tonumber(values.lineGap) or 0),
        math.max(0, math.floor(tonumber(values.padding) or 1)),
        math.max(1, math.floor(tonumber(values.scale) or 1)),
        values.outputFile
      )
    end)
    if not ok then app.alert("BMF render failed:\n" .. tostring(result)) end
  end
}
dialog:button{ id = "close", text = "Close" }
dialog:show{ wait = false }
