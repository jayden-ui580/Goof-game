--[[
	DragonUI  (ModuleScript — lives in ReplicatedStorage)

	The look of Dragon Wish's screens, shared by the HUD and the power-up controls. It borrows from
	how the Dragon Ball fighting games dress their screens (FighterZ, Sparking! ZERO) and from
	Persona 5's rules for stylish menus:
	  * no rounded boxes: everything is a SLAB, a slanted parallelogram ("/" at both ends), and
	    every slab leans the same way
	  * a tight palette: ink black, warm paper and Saiyan-gi orange, with colour only where it
	    means something (yellow health, red damage, blue ki that turns gold as a Super Saiyan)
	  * comic lettering: Bangers with an ink outline, printed twice, slightly offset
	  * Dragon Balls, halftone dots and hard shadows (solid, not blurred)
	Everything here is plain Frames and TextLabels: no uploaded images.

	One rule: never put a slab inside a ROTATED frame. A slab cuts its slanted ends out with
	ClipsDescendants, and Roblox stops clipping inside anything that is rotated.
]]

local DragonUI = {}

DragonUI.INK = Color3.fromRGB(16, 14, 20)
DragonUI.INK_SOFT = Color3.fromRGB(46, 42, 58) -- empty gauges on an ink panel
DragonUI.PAPER = Color3.fromRGB(250, 244, 228)
DragonUI.GI = Color3.fromRGB(255, 122, 24) -- Goku's gi orange
DragonUI.GI_DARK = Color3.fromRGB(176, 66, 10)
DragonUI.GOLD = Color3.fromRGB(255, 200, 44) -- Super Saiyan
DragonUI.HP = Color3.fromRGB(255, 216, 40)
DragonUI.HP_LOW = Color3.fromRGB(255, 92, 40)
DragonUI.DAMAGE = Color3.fromRGB(230, 30, 42)
DragonUI.KI = Color3.fromRGB(80, 214, 255)
DragonUI.KI_SSJ = Color3.fromRGB(255, 214, 60)
DragonUI.SCOUTER = Color3.fromRGB(40, 255, 120)
DragonUI.SLANT = math.tan(math.rad(24)) -- how far the ends lean: 24 degrees off vertical

