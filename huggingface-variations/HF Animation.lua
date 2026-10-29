-- Windows Aseprite 1.3.x. Keep beside hf_bridge.py and launch.ps1.
local origin=debug.getinfo(1,'S').source
assert(origin:sub(1,1)=='@','Run this as a saved Lua script.')
local root=app.fs.filePath(origin:sub(2))

local function readJson(path)
  local f=io.open(path,'rb');if not f then return nil end
  local text=f:read('*a');f:close();text=text:gsub('^\239\187\191','')
  local ok,result=pcall(json.decode,text);return ok and result or nil
end
local function writeJson(path,data)
  local f=assert(io.open(path,'wb'));f:write(json.encode(data));f:close()
end
local function base64(s)
  local chars='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  local out={}
  for i=1,#s,3 do
    local a,b,c=s:byte(i,i+2);b=b or 0;c=c or 0;local n=(a<<16)|(b<<8)|c
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
    if n>65535 then n=n-65536;out[#out+1]=string.pack('<I2I2',55296+(n>>10),56320+(n&1023))
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
  local encoded=base64(utf16(command))
  local ok=os.execute('powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand '..encoded)
  assert(ok,'Could not launch the bridge. Check Setup.cmd and Windows script permissions.')
end

local function exportFrame(sprite,frameNumber,path,useSelection)
  local rendered=Image(sprite.width,sprite.height,ColorMode.RGB)
  rendered:drawSprite(sprite,frameNumber)
  local bounds=Rectangle(0,0,sprite.width,sprite.height)
  if useSelection and not sprite.selection.isEmpty then
    bounds=sprite.selection.bounds:intersect(bounds)
    assert(bounds.width>0 and bounds.height>0,'Selection is outside the canvas.')
    rendered=Image(rendered,bounds)
  end
  rendered:saveAs(path);return bounds
end

local function importFrames(files,title,duration)
  assert(files and #files>0,'The animation job returned no frames.')
  local images={}
  for _,entry in ipairs(files) do
    local image=Image{fromFile=entry.path}
    assert(image and image.colorMode==ColorMode.RGB,'Could not load a generated animation PNG.')
    images[#images+1]=image
  end
  local first=images[1]
  for _,image in ipairs(images) do
    assert(image.width==first.width and image.height==first.height,'Generated animation frame sizes differ.')
  end
  local result=Sprite(first.width,first.height,ColorMode.RGB)
  result.filename=title..'-animation.aseprite';result.layers[1].name='Generated animation'
  app.transaction('Import Hugging Face animation',function()
    result.cels[1].image=first
    for i=2,#images do result:newEmptyFrame();result:newCel(result.layers[1],i,images[i],Point(0,0)) end
    local frameDuration=math.max(0.01,(duration or 2)/#images)
    for _,frame in ipairs(result.frames) do frame.duration=frameDuration end
  end)
  app.sprite=result;app.frame=result.frames[1];app.refresh();return result
end

local function importSheet(entry,title)
  assert(entry and entry.path,'The animation job returned no sprite sheet.')
  local image=Image{fromFile=entry.path}
  assert(image and image.colorMode==ColorMode.RGB,'Could not load the generated sprite sheet PNG.')
  local result=Sprite(image.width,image.height,ColorMode.RGB)
  result.filename=title..'-sheet.aseprite';result.layers[1].name='Generated sprite sheet'
  app.transaction('Import Hugging Face sprite sheet',function() result.cels[1].image=image end)
  app.sprite=result;app.frame=result.frames[1];app.refresh();return result
end

if app.params.testload=='1' then
  return {exportFrame=exportFrame,importFrames=importFrames,importSheet=importSheet,
    base64=base64,utf16=utf16,psQuote=psQuote}
end
assert(app.isUIAvailable,'Run HF Animation from the Aseprite Scripts menu.')

local settingsPath=app.fs.joinPath(root,'animation-settings.local.json')
local defaults={
  space='lienthealien/MiniMax-H3-Turbo-Lora-UNCENSORED',account='default',endpoint='/generate_frames',
  generation_mode='Pixel art frames',mode='Start + end frame',
  prompt='Animate this pixel-art character between the supplied poses. Preserve the character design, proportions, palette, pixel size, lighting, and background.',
  action_prompt='Move naturally from the starting pose to the ending pose.',
  frame_count='7',frames_between='5',output_mode='Individual frames',seed=42,duration=2,steps=6,
  canvas='960x544 · 16:9 fast',animation_lora='larry',
  upsample=false,selection=true,background='#ffffff',
  vision_space='lienthealien/mage-vl-demo',vision_max_tokens=384,
  vision_question='Describe this image accurately for a downstream image or animation generation prompt. Focus on the subject, pose, visual details, composition, camera angle, pixel-art style, palette, lighting, and background. Do not invent motion or unseen details.'
}
local saved=readJson(settingsPath) or {}
for key in pairs(defaults) do if saved[key]~=nil then defaults[key]=saved[key] end end
defaults.frame_count=tostring(defaults.frame_count)
defaults.frames_between=tostring(defaults.frames_between)

local sprite=app.sprite
local currentFrame=app.frame and app.frame.frameNumber or 1
local lastFrame=sprite and #sprite.frames or currentFrame
local suggestedEnd=math.min(currentFrame+1,lastFrame)
local activeJob,timer
local function cancel()
  if activeJob then
    local f=io.open(app.fs.joinPath(activeJob.folder,'cancel.request'),'wb')
    if f then f:write('cancel');f:close() end
  end
end
local d=Dialog{title='Hugging Face — animation frames',onclose=function()
  cancel();if timer then timer:stop() end
end}
local controlsReady=false
local function modeVisibility()
  if not controlsReady then return end
  local timeline=d.data.generation_mode=='Pixel art timeline'
  d:modify{id='mode',visible=not timeline}
  d:modify{id='end_frame',visible=timeline or d.data.mode=='Start + end frame'}
  d:modify{id='action_prompt',visible=timeline}
  d:modify{id='frame_count',visible=not timeline}
  d:modify{id='frames_between',visible=timeline}
  d:modify{id='endpoint',text=timeline and '/generate_timeline' or '/generate_frames'}
end
d:entry{id='space',label='Space:',text=defaults.space}
d:entry{id='account',label='Account profile:',text=defaults.account}
d:entry{id='endpoint',label='API endpoint:',text=defaults.endpoint}
d:combobox{id='generation_mode',label='Mode:',options={'Pixel art frames','Pixel art timeline'},option=defaults.generation_mode,onchange=modeVisibility}
d:combobox{id='mode',label='Keyframes:',options={'Start frame only','Start + end frame'},option=defaults.mode,onchange=modeVisibility}
d:number{id='start_frame',label='Start frame:',text=tostring(currentFrame),decimals=0}
d:number{id='end_frame',label='End frame:',text=tostring(suggestedEnd),decimals=0}
d:entry{id='prompt',label='Animation prompt:',text=defaults.prompt}
d:entry{id='action_prompt',label='Timeline action:',text=defaults.action_prompt}
d:combobox{id='frame_count',label='Output frames:',options={'5','7'},option=defaults.frame_count}
d:combobox{id='frames_between',label='Frames between:',options={'4','5','7'},option=defaults.frames_between}
d:combobox{id='output_mode',label='Open result as:',options={'Individual frames','Sprite sheet','Both'},option=defaults.output_mode}
d:number{id='duration',label='Model duration (1–6s):',text=tostring(defaults.duration),decimals=1}
d:number{id='steps',label='Steps:',text=tostring(defaults.steps),decimals=0}
d:number{id='seed',label='Seed (-1=random):',text=tostring(defaults.seed),decimals=0}
d:combobox{id='animation_lora',label='Turbo LoRA:',options={'larry','lightx','off'},option=defaults.animation_lora}
d:entry{id='canvas',label='Model canvas:',text=defaults.canvas}
d:entry{id='background',label='Upload background:',text=defaults.background}
d:entry{id='vision_space',label='Vision Space:',text=defaults.vision_space}
d:entry{id='vision_question',label='Description request:',text=defaults.vision_question}
d:number{id='vision_max_tokens',label='Description tokens:',text=tostring(defaults.vision_max_tokens),decimals=0}
d:check{id='upsample',text='Let the Space refine/upsample the prompt',selected=defaults.upsample}
d:check{id='selection',text='Use the same selection bounds on both frames',selected=defaults.selection}
d:separator()
d:label{id='status',text='Choose source frame numbers, then Generate animation.'}
d:label{text='The original sprite is not modified. Results open in a new sprite.'}

local function showError(err) app.alert{title='HF Animation',text=tostring(err)} end
local function finish(status)
  timer:stop();local current=activeJob;activeJob=nil
  d:modify{id='generate',enabled=true};d:modify{id='inspect',enabled=true};d:modify{id='improve',enabled=true};d:modify{id='cancel',enabled=false}
  d:modify{id='status',text=(status.message or status.state):sub(1,90)}
  if current.operation=='inspect' and status.state=='complete' then
    d:modify{id='endpoint',text=status.endpoint or '/generate_frames'}
    app.alert{title='MiniMax Space API',text={'Connected to '..(status.endpoint or '/generate_frames')..'.','No GPU generation was submitted.'}}
  elseif current.operation=='improve_prompt' and status.state=='complete' then
    d:modify{id='prompt',text=status.improved_prompt or d.data.prompt}
    app.alert{title='Mage-VL prompt proposal',text={'The proposed prompt is now in the Animation prompt field.','Review or edit it before clicking Generate animation.','No animation generation was submitted.'}}
  elseif current.operation:match('^animate') then
    if status.files and #status.files>0 then
      local ok,err=pcall(importFrames,status.files,current.title,current.duration)
      if not ok then showError(err) end
    end
    if status.sheets and #status.sheets>0 then
      local ok,err=pcall(importSheet,status.sheets[1],current.title)
      if not ok then showError(err) end
    end
    if status.state~='complete' then showError((status.message or status.state)..'\nJob folder: '..current.folder) end
  elseif status.state=='error' then showError(status.message or 'Bridge failed.') end
end

local function start(operation)
  assert(not activeJob,'A job is already active.')
  local cfg=d.data;local source=app.sprite
  if operation=='improve_prompt' then
    assert(source,'Open a sprite first.')
    assert(cfg.start_frame>=1 and cfg.start_frame<=#source.frames and cfg.start_frame==math.floor(cfg.start_frame),'Start frame is outside this sprite.')
    assert(cfg.prompt:match('%S'),'Enter an animation prompt to improve.')
  end
  if operation=='animate' then
    local timeline=cfg.generation_mode=='Pixel art timeline'
    operation=timeline and 'animate_timeline' or 'animate_frames'
    assert(source,'Open a sprite first.')
    assert(cfg.start_frame>=1 and cfg.start_frame<=#source.frames and cfg.start_frame==math.floor(cfg.start_frame),'Start frame is outside this sprite.')
    local useEnd=timeline or cfg.mode=='Start + end frame'
    if useEnd then
      assert(cfg.end_frame>=1 and cfg.end_frame<=#source.frames and cfg.end_frame==math.floor(cfg.end_frame),'End frame is outside this sprite.')
      assert(cfg.end_frame~=cfg.start_frame,'Choose different start and end frames.')
    end
    assert(cfg.prompt:match('%S'),'Enter an animation prompt.')
    if timeline then
      assert(cfg.action_prompt:match('%S'),'Enter a timeline transition action.')
      cfg.frames_between=tonumber(cfg.frames_between)
      assert(cfg.frames_between==4 or cfg.frames_between==5 or cfg.frames_between==7,'Choose 4, 5, or 7 in-between frames.')
    else
      cfg.frame_count=tonumber(cfg.frame_count)
      assert(cfg.frame_count==5 or cfg.frame_count==7,'Choose 5 or 7 output frames.')
    end
  end
  assert(app.fs.isFile(app.fs.joinPath(root,'.venv','Scripts','pythonw.exe')),'Run Setup.cmd in this script folder first.')
  local jobs=app.fs.joinPath(root,'jobs');app.fs.makeAllDirectories(jobs)
  local suffix=0;local folder
  repeat suffix=suffix+1;folder=app.fs.joinPath(jobs,tostring(os.time())..'-animation-'..suffix)
  until not app.fs.isDirectory(folder)
  app.fs.makeDirectory(folder)
  local title=source and app.fs.fileTitle(source.filename) or 'animation'
  if not title or title=='' then title='animation' end
  if operation:match('^animate') or operation=='improve_prompt' then
    local firstBounds=exportFrame(source,cfg.start_frame,app.fs.joinPath(folder,'input.png'),cfg.selection)
    if operation:match('^animate') and (operation=='animate_timeline' or cfg.mode=='Start + end frame') then
      local lastBounds=exportFrame(source,cfg.end_frame,app.fs.joinPath(folder,'last-input.png'),cfg.selection)
      assert(firstBounds.width==lastBounds.width and firstBounds.height==lastBounds.height,'Start and end frame exports must have matching sizes.')
    end
  end
  cfg.operation=operation
  local jobPath=app.fs.joinPath(folder,'job.json');writeJson(jobPath,cfg)
  local settings={};for key in pairs(defaults) do settings[key]=cfg[key] end
  settings.frame_count=tostring(settings.frame_count);settings.frames_between=tostring(settings.frames_between)
  writeJson(settingsPath,settings)
  activeJob={folder=folder,title=title,operation=operation,duration=tonumber(cfg.duration) or 2,started=os.time()}
  local ok,err=pcall(launch,jobPath,false);if not ok then activeJob=nil;error(err) end
  d:modify{id='generate',enabled=false};d:modify{id='inspect',enabled=false};d:modify{id='improve',enabled=false};d:modify{id='cancel',enabled=true}
  d:modify{id='status',text='Connecting…'}
  timer=Timer{interval=1,ontick=function()
    local ok,err=pcall(function()
      local status=readJson(app.fs.joinPath(activeJob.folder,'status.json'))
      if status then
        if status.state=='running' then d:modify{id='status',text=(status.message or 'Working…'):sub(1,90)}
        else finish(status) end
      elseif os.time()-activeJob.started>180 then
        cancel();finish{state='error',message='Bridge did not respond. Check Setup.cmd and the job folder.',files={}}
      elseif os.time()-activeJob.started>60 then d:modify{id='status',text='Bridge has not responded. Cancel to stop waiting.'} end
    end)
    if not ok then timer:stop();showError(err) end
  end};timer:start()
end
local function safely(fn) local ok,err=pcall(fn);if not ok then showError(err) end end
d:button{id='accounts',text='Accounts…',onclick=function() safely(function() launch(nil,true) end) end}
d:button{id='inspect',text='Inspect API',onclick=function() safely(function() start('inspect') end) end}
d:button{id='improve',text='Improve prompt with Mage-VL',onclick=function() safely(function() start('improve_prompt') end) end}
d:button{id='generate',text='Generate animation',onclick=function() safely(function() start('animate') end) end}
d:button{id='cancel',text='Cancel job',enabled=false,onclick=function() cancel();d:modify{id='status',text='Cancellation requested…'} end}
d:button{text='Close',onclick=function() d:close() end}
controlsReady=true;modeVisibility();d:show{wait=false}
