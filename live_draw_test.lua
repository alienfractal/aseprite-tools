-- Aseprite Live Draw Test (experimental)
-- Cycles frames in the main editor using a Lua timer.
if not app.isUIAvailable then return end
if not app.sprite then
  app.alert("Open an animated sprite first.")
  return
end

local sprite = app.sprite
local timer = nil
local fps = 4

local function stop()
  if timer then
    timer:stop()
    timer = nil
  end
end

local dlg = Dialog{
  title = "Live Draw Test",
  onclose = function() stop() end
}

dlg:combobox{
  id = "fps",
  label = "Speed",
  option = "4 FPS",
  options = {"2 FPS", "4 FPS", "6 FPS", "8 FPS", "12 FPS"}
}

dlg:button{
  text = "Start / Restart",
  onclick = function()
    stop()
    if not app.sprite or app.sprite ~= sprite then
      app.alert("Switch back to the original sprite first.")
      return
    end
    fps = tonumber(dlg.data.fps:match("%d+")) or 4
    timer = Timer{
      interval = 1 / fps,
      ontick = function()
        if not app.sprite or app.sprite ~= sprite then
          stop()
          return
        end
        local count = #sprite.frames
        if count < 2 then
          stop()
          return
        end
        local current = app.frame.frameNumber
        app.frame = (current % count) + 1
        app.refresh()
      end
    }
    timer:start()
  end
}

dlg:button{ text = "Pause", onclick = stop }
dlg:button{ text = "Close", onclick = function() stop() dlg:close() end }
dlg:show{ wait = false }
