-- Forest-specific ordering. Reorders the actual palette and remaps indexed cels.
-- Edit these hex lists to customize the artistic roles, then run again.
local groups = {
 {name='Near: deep shadows and bark', colors='040303 1D1525 222222 24243B 17173A 292967 271417 3F3232 4E282E 5C4A4A 524A44 755E5E 75423E 72675A'},
 {name='Near: foliage', colors='1B3A2F 2B674E 3E996B 6C8C50 67C176'},
 {name='Near: warm / vivid accents', colors='4A0000 6A0000 8B0000 A13D3B B96D5B C78B50 D88038 E9A049 F78863 F7AD94 E3D245 F0D472 9A407E EA00FF'},
 {name='Middle: muted materials', colors='272B37 3D4356 47416B 6F726E 9C937C AB8989 C7BA8E'},
 {name='Far: cool atmosphere', colors='2A6A6A 4F6D6F 467E9C 687393 579DC2 7D9C9C 8A8FC4 9EC6C6'},
 {name='Neutral / light accents (not depth)', colors='9F9F9F B6BBB4 C2C2C2 E2E2E2 F1E9CD F9F5EF'},
}
local anchors={}
for g,group in ipairs(groups) do
 local order=0
 for hex in group.colors:gmatch('%x+') do
  order=order+1
  anchors[#anchors+1]={r=tonumber(hex:sub(1,2),16),g=tonumber(hex:sub(3,4),16),b=tonumber(hex:sub(5,6),16),group=g,order=order}
 end
end
local function sortSprite(s)
 assert(s,'Open a sprite first.')
 assert(s.colorMode~=ColorMode.GRAY,'Use an RGB or indexed sprite.')
 assert(#s.palettes==1,'This version supports one palette only; animation palette changes are not supported.')
 local function check(layers)
  for _,l in ipairs(layers) do
   assert(not l.isTilemap,'Tilemaps are not supported by this version.')
   if l.isGroup then check(l.layers) end
  end
 end
 check(s.layers)
 local pal=s.palettes[1]
 local fixed=s.colorMode==ColorMode.INDEXED and s.transparentColor or -1
 local items={}
 for i=0,#pal-1 do
  if i~=fixed then
   local c=pal:getColor(i);local best,dist=nil,math.huge
   for _,a in ipairs(anchors) do
    local d=2*(c.red-a.r)^2+4*(c.green-a.g)^2+3*(c.blue-a.b)^2
    if d<dist then best,dist=a,d end
   end
   items[#items+1]={old=i,c=c,group=c.alpha==0 and 7 or best.group,order=best.order,dist=dist}
  end
 end
 table.sort(items,function(a,b)
  if a.group~=b.group then return a.group<b.group end
  if a.order~=b.order then return a.order<b.order end
  if a.dist~=b.dist then return a.dist<b.dist end
  return a.old<b.old
 end)
 local sorted=Palette(#pal);local map={};local pos=0
 if fixed>=0 then sorted:setColor(fixed,pal:getColor(fixed));map[fixed]=fixed end
 for _,e in ipairs(items) do
  if pos==fixed then pos=pos+1 end
  sorted:setColor(pos,e.c);map[e.old]=pos;pos=pos+1
 end
 -- Prepare detached images first. Keep shared cel images linked by patching once.
 local changes,seen={},{}
 if s.colorMode==ColorMode.INDEXED then
  for _,cel in ipairs(s.cels) do
   local im=cel.image
   if not seen[im.id] then
    seen[im.id]=true
    local copy=Image(im)
    for p in copy:pixels() do
     assert(map[p()]~=nil,'A pixel references a missing palette entry. No changes applied.')
     p(map[p()])
    end
    changes[#changes+1]={image=im,copy=copy}
   end
  end
 end
 local fg,bg=app.fgColor,app.bgColor
 app.transaction('Sort palette by forest distance',function()
  for _,change in ipairs(changes) do
   change.image:drawImage(change.copy,Point(0,0),255,BlendMode.SRC)
  end
  s:setPalette(sorted)
 end)
 if s.colorMode==ColorMode.INDEXED then
  app.fgColor=Color{index=map[fg.index] or fixed}
  app.bgColor=Color{index=map[bg.index] or fixed}
 end
 app.refresh()
 return map
end
if app.params.testload=='1' then return sortSprite end
if not app.isUIAvailable then sortSprite(app.sprite);return end
local d=Dialog('Forest distance palette')
d:label{text='Reorders the actual palette: near > middle > far.'}
d:label{text='Neutral/light accents are kept together at the end.'}
d:label{text='Indexed pixels are remapped to preserve their colors.'}
d:label{text='One Undo restores the palette and pixels. No auto-save.'}
d:button{text='Sort palette',onclick=function()
 local ok,err=pcall(sortSprite,app.sprite)
 if ok then d:close() else app.alert(tostring(err)) end
end}
d:button{text='Cancel',onclick=function() d:close() end}
d:show()
