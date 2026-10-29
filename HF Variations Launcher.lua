-- Keep the huggingface-variations folder beside this launcher.
local source = debug.getinfo(1, 'S').source
assert(source:sub(1, 1) == '@', 'Run this as a saved Lua script.')
local root = app.fs.filePath(source:sub(2))
dofile(app.fs.joinPath(root, 'huggingface-variations', 'HF Variations.lua'))
