-- Revalia Obscura: editable silhouette gallery.
-- The master file stays in the art folder; save changes there to update the gallery.
local root='C:/Users/lien/Desktop/Gamejams/revaliaobscura/revaliaobscura/art/BlogPost-001/forest-stamp-library'
local file=io.open(root..'/forest-stamps.json','r')
if not file then if app.isUIAvailable then app.alert('Forest stamp manifest is missing: '..root) end return end
local items=json.decode(file:read('*a'));file:close()
local sheet=Image{fromFile=root..'/forest-stamps.aseprite'}
assert(sheet,'Cannot load forest-stamps.aseprite')
local crops={}
for i,item in ipairs(items) do
 crops[i]=Image(sheet,Rectangle(item.x,item.y,item.w,item.h))
 assert(not crops[i]:isEmpty(),'Empty stamp: '..item.name)
end
if not app.isUIAvailable then
 local test=Sprite(200,160,ColorMode.RGB)
 for i,im in ipairs(crops) do
  app.useTool{tool='pencil',brush=Brush(im),points={Point(100,80)},color=Color{r=108,g=140,b=80}}
 end
 local drawn=Image(test)
 assert(not drawn:isEmpty(),'Brush stamping produced no pixels')
 print('Gallery validated: '..#items..' nonempty stamps; custom brush stamping works')
 return
end
local selected=1
local page=1
local pageCount=math.ceil(#items/24)
local dlg=Dialog('Forest Stamp Gallery')
local function choose(i)
 if i<1 or i>#items then return end
 selected=i
 local s=items[i]
 dlg:modify{id='selected',text=s.name..'  '..s.w..'x'..s.h..' px'}
 dlg:repaint()
end
local function loadBrush()
 local target=app.sprite
 if not target then app.alert('Open your scene before loading a stamp.') return end
 local im=Image(crops[selected])
 if dlg.data.singleColor then
  local color=app.fgColor
  local pixel=app.pixelColor.rgba(color.red,color.green,color.blue,255)
  for it in im:pixels() do if app.pixelColor.rgbaA(it())>0 then it(pixel) end end
 end
 if dlg.data.flip then im:flip(FlipType.HORIZONTAL) end
 dlg:close()
 -- NewBrush is the supported UI command for loading an active pattern brush.
 local temp=Sprite(im.width,im.height,ColorMode.RGB)
 temp.cels[1].image=im
 temp.selection:select(Rectangle(0,0,im.width,im.height))
 app.command.NewBrush()
 temp:close()
 app.activeSprite=target
 app.tool='pencil'
 app.refresh()
end
dlg:label{id='selected',text=items[1].name..'  '..items[1].w..'x'..items[1].h..' px'}
dlg:canvas{id='gallery',width=320,height=372,autoscaling=true,
 onpaint=function(ev)
  local gc=ev.context
  gc.color=Color{r=29,g=21,b=37};gc:fillRect(Rectangle(0,0,320,372))
  for i=(page-1)*24+1,math.min(page*24,#items) do
   local im=crops[i]
   local slot=(i-1)%24
   local x=(slot%4)*80;local y=math.floor(slot/4)*62
   gc.color=i==selected and Color{r=79,g=109,b=111} or Color{r=39,g=43,b=55}
   gc:fillRect(Rectangle(x+1,y+1,78,60))
   local scale=math.min(2,60/im.width,43/im.height)
   local w=math.max(1,math.floor(im.width*scale));local h=math.max(1,math.floor(im.height*scale))
   gc:drawImage(im,Rectangle(0,0,im.width,im.height),Rectangle(x+math.floor((80-w)/2),y+3+math.floor((43-h)/2),w,h))
   gc.color=Color{r=199,g=186,b=142};gc:fillText(tostring(i),x+4,y+48)
  end
 end,
 onmousedown=function(ev) choose((page-1)*24+math.floor(ev.y/62)*4+math.floor(ev.x/80)+1) end}
dlg:label{id='page',text='Page 1 / '..pageCount}
dlg:button{text='Previous',onclick=function() page=math.max(1,page-1);dlg:modify{id='page',text='Page '..page..' / '..pageCount};choose((page-1)*24+1) end}
dlg:button{text='Next',onclick=function() page=math.min(pageCount,page+1);dlg:modify{id='page',text='Page '..page..' / '..pageCount};choose((page-1)*24+1) end}
dlg:newrow()
dlg:check{id='singleColor',text='Use foreground color',selected=false}
dlg:check{id='flip',text='Flip horizontally',selected=false}
dlg:newrow()
dlg:button{text='Load brush',onclick=loadBrush}
dlg:button{text='Edit master sheet',onclick=function() dlg:close();app.open(root..'/forest-stamps.aseprite') end}
dlg:button{text='Close',onclick=function() dlg:close() end}
dlg:show{wait=false}