local function new(className: string, props, parent: Instance?)
	local inst = Instance.new(className)
	for k, v in props do
		inst[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end
DragonUI.new = new

----------------------------------------------------------------------------------------
-- Slab: a slanted parallelogram. Each slanted end is a big square turned to the slant
-- angle inside a box that clips it, so only a triangle of it shows; a plain body fills the
-- middle. (Roblox only stops clipping when the clipping box itself, or something it sits in,
-- is rotated: the turned squares inside are clipped fine.)
----------------------------------------------------------------------------------------
local Slab = {}
Slab.__index = Slab
DragonUI.Slab = Slab

-- x, y, w, h in pixels inside parent. props (all optional): Slant (pixels the top edge is
-- shifted right; default h * SLANT), ZIndex, Transparency
function Slab.new(parent: Instance, name: string, x: number, y: number, w: number, h: number, color: Color3, props)
	props = props or {}
	local self = setmetatable({}, Slab)
	local s = props.Slant or h * DragonUI.SLANT
	local z = props.ZIndex or 1
	local transparency = props.Transparency or 0
	self.S, self.H, self.W, self.Z = s, h, w, z
	self.Pieces, self.Bands = {}, {}
	-- an opaque slab's body runs a pixel into each end so no seam can show where they meet; a
	-- see-through one's can't (the overlap would show as a darker line), so it meets them exactly
	self.Overlap = transparency > 0 and 0 or 1
	self.Holder = new("Frame", {
		Name = name,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(w, h),
		BackgroundTransparency = 1,
		ZIndex = z,
	}, parent)
	local function piece(p: Instance)
		local f = new("Frame", {
			BackgroundColor3 = color,
			BackgroundTransparency = transparency,
			BorderSizePixel = 0,
			ZIndex = z,
		}, p)
		table.insert(self.Pieces, f)
		return f
	end
	self.Body = piece(self.Holder)
	self.Body.Name = "Body"
	self.LBox = new("Frame", { Name = "LeftEnd", Size = UDim2.fromOffset(s, h), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = z }, self.Holder)
	self.RBox = new("Frame", { Name = "RightEnd", Size = UDim2.fromOffset(s, h), BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = z }, self.Holder)
	local lt, rt = piece(self.LBox), piece(self.RBox)
	-- the slanted edge runs from (0, h) to (s, 0) inside each end box
	local theta = math.atan2(-h, s)
	local big = 2 * (h + s)
	local normal = Vector2.new(-math.sin(theta), math.cos(theta)) -- points down-right, off the edge
	local mid = Vector2.new(s / 2, h / 2)
	local cl, cr = mid + normal * (big / 2), mid - normal * (big / 2)
	for _, t in { lt, rt } do
		t.AnchorPoint = Vector2.new(0.5, 0.5)
		t.Size = UDim2.fromOffset(big, big)
		t.Rotation = math.deg(theta)
	end
	lt.Position = UDim2.fromOffset(cl.X, cl.Y) -- shows below-right of the edge: the left end
	rt.Position = UDim2.fromOffset(cr.X, cr.Y) -- shows above-left of the edge: the right end
	self:SetWidth(w)
	return self
end

-- a slab drawn t pixels bigger all round the slab (x, y, w, h): put it behind that one for an
-- outline of even thickness, slanted ends included
function Slab.around(parent: Instance, name: string, x: number, y: number, w: number, h: number, t: number, color: Color3, props)
	local k = DragonUI.SLANT
	local grow = t * (k + math.sqrt(1 + k * k)) -- sideways growth that keeps the slanted sides t thick
	local p = table.clone(props or {})
	p.Slant = (h + 2 * t) * k
	return Slab.new(parent, name, x - grow, y - t, w + 2 * grow, h + 2 * t, color, p)
end

-- the slab's length (its left end stays put); 0 hides it
function Slab:SetWidth(width: number)
	local s = self.S
	self.Width = width
	self.Holder.Visible = width > 0.5
	self.Holder.Size = UDim2.fromOffset(math.max(width, 0), self.H)
	local o = self.Overlap
	self.Body.Position = UDim2.fromOffset(s - o, 0)
	self.Body.Size = UDim2.fromOffset(math.max(width - 2 * s + 2 * o, 0), self.H)
	self.RBox.Position = UDim2.fromOffset(math.max(width - s, 0), 0)
	for _, band in self.Bands do
		band.Slab:SetWidth(math.max(width - band.Trim, 0))
	end
end

-- fills a share (0..1) of the full slab, like a bar
function Slab:SetFill(share: number)
	share = math.clamp(share, 0, 1)
	self:SetWidth(share <= 0.001 and 0 or self.S + share * (self.W - self.S))
end

function Slab:SetColor(color: Color3)
	for _, p in self.Pieces do
		p.BackgroundColor3 = color
	end
end

function Slab:SetTransparency(t: number)
	for _, p in self.Pieces do
		p.BackgroundTransparency = t
	end
	if (t > 0 and 0 or 1) ~= self.Overlap then
		self.Overlap = t > 0 and 0 or 1
		self:SetWidth(self.Width)
	end
end

-- a strip of this slab from a to b pixels below its top (a shine, a shade, a scan line). It has
-- the same slanted ends, so it always fits exactly inside, and it follows SetWidth.
function Slab:Band(name: string, a: number, b: number, color: Color3, props)
	props = props or {}
	local k = self.S / self.H
	local trim = (self.H - b + a) * k
	local band = Slab.new(self.Holder, name, (self.H - b) * k, a, math.max(self.W - trim, 0), b - a, color, {
		Slant = (b - a) * k,
		ZIndex = props.ZIndex or (self.Z + 1),
		Transparency = props.Transparency,
	})
	table.insert(self.Bands, { Slab = band, Trim = trim })
	band:SetWidth(math.max(self.Width - trim, 0))
	return band
end

----------------------------------------------------------------------------------------
-- comic lettering: an ink-outlined label with a second print offset behind it
-- props: Position, Size, AnchorPoint, Rotation, ZIndex, Text, Font, TextXAlignment,
--        Color (front), BackColor (the offset print), Offset (pixels), Stroke (outline width)
----------------------------------------------------------------------------------------
function DragonUI.Lettering(parent: Instance, name: string, props)
	local holder = new("Frame", {
		Name = name,
		Position = props.Position,
		Size = props.Size,
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Rotation = props.Rotation or 0,
		BackgroundTransparency = 1,
		ZIndex = props.ZIndex or 1,
	}, parent)
	local function label(nm: string, offset: number, color: Color3, z: number)
		local l = new("TextLabel", {
			Name = nm,
			Position = UDim2.fromOffset(offset, offset),
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Font = props.Font or Enum.Font.Bangers,
			Text = props.Text or "",
			TextColor3 = color,
			TextScaled = true,
			TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left,
			ZIndex = z,
		}, holder)
		local stroke = new("UIStroke", { Color = DragonUI.INK, Thickness = props.Stroke or 2 }, l)
		return l, stroke
	end
	local back, backStroke = label("Print", props.Offset or 3, props.BackColor or DragonUI.GI, props.ZIndex or 1)
	local front, frontStroke = label("Text", 0, props.Color or DragonUI.PAPER, (props.ZIndex or 1) + 1)
	local lettering = { Holder = holder, Front = front, Back = back }
	function lettering:SetText(text: string)
		front.Text = text
		back.Text = text
	end
	function lettering:SetColors(color: Color3?, backColor: Color3?)
		if color then
			front.TextColor3 = color
		end
		if backColor then
			back.TextColor3 = backColor
		end
	end
	function lettering:SetTransparency(t: number)
		front.TextTransparency, back.TextTransparency = t, t
		frontStroke.Transparency, backStroke.Transparency = t, t
	end
	return lettering
end

----------------------------------------------------------------------------------------
-- a Dragon Ball: a glossy orange orb with up to 5 red stars, an ink outline and a hard shadow
----------------------------------------------------------------------------------------
local STAR_SPOTS = { -- where the stars sit for each count (share of the ball)
	[1] = { { 0.5, 0.52 } },
	[2] = { { 0.38, 0.42 }, { 0.62, 0.62 } },
	[3] = { { 0.5, 0.36 }, { 0.36, 0.62 }, { 0.64, 0.62 } },
	[4] = { { 0.38, 0.38 }, { 0.62, 0.38 }, { 0.38, 0.64 }, { 0.62, 0.64 } },
	[5] = { { 0.5, 0.3 }, { 0.3, 0.47 }, { 0.7, 0.47 }, { 0.39, 0.71 }, { 0.61, 0.71 } },
}
DragonUI.STAR_SPOTS = STAR_SPOTS

function DragonUI.Orb(parent: Instance, name: string, x: number, y: number, size: number, z: number?)
	z = z or 1
	local holder = new("Frame", {
		Name = name,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(size, size),
		BackgroundTransparency = 1,
		ZIndex = z,
	}, parent)
	local scale = new("UIScale", {}, holder)
	local shadow = new("Frame", {
		Name = "Shadow",
		Position = UDim2.fromOffset(math.max(2, size * 0.07), math.max(3, size * 0.09)),
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = DragonUI.INK,
		ZIndex = z,
	}, holder)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, shadow)
	local ball = new("Frame", {
		Name = "Ball",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = z + 1,
	}, holder)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, ball)
	new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(255, 214, 110), Color3.fromRGB(232, 100, 18)),
		Rotation = 45,
	}, ball)
	new("UIStroke", { Color = DragonUI.INK, Thickness = math.max(2, size * 0.065), ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, ball)
	local gloss = new("Frame", {
		Name = "Gloss",
		Position = UDim2.fromScale(0.16, 0.1),
		Size = UDim2.fromScale(0.32, 0.18),
		Rotation = -28,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.35,
		ZIndex = z + 3,
	}, ball)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, gloss)
	local stars = {}
	for k = 1, 5 do
		local star = new("TextLabel", {
			Name = "Star" .. k,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromScale(0.3, 0.3),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBlack,
			Text = "★",
			TextScaled = true,
			TextColor3 = Color3.fromRGB(225, 26, 26),
			Visible = false,
			ZIndex = z + 2,
		}, ball)
		stars[k] = star
	end
	local orb = { Holder = holder, Ball = ball, Stars = stars, Scale = scale, Count = -1 }
	function orb:SetStars(n: number)
		n = math.clamp(math.floor(n), 0, 5)
		if n == self.Count then
			return
		end
		self.Count = n
		local spots = STAR_SPOTS[n] or {}
		for k, star in self.Stars do
			local spot = spots[k]
			star.Visible = spot ~= nil
			if spot then
				star.Position = UDim2.fromScale(spot[1], spot[2])
				local size = n == 1 and 0.46 or (n <= 3 and 0.36 or 0.3)
				star.Size = UDim2.fromScale(size, size)
			end
		end
	end
	orb:SetStars(0)
	return orb
