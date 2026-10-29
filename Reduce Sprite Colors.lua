-- Aseprite 1.3.x. No dependencies. Entire sprite, all frames and layers.
-- Indexed pixels are decoded through the palette, clustered as colors, and
-- explicitly remapped to a compact palette. No RGB round-trip is required.
local pc = app.pixelColor
local function distance(a,b)
  return 2*(a.r-b.r)^2 + 4*(a.g-b.g)^2 + 3*(a.b-b.b)^2
end
local function nearest(p, centers)
  local best, d = 1, math.huge
  for i,c in ipairs(centers) do
    local v = distance(p,c)
    if v < d then best,d = i,v end
  end
  return best,d
end

-- Deterministic frequency-weighted k-means over unique colors, not indices.
local function cluster(points,k,iterations,original)
  if k >= #points then return points end
  local centers = {points[1]}
  local closest = {}
  for _=2,k do
    local best,score = nil,-1
    for i,p in ipairs(points) do
      local d = distance(p,centers[#centers])
      closest[i] = math.min(closest[i] or math.huge,d)
      local v = closest[i]*p.weight
      if v > score then best,score = p,v end
    end
    centers[#centers+1] = best
  end
  for _=1,iterations do
    local sums = {}
    for i=1,k do sums[i]={r=0,g=0,b=0,weight=0} end
    for _,p in ipairs(points) do
      local i = nearest(p,centers)
      local s = sums[i]
      s.r=s.r+p.r*p.weight; s.g=s.g+p.g*p.weight
      s.b=s.b+p.b*p.weight; s.weight=s.weight+p.weight
    end
    local shift = 0
    for i,s in ipairs(sums) do
      if s.weight > 0 then
        local c={r=s.r/s.weight,g=s.g/s.weight,b=s.b/s.weight}
        shift=shift+distance(c,centers[i]); centers[i]=c
      end
    end
    if shift < 0.001 then break end
  end
  -- Pick the nearest real member of each cluster, or round the mean.
  local chosen,errors = {},{}
  if original then
    for _,p in ipairs(points) do
      local i,d=nearest(p,centers)
      if not errors[i] or d<errors[i] then chosen[i],errors[i]=p,d end
    end
  end
  local result,seen={},{}
  for i,c in ipairs(centers) do
    if original then
      -- An empty cluster still needs a real source swatch.
      c=chosen[i] or points[nearest(c,points)]
    end
    local r,g,b=math.floor(c.r+0.5),math.floor(c.g+0.5),math.floor(c.b+0.5)
    local key=pc.rgba(r,g,b,255)
    if not seen[key] then
      result[#result+1]={r=r,g=g,b=b};seen[key]=true
    end
  end
  return result
end

local function reduce(source,opts)
  assert(source,'Open a sprite first.')
  assert(source.colorMode==ColorMode.RGB or source.colorMode==ColorMode.INDEXED,
    'Use an RGB or indexed sprite.')
  assert(#source.palettes==1,
    'Sprites with palette changes between frames are not supported. No changes applied.')
  local function validate(layers)
    for _,l in ipairs(layers) do
      assert(not l.isTilemap,'Tilemap layers are not supported. No changes applied.')
      if l.isGroup then validate(l.layers) end
    end
  end
  validate(source.layers)
  local target=tonumber(opts.colors)
  assert(target and target==math.floor(target) and target>=2 and target<=256,
    'Choose a total palette size from 2 to 256.')
  local iterations=tonumber(opts.iterations) or 24
  assert(iterations>=1 and iterations<=100 and iterations==math.floor(iterations),
    'Iterations must be an integer from 1 to 100.')
  local indexed=source.colorMode==ColorMode.INDEXED
  local pal=source.palettes[1]
  local decoded={}
  if indexed then
    for i=0,#pal-1 do
      local c=pal:getColor(i)
      decoded[i]=pc.rgba(c.red,c.green,c.blue,c.alpha)
    end
  end
  local function rgba(raw,background)
    if not indexed then return raw end
    if raw==source.transparentColor and not background then return 0 end
    assert(decoded[raw]~=nil,'A pixel references a missing palette entry.')
    local c=decoded[raw]
    -- On a background the mask index uses its actual palette color/alpha.
    return c
  end
  local histogram,groups={},{}
  local transparent=indexed -- Reserve a mask index even on opaque indexed art.
  for _,cel in ipairs(source.cels) do
    for px in cel.image:pixels() do
      local c=rgba(px(),cel.layer.isBackground)
      local a=pc.rgbaA(c)
      if a==0 then transparent=true
      else histogram[c]=(histogram[c] or 0)+1 end
    end
  end
  local points={}
  for c,count in pairs(histogram) do
    points[#points+1]={r=pc.rgbaR(c),g=pc.rgbaG(c),b=pc.rgbaB(c),
      a=pc.rgbaA(c),weight=count,key=c}
  end
  table.sort(points,function(a,b)
    if a.weight~=b.weight then return a.weight>b.weight end
    return a.key<b.key
  end)
  for _,p in ipairs(points) do
    local g=groups[p.a]
    if not g then g={points={},weight=0,slots=1};groups[p.a]=g end
    g.points[#g.points+1]=p; g.weight=g.weight+p.weight
  end
  local alphas={}
  for a in pairs(groups) do alphas[#alphas+1]=a end
  table.sort(alphas)
  local budget=target-(transparent and 1 or 0)
  assert(#alphas<=budget,
    'Too many distinct opacity levels for this size. Increase the color count to preserve alpha.')
  -- Allocate at least one color per alpha level to preserve exact pixel alpha.
  for _=#alphas+1,math.min(budget,#points) do
    local best,score=nil,-1
    for _,a in ipairs(alphas) do
      local g=groups[a]
      local v=g.weight/(g.slots+1)
      if g.slots<#g.points and v>score then best,score=g,v end
    end
    if not best then break end
    best.slots=best.slots+1
  end
  local colors={}
  if transparent then colors[1]=pc.rgba(0,0,0,0) end
  local mapping={}
  for _,a in ipairs(alphas) do
    local g=groups[a]
    local centers=cluster(g.points,g.slots,iterations,opts.original~=false)
    table.sort(centers,function(x,y)
      local lx,ly=2*x.r+4*x.g+3*x.b,2*y.r+4*y.g+3*y.b
      if lx~=ly then return lx<ly end
      if x.r~=y.r then return x.r<y.r end
      if x.g~=y.g then return x.g<y.g end
      return x.b<y.b
    end)
    local offset=#colors
    for _,c in ipairs(centers) do colors[#colors+1]=pc.rgba(c.r,c.g,c.b,a) end
    for _,p in ipairs(g.points) do
      local i=nearest(p,centers)
      mapping[p.key]=offset+i-1
    end
  end
  if #colors==0 then colors[1]=0 end
  local resultPal=Palette(#colors)
  for i,c in ipairs(colors) do
    resultPal:setColor(i-1,Color{r=pc.rgbaR(c),g=pc.rgbaG(c),b=pc.rgbaB(c),a=pc.rgbaA(c)})
  end
  -- All validation and clustering finish before any document is changed.
  local sprite=source
  if opts.copy~=false then
    sprite=Sprite(source)
    sprite.filename=app.fs.fileTitle(source.filename)..'-reduced.aseprite'
  end
  app.sprite=sprite
  local ok,err=pcall(function()
    local changes,seen={},{}
    for _,cel in ipairs(sprite.cels) do
      local im=cel.image
      if not seen[im.id] then
        seen[im.id]=true
        local copy=Image(im)
        for px in copy:pixels() do
          local c=rgba(px(),cel.layer.isBackground)
          local index=pc.rgbaA(c)==0 and 0 or mapping[c]
          assert(index~=nil,'Missing color mapping.')
          px(indexed and index or colors[index+1])
        end
        changes[#changes+1]={image=im,copy=copy}
      end
    end
    app.transaction('Reduce sprite colors',function()
      for _,change in ipairs(changes) do
        change.image:drawImage(change.copy,Point(0,0),255,BlendMode.SRC)
      end
      sprite:setPalette(resultPal)
      if indexed then sprite.transparentColor=0 end
    end)
  end)
  if not ok then
    if sprite~=source then sprite:close();app.sprite=source end
    error(err)
  end
  app.refresh()
  return sprite,{before=#points,after=#colors-(transparent and 1 or 0),entries=#colors}
end

if app.params.testload=='1' then return reduce end
if not app.isUIAvailable then
  return reduce(app.sprite,{colors=app.params.colors or 32,
    iterations=app.params.iterations or 24,original=app.params.original~='0',
    copy=app.params.copy~='0'})
end
if not app.sprite then app.alert('Open a sprite first.');return end
local d=Dialog('Reduce Sprite Colors')
d:number{id='colors',label='Total colors:',text='32',decimals=0}
d:number{id='iterations',label='K-means passes:',text='24',decimals=0}
d:check{id='original',text='Use original swatches',selected=true}
d:check{id='copy',text='Create a reduced copy',selected=true}
d:label{text='All frames and layers share one reduced palette.'}
d:label{text='Indexed stays indexed; RGB stays RGB. No dithering.'}
d:label{text='Transparency counts as one slot; exact alpha is preserved.'}
d:button{text='Reduce colors',onclick=function()
  local ok,result,stats=pcall(reduce,app.sprite,d.data)
  if not ok then app.alert(tostring(result));return end
  d:close()
  app.alert{title='Colors reduced',text={
    string.format('%d -> %d nontransparent colors; %d palette entries.',stats.before,stats.after,stats.entries),
    'Nothing saved to disk. Use Save As to keep the result.',
    'One Undo restores an in-place reduction.'}}
end}
d:button{text='Cancel',onclick=function() d:close() end}
d:show()
