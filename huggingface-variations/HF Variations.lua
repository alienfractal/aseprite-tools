-- Windows Aseprite 1.3.x. Keep this file beside hf_bridge.py and launch.ps1.
local origin=debug.getinfo(1,'S').source
assert(origin:sub(1,1)=='@','Run this as a saved Lua script.')
local root=app.fs.filePath(origin:sub(2))
local function readJson(path)
  local f=io.open(path,'rb');if not f then return nil end
  local text=f:read('*a');f:close()
  text=text:gsub('^\239\187\191','')
  local ok,result=pcall(json.decode,text)
  return ok and result or nil
end
local function writeJson(path,data)
  local f=assert(io.open(path,'wb'));f:write(json.encode(data));f:close()
end
local function base64(s)
  local chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  local out={}
  for i=1,#s,3 do
    local a,b,c=s:byte(i,i+2);b=b or 0;c=c or 0
    local n=(a<<16)|(b<<8)|c
    out[#out+1]=chars:sub(((n>>18)&63)+1,((n>>18)&63)+1)
    out[#out+1]=chars:sub(((n>>12)&63)+1,((n>>12)&63)+1)
    out[#out+1]=i+1<=#s and chars:sub(((n>>6)&63)+1,((n>>6)&63)+1) or '='
    out[#out+1]=i+2<=#s and chars:sub((n&63)+1,(n&63)+1) or '='
  end
  return table.concat(out)
end
local function utf16(s)
  local out={}
  for _,n in utf8.codes(s) do
    if n>65535 then
      n=n-65536;local hi=55296+(n>>10);local lo=56320+(n&1023)
      out[#out+1]=string.pack('<I2I2',hi,lo)
    else out[#out+1]=string.pack('<I2',n) end
  end
  return table.concat(out)
end
local function psQuote(s) return "'"..s:gsub("'","''").."'" end
local function launch(jobPath,accounts)
  assert(app.fs.isFile(app.fs.joinPath(root,'.venv','Scripts','pythonw.exe')),
    'Run Setup.cmd in the HF Variations folder first.')
  local command="& "..psQuote(app.fs.joinPath(root,'launch.ps1'))
  if accounts then command=command..' -Accounts'
  else command=command..' -JobPath '..psQuote(jobPath) end
  -- Only base64 enters the shell command. Prompts and tokens never do.
  local encoded=base64(utf16(command))
  local ok=os.execute('powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand '..encoded)
  assert(ok,'Could not launch the bridge. Check Setup.cmd and Windows script permissions.')
end
local function exportReference(sprite,frame,path,useSelection)
  local rendered=Image(sprite.width,sprite.height,ColorMode.RGB)
  rendered:drawSprite(sprite,frame.frameNumber)
  local bounds=Rectangle(0,0,sprite.width,sprite.height)
  if useSelection and not sprite.selection.isEmpty then
    bounds=sprite.selection.bounds:intersect(bounds)
    assert(bounds.width>0 and bounds.height>0,'Selection is outside the canvas.')
    rendered=Image(rendered,bounds)
  end
  rendered:saveAs(path)
  return bounds
end
local function paletteColors(sprite,frame)
  local pal=sprite.palettes[1]
  for i=1,#sprite.palettes do
    local p=sprite.palettes[i]
    if p.frame.frameNumber<=frame.frameNumber then pal=p end
  end
  local colors,seen={},{}
  for i=0,#pal-1 do
    local c=pal:getColor(i)
    if c.alpha>0 and not (sprite.colorMode==ColorMode.INDEXED and i==sprite.transparentColor and not sprite.backgroundLayer) then
      local key=c.red..','..c.green..','..c.blue
      if not seen[key] then colors[#colors+1]={c.red,c.green,c.blue};seen[key]=true end
    end
  end
  return colors
end
local function importResults(files,title)
  if not files or #files==0 then return nil end
  local images={}
  for _,entry in ipairs(files) do
    local im=Image{fromFile=entry.path}
    assert(im and im.colorMode==ColorMode.RGB,'Could not load a generated PNG.')
    images[#images+1]=im
  end
  local first=images[1]
  for _,im in ipairs(images) do
    assert(im.width==first.width and im.height==first.height,'Generated image sizes differ; open the PNGs individually from the job folder.')
  end
  local result=Sprite(first.width,first.height,ColorMode.RGB)
  result.filename=title..'-variations.aseprite'
  result.layers[1].name='Generated variations'
  app.transaction('Import Hugging Face variations',function()
    result.cels[1].image=first
    for i=2,#images do result:newEmptyFrame();result:newCel(result.layers[1],i,images[i],Point(0,0)) end
    for _,frame in ipairs(result.frames) do frame.duration=0.2 end
  end)
  app.sprite=result;app.frame=result.frames[1];app.refresh()
  return result
end
if app.params.testload=='1' then
  return {exportReference=exportReference,importResults=importResults,paletteColors=paletteColors,
    base64=base64,utf16=utf16,psQuote=psQuote,launch=launch}
end
assert(app.isUIAvailable,'Run HF Variations from the Aseprite Scripts menu.')
local defaults={
  space='lienthealien/Qwen-Image-Edit-2511-LoRAs-Fast',account='default',endpoint='/infer',lora='Pixel-Art-Refiner',
  prompt='Create one different rock based on this reference. Vary the silhouette, chips and cracks. Preserve its pixel-art style, pixel size, limited palette, material, perspective and lighting direction. One isolated rock, centered, fully visible, same plain background. No text, no extra objects.',
  count=4,seed=-1,steps=4,guidance=1,selection=true,resize=true,upscale=true,match_palette=false,
  background='#ffffff',style='(No style)',lora_strength=1,backend='Qwen image edit',
  strength=0.45,model='Juggernaut XL - Ragnarok',sdxl_style='(No style)',sdxl_lora='None',
  negative_prompt='text, watermark, blurry, multiple objects, photorealistic',
  vision_space='lienthealien/mage-vl-demo',vision_max_tokens=384,
  vision_question='Describe this image accurately for a downstream image or animation generation prompt. Focus on the subject, pose, visual details, composition, camera angle, pixel-art style, palette, lighting, and background. Do not invent motion or unseen details.'
}
local qwenPrompt=defaults.prompt
local saved=readJson(app.fs.joinPath(root,'settings.local.json')) or {}
for k in pairs(defaults) do if saved[k]~=nil then defaults[k]=saved[k] end end
local qwenLoras={'Pixel-Art-Refiner','Pixel-Art-Spritesheet','Style-Transfer','Multiple-Angles'}
local knownApi=readJson(app.fs.joinPath(root,'jobs','verify-space','api-info.json'))
if knownApi and knownApi.named_endpoints and knownApi.named_endpoints['/infer'] then
  for _,p in ipairs(knownApi.named_endpoints['/infer'].parameters or {}) do
    if p.parameter_name=='lora_adapter' and p.type and p.type.enum then qwenLoras=p.type.enum end
  end
end
local function contains(list,value) for _,v in ipairs(list) do if v==value then return true end end return false end
local loraCachePath=app.fs.joinPath(root,'lora-options.local.json')
local loraCache=readJson(loraCachePath) or {}
local function sdxlOptions(list)
  local result={'None'}
  for _,name in ipairs(list or {}) do
    if type(name)=='string' and name~='' and not contains(result,name) then result[#result+1]=name end
  end
  return result
end
local sdxlLoras=loraCache['lienthealien/RuinedHugg']
if not sdxlLoras then
  local api=readJson(app.fs.joinPath(root,'jobs','verify-ruined','api-info.json'))
  local endpoint=api and api.named_endpoints and api.named_endpoints['/generate']
  for _,p in ipairs(endpoint and endpoint.parameters or {}) do
    if p.parameter_name=='param_20' and p.type then sdxlLoras=p.type.enum end
  end
end
sdxlLoras=sdxlOptions(sdxlLoras)
if not contains(sdxlLoras,defaults.sdxl_lora) then defaults.sdxl_lora='None' end
if not contains(qwenLoras,defaults.lora) then
  defaults.lora=contains(qwenLoras,'Pixel-Art-Refiner') and 'Pixel-Art-Refiner' or qwenLoras[1]
end
if not saved.backend and defaults.space=='lienthealien/RuinedHugg' then defaults.backend='RuinedHugg SDXL' end
local activeJob,timer
local function cancel()
  if activeJob then
    local f=io.open(app.fs.joinPath(activeJob.folder,'cancel.request'),'wb')
    if f then f:write('cancel');f:close() end
  end
end
local d=Dialog{title='Hugging Face — reference variations',onclose=function()
  cancel();if timer then timer:stop() end
end}
local controlsReady=false
local function backendVisibility()
  local sdxl=d.data.backend=='RuinedHugg SDXL'
  for _,id in ipairs({'lora','style'}) do d:modify{id=id,visible=not sdxl} end
  for _,id in ipairs({'model','strength','negative_prompt','sdxl_style','sdxl_lora'}) do d:modify{id=id,visible=sdxl} end
end
local function setBackend()
  if not controlsReady then return end
  local sdxl=d.data.backend=='RuinedHugg SDXL'
  d:modify{id='space',text=sdxl and 'lienthealien/RuinedHugg' or 'lienthealien/Qwen-Image-Edit-2511-LoRAs-Fast'}
  d:modify{id='endpoint',text=sdxl and '/generate' or '/infer'}
  d:modify{id='steps',text=sdxl and '25' or '4'}
  d:modify{id='guidance',text=sdxl and '7' or '1'}
  d:modify{id='lora_strength',text=sdxl and '0.5' or '1'}
  d:modify{id='prompt',text=sdxl and 'pixel art, one isolated rugged rock, angular chipped silhouette, cracks, muted stone colors, upper-left lighting, centered, fully visible, plain white background' or qwenPrompt}
  backendVisibility()
end
d:combobox{id='backend',label='Backend:',options={'Qwen image edit','RuinedHugg SDXL'},option=defaults.backend,onchange=setBackend}
d:entry{id='space',label='Space:',text=defaults.space}
d:entry{id='account',label='Account profile:',text=defaults.account}
d:entry{id='endpoint',label='API endpoint:',text=defaults.endpoint}
d:combobox{id='lora',label='LoRA:',options=qwenLoras,option=defaults.lora}
d:combobox{id='style',label='Style:',options={'(No style)','General Pixel Art','VGA Pixel Art','Digital Art','Fantasy Art','NES Pixel Art','Commodore 64','EGA/CGA Pixel Art','Top-Down Dungeon Pixel Art'},option=defaults.style}
d:entry{id='prompt',label='Variation prompt:',text=defaults.prompt}
d:entry{id='negative_prompt',label='Negative prompt:',text=defaults.negative_prompt}
d:entry{id='model',label='SDXL model:',text=defaults.model}
d:combobox{id='sdxl_style',label='SDXL style:',options={'(No style)','sai-pixel art','General PixelArt','CS VGA','CS 2D Side Scroller Pixel Art','CS EGA','CS NES','Top-Down Dungeon Pixel Art'},option=defaults.sdxl_style}
d:combobox{id='sdxl_lora',label='SDXL LoRA:',options=sdxlLoras,option=defaults.sdxl_lora}
d:number{id='strength',label='Denoising (0–1):',text=tostring(defaults.strength),decimals=2}
d:number{id='count',label='Variations (1–8):',text=tostring(defaults.count),decimals=0}
d:number{id='seed',label='Seed (-1=random):',text=tostring(defaults.seed),decimals=0}
d:number{id='steps',label='Steps:',text=tostring(defaults.steps),decimals=0}
d:number{id='guidance',label='Guidance:',text=tostring(defaults.guidance),decimals=1}
d:number{id='lora_strength',label='LoRA strength:',text=tostring(defaults.lora_strength),decimals=1}
d:entry{id='background',label='Upload background:',text=defaults.background}
d:entry{id='vision_space',label='Vision Space:',text=defaults.vision_space}
d:entry{id='vision_question',label='Description request:',text=defaults.vision_question}
d:number{id='vision_max_tokens',label='Description tokens:',text=tostring(defaults.vision_max_tokens),decimals=0}
d:check{id='selection',text='Use selection bounding box if selected',selected=defaults.selection}
d:check{id='upscale',text='Enlarge small reference with nearest-neighbor',selected=defaults.upscale}
d:check{id='resize',text='Resize results to reference size (nearest-neighbor)',selected=defaults.resize}
d:check{id='match_palette',text='Match results to the source palette',selected=defaults.match_palette}
d:separator()
d:label{id='status',text='Accounts → Inspect API → choose LoRA → Generate.'}
d:label{text='Generate uploads the visible current frame/selection to your Space.'}
local function showError(err) app.alert{title='HF Variations',text=tostring(err)} end
local function finish(status)
  timer:stop()
  local current=activeJob;activeJob=nil
  d:modify{id='generate',enabled=true};d:modify{id='inspect',enabled=true};d:modify{id='improve',enabled=true}
  d:modify{id='backend',enabled=true}
  d:modify{id='cancel',enabled=false}
  d:modify{id='status',text=(status.message or status.state):sub(1,90)}
  if current.operation=='inspect' and status.state=='complete' then
    d:modify{id='endpoint',text=status.endpoint or ''}
    if current.backend=='RuinedHugg SDXL' then
      local choices=sdxlOptions(status.loras)
      local selected=d.data.sdxl_lora
      if not contains(choices,selected) then selected='None' end
      d:modify{id='sdxl_lora',options=choices,option=selected}
      loraCache[current.space]=choices
      writeJson(loraCachePath,loraCache)
    elseif status.loras and #status.loras>0 then
      local selected=d.data.lora
      if not contains(status.loras,selected) then selected=contains(status.loras,'Pixel-Art-Refiner') and 'Pixel-Art-Refiner' or status.loras[1] end
      d:modify{id='lora',options=status.loras,option=selected}
    end
    d:modify{id='status',text='Connected. LoRA dropdown refreshed.'}
    local lines={'Connected. The LoRA dropdown has been refreshed.',
      'Choose a LoRA from the dropdown. For SDXL, None disables the LoRA.'}
    app.alert{title='Space API',text=lines}
  elseif current.operation=='improve_prompt' and status.state=='complete' then
    d:modify{id='prompt',text=status.improved_prompt or d.data.prompt}
    if current.backend=='Qwen image edit' then qwenPrompt=status.improved_prompt or qwenPrompt end
    app.alert{title='Mage-VL prompt proposal',text={'The proposed prompt is now in the prompt field.','Review or edit it before clicking Generate.','No generation was submitted.'}}
  elseif current.operation=='generate' then
    local ok,err=pcall(importResults,status.files,current.title)
    if not ok then showError(err) end
    if status.state~='complete' then showError((status.message or status.state)..'\nAny finished variations have been imported.\nJob folder: '..current.folder) end
  elseif status.state=='error' then showError(status.message or 'Bridge failed.') end
end
local function start(operation)
  assert(not activeJob,'A job is already active.')
  local cfg=d.data
  local sprite,frame=app.sprite,app.frame
  if operation=='generate' or operation=='improve_prompt' then
    assert(sprite and frame,'Open a sprite and select a frame first.')
    assert(cfg.prompt:match('%S'),'Enter a prompt.')
  end
  if operation=='generate' then
    assert(cfg.count>=1 and cfg.count<=8 and cfg.count==math.floor(cfg.count),'Choose 1–8 variations.')
    if cfg.match_palette then
      cfg.palette=paletteColors(sprite,frame)
      assert(#cfg.palette>0 and #cfg.palette<=256,'Palette matching supports 1–256 source colors.')
    end
  end
  -- Check installation before exporting anything.
  assert(app.fs.isFile(app.fs.joinPath(root,'.venv','Scripts','pythonw.exe')),'Run Setup.cmd in this script folder first.')
  local jobs=app.fs.joinPath(root,'jobs');app.fs.makeAllDirectories(jobs)
  local suffix=0;local folder
  repeat suffix=suffix+1;folder=app.fs.joinPath(jobs,tostring(os.time())..'-'..suffix)
  until not app.fs.isDirectory(folder)
  app.fs.makeDirectory(folder)
  local title=sprite and app.fs.fileTitle(sprite.filename) or 'reference'
  if operation=='generate' or operation=='improve_prompt' then exportReference(sprite,frame,app.fs.joinPath(folder,'input.png'),cfg.selection) end
  cfg.operation=operation
  local jobPath=app.fs.joinPath(folder,'job.json')
  writeJson(jobPath,cfg)
  local settings={};for k in pairs(defaults) do settings[k]=cfg[k] end
  writeJson(app.fs.joinPath(root,'settings.local.json'),settings)
  activeJob={folder=folder,title=title,operation=operation,backend=cfg.backend,space=cfg.space,started=os.time()}
  local ok,err=pcall(launch,jobPath,false)
  if not ok then activeJob=nil;error(err) end
  d:modify{id='generate',enabled=false};d:modify{id='inspect',enabled=false};d:modify{id='improve',enabled=false}
  d:modify{id='backend',enabled=false}
  d:modify{id='cancel',enabled=true};d:modify{id='status',text='Connecting…'}
  timer=Timer{interval=1,ontick=function()
    local ok,err=pcall(function()
      local status=readJson(app.fs.joinPath(activeJob.folder,'status.json'))
      if status then
        if status.state=='running' then d:modify{id='status',text=(status.message or 'Working…'):sub(1,90)}
        else finish(status) end
      elseif os.time()-activeJob.started>180 then
        cancel();finish{state='error',message='Bridge did not respond. Check Setup.cmd and the job folder.',files={}}
      elseif os.time()-activeJob.started>60 then
        d:modify{id='status',text='Bridge has not responded. Check Setup.cmd; Cancel to stop waiting.'}
      end
    end)
    if not ok then timer:stop();showError(err) end
  end}
  timer:start()
end
local function safely(fn) local ok,err=pcall(fn);if not ok then showError(err) end end
d:button{id='accounts',text='Accounts…',onclick=function() safely(function() launch(nil,true) end) end}
d:button{id='inspect',text='Inspect API',onclick=function() safely(function() start('inspect') end) end}
d:button{id='improve',text='Improve prompt with Mage-VL',onclick=function() safely(function() start('improve_prompt') end) end}
d:button{id='generate',text='Generate',onclick=function() safely(function() start('generate') end) end}
d:button{id='cancel',text='Cancel job',enabled=false,onclick=function()
  cancel();d:modify{id='status',text='Cancellation requested…'}
end}
d:button{text='Close',onclick=function() d:close() end}
controlsReady=true;backendVisibility()
d:show{wait=false}