end

----------------------------------------------------------------------------------------
-- halftone: a patch of dots shrinking toward the right, like a screentone fading out
-- props (all optional): ZIndex, Transparency, Lean (shift each row right by this much per pixel
-- it sits higher, so the patch leans like a slab: use DragonUI.SLANT)
----------------------------------------------------------------------------------------
function DragonUI.Halftone(parent: Instance, name: string, x: number, y: number, cols: number, rows: number, step: number, biggest: number, color: Color3, props)
	props = props or {}
	local z = props.ZIndex or 1
	local lean = props.Lean or 0
	local holder = new("Frame", {
		Name = name,
		Position = UDim2.fromOffset(x, y),
		Size = UDim2.fromOffset(cols * step + rows * step * lean, rows * step),
		BackgroundTransparency = 1,
		ZIndex = z,
	}, parent)
	for row = 0, rows - 1 do
		local shift = (rows - 1 - row) * step * lean + (row % 2) * 0.5 * step
		for col = 0, cols - 1 do
			local d = biggest * (1 - col / cols)
			if d >= 1.5 then
				local dot = new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset((col + 0.5) * step + shift, (row + 0.5) * step),
					Size = UDim2.fromOffset(d, d),
					BackgroundColor3 = color,
					BackgroundTransparency = props.Transparency or 0,
					BorderSizePixel = 0,
					ZIndex = z,
				}, holder)
				new("UICorner", { CornerRadius = UDim.new(1, 0) }, dot)
			end
		end
	end
	return holder
end

----------------------------------------------------------------------------------------
-- small helpers for hand-made motion
----------------------------------------------------------------------------------------
-- 0..1 -> 0..1, overshooting a little before settling (like Enum.EasingStyle.Back, Out)
function DragonUI.BackOut(t: number): number
	t = math.clamp(t, 0, 1)
	local c1 = 1.70158
	return 1 + (c1 + 1) * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
end

-- 0..1 -> 0..1, fast then gentle (Quad, Out)
function DragonUI.QuadOut(t: number): number
	t = math.clamp(t, 0, 1)
	return 1 - (1 - t) * (1 - t)
end

return DragonUI
