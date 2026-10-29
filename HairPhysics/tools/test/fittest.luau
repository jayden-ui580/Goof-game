-- Tests FitRig/HeadToPart: imported bones may be shifted, turned 90 degrees and scaled
local luau = require("@lune/luau"); local roblox = require("@lune/roblox"); local fs = require("@lune/fs"); local process = require("@lune/process")
local V3, CF = roblox.Vector3, roblox.CFrame
local HP = luau.load(fs.readFile(process.args[1]), { environment = { Vector3 = V3, CFrame = CF } })()
local design = { V3.new(0,0,0), V3.new(-0.56,0.44,0.12), V3.new(-1.0,-0.8,0.3), V3.new(0.56,0.44,0.12), V3.new(1.2,-0.34,0.2) }
local worst = 0
for _, case in { {CF.new(), 1}, {CF.new(0.3,-1.2,0.5), 1}, {CF.new(1,2,3) * CF.Angles(-math.pi/2,0,0), 1}, {CF.new(-2,0,1) * CF.Angles(0,math.pi,0), 0.01}, {CF.Angles(0,math.pi/2,math.pi/2), 3.57} } do
	local importCF, s = case[1], case[2]
	local actual = {}
	for i, d in design do actual[i] = importCF * (d * s) end
	local fit = HP.FitRig(design, actual)
	-- the head-space position the attach transform gives each bone should be s * design
	local M = HP.HeadToPart(fit)
	for i, a in actual do
		local back = M * a
		worst = math.max(worst, (back - design[i] * fit.Scale).Magnitude)
	end
	print(("scale in %.3f -> fit %.3f, error %.5f"):format(s, fit.Scale, fit.Error))
end
print("max head-space mismatch", worst)
