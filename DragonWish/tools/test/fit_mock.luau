-- Runs the real HairFitTool against a fake character wearing the base hair, the belt and the
-- (hidden) SSJ, SSJ2 and SSJ3 hairs: opening the panel, stepping through the pieces with Next,
-- and closing it. A hidden hair must show while it's picked (in place of the hair on the head,
-- never touching the belt), and closing must put back what the current form shows.
-- usage (from the DragonWish folder): lune run tools/test/fit_mock.luau
local luau = require("@lune/luau")
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local V3, CF, I = roblox.Vector3, roblox.CFrame, roblox.Instance

local function signal()
	local s = { fns = {} }
	function s:Connect(fn) table.insert(self.fns, fn); return { Disconnect = function() end } end
	function s:Fire(...) for _, f in self.fns do f(...) end end
	return s
end

-- the character: a head and a waist, five pieces welded on
local char = I.new("Model"); char.Name = "Player1"
char:SetAttribute("Form", "Base")
local function part(name, cls, parent)
	local p = I.new(cls or "Part"); p.Name = name; p.Size = V3.new(1, 1, 1); p.CFrame = CF.new(0, 4.5, 0); p.Parent = parent or char
	return p
end
local head = part("Head")
local waist = part("LowerTorso")
local tagged = {}
local pieces = {}
for _, spec in { { "BaseHair", "Base", head }, { "SSJHair", "SSJ", head }, { "SSJ2Hair", "SSJ2", head }, { "SSJ3Hair", "SSJ3", head }, { "Belt", "Both", waist } } do
	local holder = I.new("Model"); holder.Name = "DW_" .. spec[1]; holder.Parent = char
	local mesh = part(spec[1], "MeshPart", holder)
	mesh:SetAttribute("HairPreset", spec[1])
	mesh:SetAttribute("VisibleIn", spec[2])
	mesh.Transparency = (spec[2] == "Base" or spec[2] == "Both") and 0 or 1
	local weld = I.new("Weld"); weld.Name = "DWWeld"; weld.Part0 = spec[3]; weld.Part1 = mesh; weld.Parent = mesh
	table.insert(tagged, mesh)
	pieces[spec[1]] = mesh
end

-- just enough UI for the panel: plain tables, buttons can be pressed
local buttons = {}
local function uiObject(cls)
	local o = { ClassName = cls, Activated = signal() }
	setmetatable(o, { __index = function() return nil end })
	if cls == "TextButton" then table.insert(buttons, o) end
	return o
end
local uiClasses = { ScreenGui = true, Frame = true, TextLabel = true, TextButton = true, TextBox = true, UICorner = true, UIPadding = true, Highlight = true }
local instanceStub = { new = function(cls) if uiClasses[cls] then return uiObject(cls) end return I.new(cls) end }

local action
local player = { Character = char, WaitForChild = function() return {} end }
local services = {
	CollectionService = { GetTagged = function() return tagged end },
	ContextActionService = {
		BindAction = function(_, _, fn) action = fn end,
		SetTitle = function() end,
		SetPosition = function() end,
	},
	Players = { LocalPlayer = player },
	ReplicatedStorage = { WaitForChild = function(_, name) return { Name = name } end },
	UserInputService = { IsKeyDown = function() return false end },
}
local mods = { Vector3 = V3, CFrame = CF, Color3 = roblox.Color3, Enum = roblox.Enum }
local modules = {
	HairConfig = luau.load(fs.readFile("src/ReplicatedStorage/HairConfig.luau"), { environment = mods })(),
	HairPhysics = { TAG = "HairPhysics" },
}
local env = {
	game = { GetService = function(_, n) return services[n] end },
	require = function(m) return modules[m.Name] end,
	Instance = instanceStub, Vector3 = V3, CFrame = CF, Color3 = roblox.Color3, Enum = roblox.Enum,
	UDim = roblox.UDim, UDim2 = roblox.UDim2, Vector2 = roblox.Vector2,
	print = function() end, warn = print, typeof = typeof, string = string, table = table, math = math,
}
luau.load(fs.readFile("src/StarterPlayerScripts/HairFitTool.client.luau"), { environment = env })()
assert(action, "the fit tool didn't bind its key")

local function press(label)
	for _, b in buttons do
		if b.Text == label then b.Activated:Fire(); return end
	end
	error("no button " .. label)
end
local function shown()
	local t = {}
	for _, name in { "BaseHair", "SSJHair", "SSJ2Hair", "SSJ3Hair", "Belt" } do
		if pieces[name].Transparency < 0.99 then table.insert(t, name) end
	end
	return table.concat(t, " ")
end
local failures = 0
local function check(what, ok)
	print((ok and "PASS  " or "FAIL  ") .. what)
	if not ok then failures += 1 end
end

action("HairFitTool", roblox.Enum.UserInputState.Begin)
check("open: the base hair is picked, nothing else changes (" .. shown() .. ")", shown() == "BaseHair Belt")
press("Next")
check("Next: the belt; still nothing changes (" .. shown() .. ")", shown() == "BaseHair Belt")
press("Next")
check("Next: the SSJ2 hair shows in place of the base hair, the belt stays (" .. shown() .. ")", shown() == "SSJ2Hair Belt")
press("Next")
check("Next: the SSJ3 hair; the SSJ2 hair goes back to hidden (" .. shown() .. ")", shown() == "SSJ3Hair Belt")
press("Next")
check("Next: the SSJ hair (hidden in base form) shows too (" .. shown() .. ")", shown() == "SSJHair Belt")
press("Next")
check("Next wraps round to the base hair: back to normal (" .. shown() .. ")", shown() == "BaseHair Belt")
press("Prev")
check("Prev: the SSJ hair again (" .. shown() .. ")", shown() == "SSJHair Belt")
action("HairFitTool", roblox.Enum.UserInputState.Begin)
check("closing the panel puts back what base form shows (" .. shown() .. ")", shown() == "BaseHair Belt")
char:SetAttribute("Form", "SSJ")
pieces.BaseHair.Transparency = 1; pieces.SSJHair.Transparency = 0 -- (the server swapping the hair)
action("HairFitTool", roblox.Enum.UserInputState.Begin)
check("reopened on the SSJ hair, which shows anyway: nothing changes (" .. shown() .. ")", shown() == "SSJHair Belt")
press("Next")
check("as a Super Saiyan, the (hidden) base hair shows in place of the SSJ hair (" .. shown() .. ")", shown() == "BaseHair Belt")
press("Next"); press("Next")
check("then the SSJ2 hair in place of the SSJ hair (" .. shown() .. ")", shown() == "SSJ2Hair Belt")
action("HairFitTool", roblox.Enum.UserInputState.Begin)
check("closing puts the SSJ hair back (" .. shown() .. ")", shown() == "SSJHair Belt")
print(failures == 0 and "all fit-tool checks passed" or (failures .. " fit-tool check(s) failed"))
