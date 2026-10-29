-- Packs the scripts in ../src into one drag-and-drop model file (HairPhysicsKit.rbxmx).
-- Run with Lune:  lune run tools/build_rbxmx.luau <path to HairPhysics folder>
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Instance = roblox.Instance

local base = process.args[1] or "."
local src = base .. "/src/"

local function script(class, name, file, parent)
	local s = Instance.new(class)
	s.Name = name
	s.Source = fs.readFile(src .. file)
	s.Parent = parent
	return s
end
local function folder(name, parent)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local kit = folder("HairPhysicsKit", nil)
local readme = script("Script", "README", "README.luau", kit)
readme.Disabled = true

local rs = folder("ReplicatedStorage", kit)
script("ModuleScript", "HairPhysics", "ReplicatedStorage/HairPhysics.luau", rs)
script("ModuleScript", "HairConfig", "ReplicatedStorage/HairConfig.luau", rs)

local sss = folder("ServerScriptService", kit)
script("Script", "HairApplier", "ServerScriptService/HairApplier.server.luau", sss)
script("Script", "NPCRoam", "ServerScriptService/NPCRoam.server.luau", sss)
script("Script", "ArenaSetup", "ServerScriptService/ArenaSetup.server.luau", sss)

local sps = folder("StarterPlayerScripts", kit)
script("LocalScript", "HairPhysicsClient", "StarterPlayerScripts/HairPhysicsClient.client.luau", sps)
script("LocalScript", "HairFitTool", "StarterPlayerScripts/HairFitTool.client.luau", sps)
script("LocalScript", "ArenaControls", "StarterPlayerScripts/ArenaControls.client.luau", sps)

local ss = folder("ServerStorage", kit)
folder("HairModels", ss)

local ws = folder("Workspace", kit)
require("./arena")().Parent = ws

local xml = roblox.serializeModel({ kit }, true)
-- Studio stores script code as ProtectedString; write it the same way Studio and Rojo do
local fixed, count = xml:gsub('<string name="Source">(<!%[CDATA%[.-%]%]>)</string>', '<ProtectedString name="Source">%1</ProtectedString>')
assert(count == 9, "expected 9 scripts, converted " .. count)
fs.writeFile(base .. "/HairPhysicsKit.rbxmx", fixed)
print("wrote " .. base .. "/HairPhysicsKit.rbxmx")
