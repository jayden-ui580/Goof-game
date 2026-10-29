--[[
	HairPhysicsClient  (LocalScript — lives in StarterPlayer > StarterPlayerScripts)

	Starts the hair simulation on this player's screen. Every hair the server tagged
	"HairPhysics" gets simulated here. Nothing to change in this script — the settings
	are in ReplicatedStorage > HairConfig.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local HairPhysics = require(ReplicatedStorage:WaitForChild("HairPhysics"))
HairPhysics.StartClient()
