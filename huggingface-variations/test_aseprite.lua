local dir=assert(app.params.dir)
local f=assert(io.open(app.fs.joinPath(dir,'aseprite-test-results.txt'),'w'))
local function log(s) f:write(tostring(s)..'\n');f:flush() end
local ok,err=xpcall(function()
  local api=dofile(app.fs.joinPath(dir,'HF Variations.lua'))
  local animation=dofile(app.fs.joinPath(dir,'HF Animation.lua'))
  assert(api.base64('hello')=='aGVsbG8=' and animation.base64('hello')=='aGVsbG8=')
  assert(api.base64('a')=='YQ==' and api.base64('ab')=='YWI=')
  assert(api.utf16('A')=='A\0' and animation.utf16('A')=='A\0')
  assert(api.psQuote("a'b")=="'a''b'" and animation.psQuote("a'b")=="'a''b'")
  local s=Sprite(8,6,ColorMode.INDEXED)
  local p=Palette(4)
  p:setColor(0,Color{r=0,g=0,b=0,a=0})
  p:setColor(1,Color{r=80,g=90,b=100})
  p:setColor(2,Color{r=180,g=150,b=120})
  p:setColor(3,Color{r=200,g=200,b=200})
  s:setPalette(p);s.transparentColor=0
  local im=Image(8,6,ColorMode.INDEXED)
  for y=1,4 do for x=2,5 do im:drawPixel(x,y,(x+y)%2+1) end end
  s.cels[1].image=im
  s.selection:select(Rectangle(2,1,4,4))
  local before=s.cels[1].image.bytes
  local path=app.fs.joinPath(dir,'test-reference.png')
  local bounds=api.exportReference(s,s.frames[1],path,true)
  assert(bounds.width==4 and bounds.height==4)
  local exported=Image{fromFile=path}
  assert(exported.colorMode==ColorMode.RGB and exported.width==4)
  assert(app.pixelColor.rgbaR(exported:getPixel(0,0))==180,'Indexed palette export incorrect')
  assert(s.colorMode==ColorMode.INDEXED and s.cels[1].image.bytes==before,'Original changed')
  assert(#api.paletteColors(s,s.frames[1])==3,'Palette transparency handling incorrect')
  local out=api.importResults({{path=path,seed=1},{path=path,seed=2}},'rock-test')
  assert(#out.frames==2 and out.width==4 and out.height==4)
  assert(out.colorMode==ColorMode.RGB)
  assert(out.layers[1]:cel(1).image:isEqual(exported))
  assert(out.layers[1]:cel(2).image:isEqual(exported))
  s:newEmptyFrame();s:newCel(s.layers[1],2,im,Point(0,0))
  local animationBounds=animation.exportFrame(s,2,path,true)
  assert(animationBounds.width==4 and animationBounds.height==4)
  local animationOut=animation.importFrames({{path=path,frame=1},{path=path,frame=2}},'animation-test',1.5)
  assert(#animationOut.frames==2 and animationOut.width==4 and animationOut.height==4)
  assert(math.abs(animationOut.frames[1].duration-0.75)<0.001)
  local sheetOut=animation.importSheet({path=path},'animation-test')
  assert(#sheetOut.frames==1 and sheetOut.width==4 and sheetOut.height==4)
  local actual=app.fs.joinPath(dir,'jobs','verify-qwen-generation','variation-01.png')
  if app.fs.isFile(actual) then
    local generated=api.importResults({{path=actual}},'cloud-rock-variation')
    local expected=Image{fromFile=actual}
    assert(generated.width==expected.width and generated.height==expected.height)
    assert(generated.cels[1].image:isEqual(expected),'Actual cloud result import changed pixels')
    generated:saveAs(app.fs.joinPath(dir,'jobs','verify-qwen-generation','rock-variation.aseprite'))
    log('PASS: actual cloud-generated PNG imported and saved as an Aseprite sprite')
  end
  log('PASS: Lua syntax, safe command encoding, indexed reference export, selection crop, palette extraction, original safety, variation and animation import as frames')
end,debug.traceback)
if not ok then log(err) end
f:close()
if not ok then error(err) end
