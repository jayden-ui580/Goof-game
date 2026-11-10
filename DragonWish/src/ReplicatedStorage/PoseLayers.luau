--[[
	PoseLayers  (ModuleScript — lives in ReplicatedStorage)

	More than one script poses the same character's joints after Roblox has played its
	animations for the frame: Locomotion lays down the walk / idle, then PowerFX puts the
	power-up poses on top of it. Roblox doesn't promise which script's handler runs first, so
	they all run from here, every frame, in a fixed order (lowest Order first):
	    10  Locomotion   the idle, walk and run
	    20  PowerFX      powering up, the "YOU'RE FINISHED!" point, Kaioken, exhausted
	They run in PreSimulation (or Stepped on older Roblox versions), where Roblox says joint
	Transforms should be changed.
]]

local RunService = game:GetService("RunService")

local PoseLayers = {}

local layers = {}
local started = false

local function runAll(dt: number)
	for _, layer in layers do
		local ok, err = pcall(layer.Fn, dt)
		if not ok and not layer.Warned then
			layer.Warned = true -- (once, not every frame)
			warn(("[PoseLayers] %s failed: %s"):format(layer.Name, tostring(err)))
		end
	end
end

-- fn(dt) runs every frame, after every layer with a lower order
function PoseLayers.Add(order: number, name: string, fn: (number) -> ())
	table.insert(layers, { Order = order, Name = name, Fn = fn })
	table.sort(layers, function(a, b)
		return a.Order < b.Order
	end)
	if not started then
		started = true
		local ok, preSimulation = pcall(function()
			return RunService.PreSimulation
		end)
		if ok and preSimulation then
			preSimulation:Connect(runAll)
		else
			RunService.Stepped:Connect(function(_, dt)
				runAll(dt)
			end)
		end
	end
end

return PoseLayers
