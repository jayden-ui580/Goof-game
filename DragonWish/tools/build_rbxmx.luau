-- Packs the scripts in ../src into one drag-and-drop model file (DragonWishKit.rbxmx).
-- Run with Lune from the DragonWish folder:  lune run tools/build_rbxmx.luau .
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Instance = roblox.Instance

local base = process.args[1] or "."
local src = base .. "/src/"
local count = 0
local function script(class, name, file, parent)
	local s = Instance.new(class)
	s.Name = name
	s.Source = fs.readFile(src .. file)
	s.Parent = parent
	count += 1
	return s
end
local function folder(name, parent)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local kit = folder("DragonWishKit", nil)
script("Script", "README", "README.luau", kit).Disabled = true
local rs = folder("ReplicatedStorage", kit)
script("ModuleScript", "HairPhysics", "ReplicatedStorage/HairPhysics.luau", rs)
script("ModuleScript", "HairConfig", "ReplicatedStorage/HairConfig.luau", rs)
script("ModuleScript", "PowerConfig", "ReplicatedStorage/PowerConfig.luau", rs)
script("ModuleScript", "DragonUI", "ReplicatedStorage/DragonUI.luau", rs)
local sss = folder("ServerScriptService", kit)
script("Script", "CharacterSetup", "ServerScriptService/CharacterSetup.server.luau", sss)
script("Script", "PowerUpServer", "ServerScriptService/PowerUpServer.server.luau", sss)
local sps = folder("StarterPlayerScripts", kit)
script("LocalScript", "HairPhysicsClient", "StarterPlayerScripts/HairPhysicsClient.client.luau", sps)
script("LocalScript", "PowerUpClient", "StarterPlayerScripts/PowerUpClient.client.luau", sps)
script("LocalScript", "PowerFX", "StarterPlayerScripts/PowerFX.client.luau", sps)
script("ModuleScript", "SSJCutscene", "StarterPlayerScripts/SSJCutscene.luau", sps)
script("LocalScript", "HUD", "StarterPlayerScripts/HUD.client.luau", sps)
script("LocalScript", "HandFX", "StarterPlayerScripts/HandFX.client.luau", sps)
script("LocalScript", "HairFitTool", "StarterPlayerScripts/HairFitTool.client.luau", sps)
local ss = folder("ServerStorage", kit)
folder("CharacterParts", ss)

local xml = roblox.serializeModel({ kit }, true)
-- Studio stores script code as ProtectedString; write it the same way Studio and Rojo do
local fixed, converted = xml:gsub('<string name="Source">(<!%[CDATA%[.-%]%]>)</string>', '<ProtectedString name="Source">%1</ProtectedString>')
assert(converted == count, ("expected %d scripts, converted %d"):format(count, converted))
fs.writeFile(base .. "/DragonWishKit.rbxmx", fixed)
print("wrote " .. base .. "/DragonWishKit.rbxmx (" .. count .. " scripts)")
