-- runs applytest's world, then drives HairPhysics.StartClient with stub services
local luau = require("@lune/luau"); local fs = require("@lune/fs")
local src = fs.readFile("tools/test/applytest.luau")
src = src .. [[

-- ===== client runner test =====
local function signal()
	local s = { fns = {} }
	function s:Connect(fn) table.insert(self.fns, fn); return { Disconnect = function() end } end
	function s:Fire(...) for _, f in self.fns do f(...) end end
	return s
end
local preRender = signal()
local tagged = {}
for _, d in Workspace:GetDescendants() do if d:HasTag("HairPhysics") then table.insert(tagged, d) end end
local stubCS = {
	GetTagged = function() return tagged end,
	GetInstanceAddedSignal = function() return signal() end,
	GetInstanceRemovedSignal = function() return signal() end,
}
local stubRS = { PreRender = preRender }
local clientEnv = {}
for k, v in env do clientEnv[k] = v end
clientEnv.game = { GetService = function(_, n)
	if n == "RunService" then return stubRS elseif n == "CollectionService" then return stubCS end
	return game:GetService(n)
end }
clientEnv.script = { Parent = { WaitForChild = function(_, n) return { Name = n } end } }
clientEnv.os = os
local HPc = luau.load(fs.readFile(SRC .. "ReplicatedStorage/HairPhysics.luau"), { environment = clientEnv })()
HPc.StartClient()
local heads = { headP, headL }
local t = 0
for frame = 1, 240 do
	t += 1/60
	for _, h in heads do
		h.CFrame = h.CFrame * CF.new(0, 0, -16/60) -- walk forward
		local handle = h.Parent:FindFirstChildWhichIsA("Accessory"):FindFirstChild("Handle")
		local weld = handle:FindFirstChild("AccessoryWeld")
		handle.CFrame = h.CFrame * weld.C0
	end
	preRender:Fire(1/60)
end
for _, h in heads do
	local handle = h.Parent:FindFirstChildWhichIsA("Accessory"):FindFirstChild("Handle")
	local moved, total = 0, 0
	for _, b in handle:GetDescendants() do
		if b:IsA("Bone") then
			total += 1
			local okT, tr = pcall(function() return b.Transform end)
			local rx, ry, rz = 0, 0, 0
			if okT then rx, ry, rz = tr:ToEulerAnglesXYZ() end
			if math.abs(rx) + math.abs(ry) + math.abs(rz) > 1e-3 then moved += 1 end
		end
	end
	print(h.Parent.Name, "bones with physics rotation:", moved, "/", total)
end
print("warnings after client run:", #warnings)
]]
luau.load(src, { injectGlobals = true })()
