--// QQHUD (cleaned up)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local LP = Players.LocalPlayer
local PlayerGui = LP:WaitForChild("PlayerGui")

-- remove any previous copy (re-execute safe)
for _, n in ipairs({ "qqhud", "qqhud_notify" }) do
	local old = PlayerGui:FindFirstChild(n)
	if old then old:Destroy() end
end

--========================
-- CONFIG
--========================
local COLORS = {
	Uncommon = Color3.fromRGB(0, 255, 0),
	Rare = Color3.fromRGB(127, 0, 255),
	Epic = Color3.fromRGB(0, 255, 255),
	Legendary = Color3.fromRGB(255, 244, 119),
	Ultimate = Color3.fromRGB(0, 0, 0),
}

local HIGHLIGHT = {
	Uncommon = Color3.fromRGB(0, 255, 0),
	Rare = Color3.fromRGB(127, 0, 255),
	Epic = Color3.fromRGB(0, 255, 255),
	Legendary = Color3.fromRGB(255, 244, 119),
	Ultimate = Color3.fromRGB(255, 0, 0), -- Highlight red
}

local BAG_ORDER = { "Uncommon", "Rare", "Epic", "Legendary", "Ultimate" }

-- Seasonals
local HALLOWEEN_COLOR = Color3.fromRGB(222, 111, 0)
local CANDY_SCRIPT_NAME = "CandyCornScript"
local CANDY_PART_COLOR = Color3.fromRGB(163, 162, 165) -- also needs Neon material
local CANDY_HIGHLIGHT = Color3.fromRGB(255, 190, 40)

-- Caches (these are plain parts, rarity comes from part color)
local CACHE_ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Ultimate" }
local CACHE_COLORS = {
	Common = Color3.fromRGB(255, 255, 255),
	Uncommon = Color3.fromRGB(100, 255, 100),
	Rare = Color3.fromRGB(228, 100, 255),
	Epic = Color3.fromRGB(100, 255, 255),
	Legendary = Color3.fromRGB(255, 255, 100),
	Ultimate = Color3.fromRGB(255, 100, 100),
}

local CONFIG = {
	ScanInterval = 0.3, -- seconds between scans (highlights refresh constantly)
	ToggleKey = Enum.KeyCode.RightControl,
	ClickSound = "rbxassetid://77082587278347",
	NotifySound = "rbxassetid://74316354846007",
	NotifyRarities = { Epic = true, Legendary = true, Ultimate = true },
	NotifyTime = 4,
	-- Caches are direct child parts of this folder in workspace (nothing deeper is searched)
	CacheFolder = "Map",
	-- Trail changer: workspace.<GearFolder>.<your name> holds an emitter named <TrailName>
	GearFolder = "PlayerGear",
	TrailName = "GlowingParticle",
}

local THEME = {
	Bg = Color3.fromRGB(24, 24, 28),
	Btn = Color3.fromRGB(46, 46, 54),
	BtnHover = Color3.fromRGB(64, 64, 76),
	Accent = Color3.fromRGB(255, 140, 30),
	Text = Color3.fromRGB(235, 235, 240),
	Line = Color3.fromRGB(60, 60, 70),
}

--========================
-- Helpers
--========================
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

-- integer color key so float rounding never breaks matching
local function colorKey(c)
	return math.floor(c.R * 255 + 0.5) * 65536 + math.floor(c.G * 255 + 0.5) * 256 + math.floor(c.B * 255 + 0.5)
end

local BAG_BY_KEY, CACHE_BY_KEY = {}, {}
for name, c in pairs(COLORS) do BAG_BY_KEY[colorKey(c)] = name end
for name, c in pairs(CACHE_COLORS) do CACHE_BY_KEY[colorKey(c)] = name end
local HALLOWEEN_KEY = colorKey(HALLOWEEN_COLOR)
local CANDY_KEY = colorKey(CANDY_PART_COLOR)

local connections = {}
local function connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(connections, c)
	return c
end

--========================
-- Sounds
--========================
local clickSound = new("Sound", { SoundId = CONFIG.ClickSound, Volume = 0.6 }, nil)
local notifySound = new("Sound", { SoundId = CONFIG.NotifySound, Volume = 4 }, nil)

local function playSound(template)
	local s = template:Clone()
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, 4)
end

--========================
-- Highlight tracker (one per feature)
--========================
local function defaultTarget(part)
	local p = part.Parent
	if p and p:IsA("Model") then return p end -- never highlight a Folder / workspace
	return part
end

local function newTracker()
	local T = { items = {} }

	function T:Remove(part)
		local it = self.items[part]
		if not it then return end
		if it.Highlight then it.Highlight:Destroy() end
		if it.Gui then it.Gui:Destroy() end
		self.items[part] = nil
	end

	function T:Clear()
		for part in pairs(self.items) do self:Remove(part) end
	end

	-- desired[part] = { Color = Color3, Text = string, Target = Instance? }
	function T:Sync(desired)
		for part in pairs(self.items) do
			if not desired[part] or not part:IsDescendantOf(workspace) then
				self:Remove(part)
			end
		end
		for part, d in pairs(desired) do
			local it = self.items[part]
			if not it then
				local target = d.Target or defaultTarget(part)

				local hl = Instance.new("Highlight")
				hl.FillTransparency = .45
				hl.OutlineTransparency = 0
				hl.Adornee = target
				hl.Parent = target

				local bill = Instance.new("BillboardGui")
				bill.Size = UDim2.new(0, 150, 0, 24)
				bill.AlwaysOnTop = true
				bill.StudsOffset = Vector3.new(0, 3, 0)
				bill.Adornee = part
				bill.Parent = part

				local txt = Instance.new("TextLabel")
				txt.Size = UDim2.fromScale(1, 1)
				txt.BackgroundTransparency = 1
				txt.Font = Enum.Font.Code
				txt.TextScaled = false -- same fixed size on every billboard
				txt.TextSize = 10
				txt.TextStrokeTransparency = 0
				txt.TextStrokeColor3 = Color3.new(0, 0, 0)
				txt.Parent = bill

				it = { Part = part, Highlight = hl, Gui = bill, Label = txt }
				self.items[part] = it
			end
			it.Prefix = d.Text
			if it.Color ~= d.Color then
				it.Color = d.Color
				it.Highlight.FillColor = d.Color
				it.Highlight.OutlineColor = d.Color
				it.Label.TextColor3 = d.Color
			end
		end
	end

	function T:UpdateLabels(rootPos)
		for part, it in pairs(self.items) do
			if part.Parent then
				it.Label.Text = string.format("%s | %.0f studs", it.Prefix, (rootPos - part.Position).Magnitude)
			end
		end
	end

	return T
end

local trackers = {
	Bag = newTracker(),
	Halloween = newTracker(),
	Candy = newTracker(),
	Cache = newTracker(),
}

--========================
-- State
--========================
local state = { Bag = nil, Halloween = false, Candy = false, Cache = nil }
local knownCaches, autoHL = {}, {}
local cacheSeeded = false

--========================
-- Notifications (top of screen)
--========================
local notifyGui = new("ScreenGui", {
	Name = "qqhud_notify", ResetOnSpawn = false, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 60,
}, PlayerGui)

local notifyHolder = new("Frame", {
	Size = UDim2.new(0, 380, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
	AnchorPoint = Vector2.new(.5, 0), Position = UDim2.new(.5, 0, 0, 90),
	BackgroundTransparency = 1,
}, notifyGui)
new("UIListLayout", {
	Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
}, notifyHolder)

local notifyOrder = 0
local function notify(rarity)
	local color = CACHE_COLORS[rarity]
	notifyOrder -= 1 -- newest on top

	local card = new("Frame", {
		Size = UDim2.new(1, 0, 0, 56), BackgroundColor3 = THEME.Bg, BackgroundTransparency = 1,
		BorderSizePixel = 0, LayoutOrder = notifyOrder,
	}, notifyHolder)
	new("UICorner", { CornerRadius = UDim.new(0, 8) }, card)
	local stroke = new("UIStroke", { Color = color, Thickness = 2, Transparency = 1 }, card)
	local label = new("TextLabel", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.Code,
		TextSize = 24, TextColor3 = color, TextTransparency = 1,
		TextStrokeColor3 = Color3.new(0, 0, 0), TextStrokeTransparency = 1,
		Text = string.upper(rarity) .. " CACHE SPAWNED!",
	}, card)

	playSound(notifySound)

	local info = TweenInfo.new(.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(card, info, { BackgroundTransparency = .1 }):Play()
	TweenService:Create(stroke, info, { Transparency = 0 }):Play()
	TweenService:Create(label, info, { TextTransparency = 0, TextStrokeTransparency = .3 }):Play()

	-- pulse: the card glows with the rarity color and the outline breathes
	local pulseInfo = TweenInfo.new(.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local pulses = {
		TweenService:Create(card, pulseInfo, { BackgroundColor3 = THEME.Bg:Lerp(color, .35) }),
		TweenService:Create(stroke, pulseInfo, { Thickness = 5 }),
	}
	for _, p in ipairs(pulses) do p:Play() end

	task.delay(CONFIG.NotifyTime, function()
		if not card.Parent then return end
		for _, p in ipairs(pulses) do p:Cancel() end
		local out = TweenInfo.new(.4)
		TweenService:Create(card, out, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(stroke, out, { Transparency = 1 }):Play()
		TweenService:Create(label, out, { TextTransparency = 1 }):Play()
		Debris:AddItem(card, .5)
	end)
end

--========================
-- World index (event driven, so the workspace is never re-walked = no lag)
--========================
local mains = {} -- bag unions ("Main"), kept up to date by events

local function index(d)
	if d:IsA("UnionOperation") and d.Name == "Main" then
		mains[d] = true
	end
end

local function unindex(d)
	mains[d] = nil
end

connect(workspace.DescendantAdded, index)
connect(workspace.DescendantRemoving, unindex)

-- one-time initial index, spread over frames so it never freezes the game
task.spawn(function()
	local n = 0
	for _, d in ipairs(workspace:GetDescendants()) do
		index(d)
		n += 1
		if n % 1500 == 0 then task.wait() end
	end
end)

--========================
-- Scan (cheap: only touches the small indexed sets + Map's direct children)
--========================
local function scan()
	local bags, hallo, candy, caches = {}, {}, {}, {}

	if state.Bag or state.Halloween then
		for d in pairs(mains) do
			if d.Parent then
				local k = colorKey(d.Color)
				local r = BAG_BY_KEY[k]
				if r then
					bags[d] = r
				elseif k == HALLOWEEN_KEY then
					hallo[d] = true
				end
			end
		end
	end

	if state.Candy then
		-- workspace only: direct child parts (folders and everything deeper are ignored)
		for _, p in ipairs(workspace:GetChildren()) do
			if p:IsA("BasePart") and (
				p:FindFirstChild(CANDY_SCRIPT_NAME)
				or (p.Material == Enum.Material.Neon and colorKey(p.Color) == CANDY_KEY)
			) then
				candy[p] = true
			end
		end
	end

	-- caches: ONLY direct child parts of the Map folder (other folders are ignored)
	local map = workspace:FindFirstChild(CONFIG.CacheFolder)
	if map then
		for _, p in ipairs(map:GetChildren()) do
			if p:IsA("BasePart") and p.Transparency < 1 then
				local r = CACHE_BY_KEY[colorKey(p.Color)]
				if r then caches[p] = r end
			end
		end
	end

	for part, rarity in pairs(caches) do
		if knownCaches[part] ~= rarity then
			knownCaches[part] = rarity
			if cacheSeeded and CONFIG.NotifyRarities[rarity] then
				autoHL[part] = rarity
				notify(rarity)
			end
		end
	end
	for part in pairs(knownCaches) do
		if not caches[part] then
			knownCaches[part] = nil
			autoHL[part] = nil
		end
	end
	cacheSeeded = true

	-- build desired highlight sets
	local bagDesired, halloDesired, candyDesired, cacheDesired = {}, {}, {}, {}

	if state.Bag then
		for part, r in pairs(bags) do
			if state.Bag == "All" or state.Bag == r then
				bagDesired[part] = { Color = HIGHLIGHT[r], Text = r .. " Bag" }
			end
		end
	end
	if state.Halloween then
		for part in pairs(hallo) do
			halloDesired[part] = { Color = HALLOWEEN_COLOR, Text = "Halloween Bag" }
		end
	end
	if state.Candy then
		for part in pairs(candy) do
			candyDesired[part] = { Color = CANDY_HIGHLIGHT, Text = "Candy Corn", Target = part }
		end
	end
	for part, r in pairs(caches) do
		if state.Cache == "All" or state.Cache == r or autoHL[part] then
			cacheDesired[part] = { Color = CACHE_COLORS[r], Text = r .. " Cache", Target = part }
		end
	end

	trackers.Bag:Sync(bagDesired)
	trackers.Halloween:Sync(halloDesired)
	trackers.Candy:Sync(candyDesired)
	trackers.Cache:Sync(cacheDesired)
end

local function safeScan()
	local ok, err = pcall(scan)
	if not ok then warn("[QQHUD] scan error: " .. tostring(err)) end
end

--========================
-- GUI
--========================
local gui = new("ScreenGui", {
	Name = "qqhud", ResetOnSpawn = false, IgnoreGuiInset = true,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 50,
}, PlayerGui)

-- hit marker layer (only ever spawned from GUI clicks)
local overlay = new("Frame", {
	Name = "Overlay", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 100,
}, gui)

local function hitMarker()
	local m = UserInputService:GetMouseLocation()
	local holder = new("Frame", {
		BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0),
		Position = UDim2.fromOffset(m.X, m.Y), ZIndex = 100,
	}, overlay)
	local dirs = { { -1, -1, 45 }, { 1, 1, 45 }, { 1, -1, -45 }, { -1, 1, -45 } }
	for _, d in ipairs(dirs) do
		local bar = new("Frame", {
			AnchorPoint = Vector2.new(.5, .5), Size = UDim2.fromOffset(9, 2),
			Position = UDim2.fromOffset(d[1] * 8, d[2] * 8), Rotation = d[3],
			BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 100,
		}, holder)
		TweenService:Create(bar, TweenInfo.new(.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.fromOffset(d[1] * 15, d[2] * 15),
			BackgroundTransparency = 1,
		}):Play()
	end
	Debris:AddItem(holder, .4)
end

local lastFeedback = 0
local function feedback()
	if os.clock() - lastFeedback < .08 then return end
	lastFeedback = os.clock()
	playSound(clickSound)
	hitMarker()
end

local function bindBackgroundClicks(guiObject)
	connect(guiObject.InputBegan, function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			feedback()
		end
	end)
end

local function styleBox(f)
	new("UICorner", { CornerRadius = UDim.new(0, 10) }, f)
	new("UIStroke", { Color = THEME.Line, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
	}, f)
	new("UIListLayout", {
		Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, f)
end

local frame = new("Frame", {
	Name = "Main", Size = UDim2.new(0, 190, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
	Position = UDim2.new(0.02, 0, 0.25, 0), BackgroundColor3 = THEME.Bg,
	BorderSizePixel = 0, Active = true,
}, gui)
styleBox(frame)
bindBackgroundClicks(frame)

local title = new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 26), BackgroundTransparency = 1, Text = "QQ HUD",
	Font = Enum.Font.Code, TextSize = 18, TextColor3 = Color3.new(1, 1, 1),
	LayoutOrder = 0, Active = true,
}, frame)

-- drag by title
do
	local dragging, dragStart, startPos
	connect(title.InputBegan, function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging, dragStart, startPos = true, i.Position, frame.Position
			local c
			c = i.Changed:Connect(function()
				if i.UserInputState == Enum.UserInputState.End then
					dragging = false
					c:Disconnect()
				end
			end)
		end
	end)
	connect(UserInputService.InputChanged, function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			local d = i.Position - dragStart
			frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
		end
	end)
end

-- side column for pop-outs, follows the main frame
local side = new("Frame", {
	Name = "Side", Size = UDim2.new(0, 175, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
}, gui)
new("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, side)

local function placeSide()
	local p, s = frame.AbsolutePosition, frame.AbsoluteSize
	side.Position = UDim2.fromOffset(p.X + s.X + 8, p.Y)
end
connect(frame:GetPropertyChangedSignal("AbsolutePosition"), placeSide)
connect(frame:GetPropertyChangedSignal("AbsoluteSize"), placeSide)
task.defer(placeSide)

local orders = {}
local function nextOrder(parent)
	orders[parent] = (orders[parent] or 0) + 1
	return orders[parent]
end

-- returns button, setActive(bool)
local function Button(parent, txt, accent, onClick)
	local b = new("TextButton", {
		Size = UDim2.new(1, 0, 0, 28), BackgroundColor3 = THEME.Btn, TextColor3 = accent or THEME.Text,
		TextSize = 14, Font = Enum.Font.Code, Text = txt, AutoButtonColor = false,
		BorderSizePixel = 0, LayoutOrder = nextOrder(parent),
	}, parent)
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
	local stroke = new("UIStroke", {
		Color = accent or THEME.Accent, Thickness = 1.5, Transparency = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, b)

	connect(b.MouseEnter, function()
		TweenService:Create(b, TweenInfo.new(.12), { BackgroundColor3 = THEME.BtnHover }):Play()
	end)
	connect(b.MouseLeave, function()
		TweenService:Create(b, TweenInfo.new(.12), { BackgroundColor3 = THEME.Btn }):Play()
	end)
	connect(b.MouseButton1Down, feedback)
	connect(b.MouseButton1Click, function()
		feedback() -- no-op if already fired on press (debounced)
		if onClick then onClick() end
	end)

	local function setActive(on)
		TweenService:Create(stroke, TweenInfo.new(.15), { Transparency = on and 0 or 1 }):Play()
	end
	return b, setActive
end

local function Panel(name, header, order)
	local p = new("Frame", {
		Name = name, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = THEME.Bg, BorderSizePixel = 0, Visible = false,
		Active = true, LayoutOrder = order,
	}, side)
	styleBox(p)
	bindBackgroundClicks(p)
	new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Text = header,
		Font = Enum.Font.Code, TextSize = 16, TextColor3 = Color3.new(1, 1, 1), LayoutOrder = 0,
	}, p)
	return p
end

local seasonalsPanel = Panel("Seasonals", "Seasonals", 1)
local cachesPanel = Panel("Caches", "Caches", 2)
local playerPanel = Panel("Player", "Player", 3)

--========================
-- Bag buttons (main)
--========================
local bagActive = {}
local function setBag(name)
	state.Bag = (state.Bag == name) and nil or name
	for n, setA in pairs(bagActive) do setA(state.Bag == n) end
	safeScan()
end

local _, a = Button(frame, "Highlight All", nil, function() setBag("All") end)
bagActive.All = a
for _, name in ipairs(BAG_ORDER) do
	local _, setA = Button(frame, name, HIGHLIGHT[name], function() setBag(name) end)
	bagActive[name] = setA
end

--========================
-- Seasonals pop-out
--========================
local setHalloween, setCandy
_, setHalloween = Button(seasonalsPanel, "Halloween Bag", HALLOWEEN_COLOR, function()
	state.Halloween = not state.Halloween
	setHalloween(state.Halloween)
	safeScan()
end)
_, setCandy = Button(seasonalsPanel, "Candy Corn", CANDY_HIGHLIGHT, function()
	state.Candy = not state.Candy
	setCandy(state.Candy)
	safeScan()
end)

--========================
-- Caches pop-out
--========================
local cacheActive = {}
local function setCache(name)
	state.Cache = (state.Cache == name) and nil or name
	for n, setA in pairs(cacheActive) do setA(state.Cache == n) end
	safeScan()
end
local _, ca = Button(cachesPanel, "All Caches", nil, function() setCache("All") end)
cacheActive.All = ca
for _, name in ipairs(CACHE_ORDER) do
	local _, setA = Button(cachesPanel, name, CACHE_COLORS[name], function() setCache(name) end)
	cacheActive[name] = setA
end

--========================
-- Player pop-out (trail changer)
--========================
local function Slider(parent, text, min, max, default, decimals, onChange)
	local holder = new("Frame", {
		Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, LayoutOrder = nextOrder(parent),
	}, parent)
	local lbl = new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Font = Enum.Font.Code,
		TextSize = 14, TextColor3 = THEME.Text, TextXAlignment = Enum.TextXAlignment.Left,
	}, holder)
	local track = new("Frame", {
		Position = UDim2.new(0, 0, 0, 26), Size = UDim2.new(1, 0, 0, 8),
		BackgroundColor3 = THEME.Btn, BorderSizePixel = 0,
	}, holder)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, track)
	local fill = new("Frame", {
		Size = UDim2.fromScale(0, 1), BackgroundColor3 = THEME.Accent, BorderSizePixel = 0,
	}, track)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, fill)
	local knob = new("Frame", {
		AnchorPoint = Vector2.new(.5, .5), Size = UDim2.fromOffset(14, 14), Position = UDim2.fromScale(0, .5),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 2,
	}, track)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, knob)

	local mult = 10 ^ decimals
	local function set(v, silent)
		v = math.clamp(math.floor(v * mult + 0.5) / mult, min, max)
		local a = (v - min) / (max - min)
		fill.Size = UDim2.fromScale(a, 1)
		knob.Position = UDim2.fromScale(a, .5)
		lbl.Text = string.format("%s: %." .. decimals .. "f", text, v)
		if not silent and onChange then onChange(v) end
	end
	set(default, true)

	local dragging = false
	local function fromMouse(x)
		local a = math.clamp((x - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1), 0, 1)
		set(min + (max - min) * a)
	end
	connect(holder.InputBegan, function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			feedback()
			fromMouse(i.Position.X)
		end
	end)
	connect(UserInputService.InputChanged, function(i)
		if dragging and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
			fromMouse(i.Position.X)
		end
	end)
	connect(UserInputService.InputEnded, function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	return { Set = set, IsDragging = function() return dragging end }
end

-- ColorSequence strings are "time r g b 0" repeated per keypoint
local PRESET_ORDER = { "Sunset", "Rainbow", "Red & Blue", "Rainy Day" }
local PRESET_STRINGS = {
	["Sunset"] = "0 1 0.90411 0 0 0.304 1 0.356164 0 0 0.585 0 0.136986 1 0 0.787 0.60274 0 1 0 1 1 0.79452 0 0",
	["Rainbow"] = "0 1 0 0 0 0.200318 1 0.493151 0 0 0.4 0.986301 1 0 0 0.6 0.136986 1 0 0 0.8 0 0.273973 1 0 1 1 0 0.958904 0",
	["Red & Blue"] = "0 0 0.273973 1 0 1 1 0 0 0",
	["Rainy Day"] = "0 0 0.273973 1 0 0.2 0.0472363 0.543195 1 0 0.4 0 0.0273974 1 0 0.6 0 0.371184 0.97579 0 1 0 1 0.931507 0",
}
local PRESET_ACCENT = {
	["Sunset"] = Color3.fromRGB(255, 150, 60),
	["Rainbow"] = Color3.fromRGB(255, 110, 200),
	["Red & Blue"] = Color3.fromRGB(150, 120, 255),
	["Rainy Day"] = Color3.fromRGB(90, 175, 255),
}

local function parseSequence(str)
	local t = {}
	for tok in string.gmatch(str, "%S+") do t[#t + 1] = tonumber(tok) end
	local kps, i = {}, 1
	while i + 3 <= #t do
		kps[#kps + 1] = ColorSequenceKeypoint.new(
			math.clamp(t[i], 0, 1),
			Color3.new(math.clamp(t[i + 1], 0, 1), math.clamp(t[i + 2], 0, 1), math.clamp(t[i + 3], 0, 1))
		)
		i += 5
	end
	-- a ColorSequence must start at 0 and end at 1
	kps[1] = ColorSequenceKeypoint.new(0, kps[1].Value)
	kps[#kps] = ColorSequenceKeypoint.new(1, kps[#kps].Value)
	return ColorSequence.new(kps)
end

local PRESETS = {}
for name, str in pairs(PRESET_STRINGS) do
	local ok, seq = pcall(parseSequence, str)
	if ok then PRESETS[name] = seq else warn("[QQHUD] bad preset " .. name) end
end

-- saved settings: re-applied automatically whenever the trail is recreated (e.g. after dying)
local trail = { Lifetime = nil, Brightness = nil, Color = nil, ColorName = nil, Face = false }
local emitters = {}
local trailFolder, folderConn
local trailDirty = true
local orig = setmetatable({}, { __mode = "k" })
local appliedColor = setmetatable({}, { __mode = "k" })
local synced = setmetatable({}, { __mode = "k" })
local safeTrail

-- GlowingParticle can be a ParticleEmitter or a Trail; these helpers hide the differences
local function isFx(d) return d:IsA("ParticleEmitter") or d:IsA("Trail") end
local function lifeMax(v) return typeof(v) == "NumberRange" and v.Max or v end
local function setFace(e, on)
	if e:IsA("Trail") then
		e.FaceCamera = on
	else
		e.Orientation = Enum.ParticleOrientation.FacingCamera
	end
end
local function restoreFace(e, o)
	if e:IsA("Trail") then
		if o.Face ~= nil then e.FaceCamera = o.Face end
	elseif o.Orient then
		e.Orientation = o.Orient
	end
end

local statusLabel = new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 13,
	TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(170, 170, 180),
	Text = "Trail: searching...", LayoutOrder = nextOrder(playerPanel),
}, playerPanel)

local lifeSlider = Slider(playerPanel, "Lifetime", 0.1, 10, 1, 1, function(v)
	trail.Lifetime = v
	safeTrail()
end)
local brightSlider = Slider(playerPanel, "Brightness", 0, 10, 1, 1, function(v)
	trail.Brightness = v
	safeTrail()
end)

local setFaceActive
_, setFaceActive = Button(playerPanel, "Face Camera", nil, function()
	trail.Face = not trail.Face
	setFaceActive(trail.Face)
	if not trail.Face then
		for _, e in ipairs(emitters) do
			local o = orig[e]
			if o and e:IsDescendantOf(workspace) then restoreFace(e, o) end
		end
	end
	safeTrail()
end)

new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Font = Enum.Font.Code, TextSize = 14,
	TextColor3 = THEME.Text, TextXAlignment = Enum.TextXAlignment.Left, Text = "Color Presets",
	LayoutOrder = nextOrder(playerPanel),
}, playerPanel)

local presetActive = {}
for _, name in ipairs(PRESET_ORDER) do
	if PRESETS[name] then
		local _, setA = Button(playerPanel, name, PRESET_ACCENT[name], function()
			if trail.ColorName == name then
				-- toggle off: put the game's original color back
				trail.Color, trail.ColorName = nil, nil
				for _, e in ipairs(emitters) do
					local o = orig[e]
					if o and e:IsDescendantOf(workspace) then e.Color = o.Color end
					appliedColor[e] = nil
				end
			else
				trail.Color, trail.ColorName = PRESETS[name], name
			end
			for n, sa in pairs(presetActive) do sa(trail.ColorName == n) end
			safeTrail()
		end)
		presetActive[name] = setA
	end
end

Button(playerPanel, "Reset Trail", Color3.fromRGB(255, 100, 100), function()
	trail.Lifetime, trail.Brightness, trail.Color, trail.ColorName, trail.Face = nil, nil, nil, nil, false
	for _, e in ipairs(emitters) do
		local o = orig[e]
		if o and e:IsDescendantOf(workspace) then
			e.Lifetime = o.Lifetime
			e.Color = o.Color
			restoreFace(e, o)
			e.LightEmission = o.LightEmission
			if o.Brightness then pcall(function() e.Brightness = o.Brightness end) end
			lifeSlider.Set(lifeMax(o.Lifetime), true)
			if o.Brightness then brightSlider.Set(o.Brightness, true) end
		end
		appliedColor[e] = nil
	end
	setFaceActive(false)
	for _, sa in pairs(presetActive) do sa(false) end
end)

local function getTrailFolder()
	local gear = workspace:FindFirstChild(CONFIG.GearFolder)
	if not gear then return nil, "no " .. CONFIG.GearFolder end
	return gear:FindFirstChild(LP.Name) or gear:FindFirstChild(LP.DisplayName), "waiting for " .. LP.Name
end

local function collectEmitters(f)
	local list, seen = {}, {}
	for _, d in ipairs(f:GetDescendants()) do
		if d.Name == CONFIG.TrailName then
			if isFx(d) then
				if not seen[d] then seen[d] = true; list[#list + 1] = d end
			else
				for _, c in ipairs(d:GetDescendants()) do
					if isFx(c) and not seen[c] then seen[c] = true; list[#list + 1] = c end
				end
			end
		end
	end
	return list
end

local function remember(e)
	if orig[e] then return orig[e] end
	local o = { Lifetime = e.Lifetime, Color = e.Color, LightEmission = e.LightEmission }
	if e:IsA("Trail") then o.Face = e.FaceCamera else o.Orient = e.Orientation end
	pcall(function() o.Brightness = e.Brightness end)
	orig[e] = o
	return o
end

local function applyTrail(e)
	if trail.Lifetime then
		local lt = e.Lifetime
		if typeof(lt) == "NumberRange" then
			if math.abs(lt.Min - trail.Lifetime) > 1e-3 or math.abs(lt.Max - trail.Lifetime) > 1e-3 then
				e.Lifetime = NumberRange.new(trail.Lifetime)
			end
		elseif math.abs(lt - trail.Lifetime) > 1e-3 then
			e.Lifetime = trail.Lifetime
		end
	end
	if trail.Brightness then
		local ok = pcall(function()
			if math.abs(e.Brightness - trail.Brightness) > 1e-3 then e.Brightness = trail.Brightness end
		end)
		if not ok then e.LightEmission = math.clamp(trail.Brightness / 10, 0, 1) end -- older engines
	end
	if trail.Color and appliedColor[e] ~= trail.Color then
		e.Color = trail.Color
		appliedColor[e] = trail.Color
	end
	if trail.Face then
		if e:IsA("Trail") then
			if not e.FaceCamera then e.FaceCamera = true end
		elseif e.Orientation ~= Enum.ParticleOrientation.FacingCamera then
			setFace(e, true)
		end
	end
end

local function trailStep()
	local f, why = getTrailFolder()
	if f ~= trailFolder then
		trailFolder = f
		if folderConn then folderConn:Disconnect() folderConn = nil end
		if f then
			folderConn = connect(f.DescendantAdded, function(d)
				if isFx(d) or d.Name == CONFIG.TrailName then trailDirty = true end
			end)
		end
		trailDirty = true
	end
	for _, e in ipairs(emitters) do
		if not e:IsDescendantOf(workspace) then trailDirty = true break end
	end
	if trailDirty then
		trailDirty = false
		emitters = f and collectEmitters(f) or {}
	end

	if #emitters == 0 then
		statusLabel.Text = "Trail: " .. (f and ("no " .. CONFIG.TrailName) or why)
		statusLabel.TextColor3 = Color3.fromRGB(255, 130, 130)
		return
	end

	statusLabel.Text = "Trail: found (" .. #emitters .. ")"
	statusLabel.TextColor3 = Color3.fromRGB(120, 255, 140)

	local anySetting = trail.Lifetime or trail.Brightness or trail.Color or trail.Face
	for _, e in ipairs(emitters) do
		if e:IsDescendantOf(workspace) then
			remember(e)
			if anySetting then applyTrail(e) end
		end
	end

	-- show the game's current values on the sliders until you change them
	local e = emitters[1]
	if not synced[e] then
		synced[e] = true
		if not trail.Lifetime and not lifeSlider.IsDragging() then lifeSlider.Set(lifeMax(e.Lifetime), true) end
		if not trail.Brightness and orig[e] and orig[e].Brightness then brightSlider.Set(orig[e].Brightness, true) end
	end
end

safeTrail = function()
	local ok, err = pcall(trailStep)
	if not ok then warn("[QQHUD] trail error: " .. tostring(err)) end
end

connect(LP.CharacterAdded, function() trailDirty = true end)
task.spawn(function()
	while gui.Parent do
		safeTrail()
		task.wait(0.2)
	end
end)

--========================
-- Main toggles + Clear
--========================
local setSeasonalsOpen, setCachesOpen, setPlayerOpen
_, setSeasonalsOpen = Button(frame, "Seasonals", nil, function()
	seasonalsPanel.Visible = not seasonalsPanel.Visible
	setSeasonalsOpen(seasonalsPanel.Visible)
end)
_, setCachesOpen = Button(frame, "Caches", nil, function()
	cachesPanel.Visible = not cachesPanel.Visible
	setCachesOpen(cachesPanel.Visible)
end)
_, setPlayerOpen = Button(frame, "Player", nil, function()
	playerPanel.Visible = not playerPanel.Visible
	setPlayerOpen(playerPanel.Visible)
end)

Button(frame, "Clear", Color3.fromRGB(255, 100, 100), function()
	state.Bag, state.Halloween, state.Candy, state.Cache = nil, false, false, nil
	table.clear(autoHL)
	for _, setA in pairs(bagActive) do setA(false) end
	for _, setA in pairs(cacheActive) do setA(false) end
	setHalloween(false)
	setCandy(false)
	for _, t in pairs(trackers) do t:Clear() end
	safeScan()
end)

--========================
-- Right Ctrl toggles the GUI
--========================
connect(UserInputService.InputBegan, function(input)
	if input.KeyCode == CONFIG.ToggleKey and not UserInputService:GetFocusedTextBox() then
		gui.Enabled = not gui.Enabled
	end
end)

--========================
-- Loops
--========================
local labelConn
local labelAcc = 0
labelConn = RunService.RenderStepped:Connect(function(dt)
	if not gui.Parent then
		labelConn:Disconnect()
		return
	end
	labelAcc += dt
	if labelAcc < 0.1 then return end -- distance text only needs ~10 updates/sec
	labelAcc = 0
	local char = LP.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	for _, t in pairs(trackers) do t:UpdateLabels(root.Position) end
end)

task.spawn(function()
	while gui.Parent do
		safeScan()
		task.wait(CONFIG.ScanInterval)
	end
end)

-- full cleanup if the GUI is destroyed (e.g. script re-executed)
gui.Destroying:Connect(function()
	for _, c in ipairs(connections) do c:Disconnect() end
	for _, t in pairs(trackers) do t:Clear() end
	notifyGui:Destroy()
end)

--// SUPER OPSEC MODE
--// LocalScript - StarterPlayer > StarterPlayerScripts

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

--------------------------------------------------
-- CONFIG
--------------------------------------------------

local IMAGE_ID = "rbxassetid://93061945307159"
local SOUND_ID = "rbxassetid://140729021718836"

local FADE_TIME = 5 -- seconds
local IMAGE_TRANSPARENCY = 0.15

--------------------------------------------------
-- GUI
--------------------------------------------------

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SuperOpsecMode"
ScreenGui.IgnoreGuiInset = true -- covers the top bar too
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 999999
ScreenGui.Parent = PlayerGui

--------------------------------------------------
-- FULL SCREEN IMAGE
--------------------------------------------------

local Image = Instance.new("ImageLabel")
Image.Name = "HackerImage"
Image.AnchorPoint = Vector2.new(0.5, 0.5)
Image.Position = UDim2.fromScale(0.5, 0.5)
Image.Size = UDim2.fromScale(1, 1)
Image.BackgroundTransparency = 1
Image.BorderSizePixel = 0
Image.Image = IMAGE_ID
Image.ImageTransparency = IMAGE_TRANSPARENCY

-- Stretches the image to exactly fill the screen
Image.ScaleType = Enum.ScaleType.Stretch

Image.Parent = ScreenGui

--------------------------------------------------
-- CENTER TEXT
--------------------------------------------------

local Text = Instance.new("TextLabel")
Text.Name = "HackerText"
Text.AnchorPoint = Vector2.new(0.5, 0.5)
Text.Position = UDim2.fromScale(0.5, 0.5)
Text.Size = UDim2.fromScale(0.9, 0.15)

Text.BackgroundTransparency = 1
Text.Text = "SUPER OPSEC MODE ACTIVE!!! SCRIPT LOADED!!"

Text.TextColor3 = Color3.fromRGB(0, 255, 0)
Text.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
Text.TextStrokeTransparency = 0

Text.Font = Enum.Font.Code
Text.TextScaled = true
Text.TextWrapped = true

Text.Parent = ScreenGui

--------------------------------------------------
-- SOUND
--------------------------------------------------

local Sound = Instance.new("Sound")
Sound.Name = "OpsecSound"
Sound.SoundId = SOUND_ID
Sound.Volume = 4
Sound.Parent = ScreenGui

Sound:Play()

--------------------------------------------------
-- FADE OUT
--------------------------------------------------

task.wait(1)

local FadeInfo = TweenInfo.new(
	FADE_TIME,
	Enum.EasingStyle.Linear,
	Enum.EasingDirection.Out
)

local ImageFade = TweenService:Create(
	Image,
	FadeInfo,
	{
		ImageTransparency = 1
	}
)

local TextFade = TweenService:Create(
	Text,
	FadeInfo,
	{
		TextTransparency = 1,
		TextStrokeTransparency = 1
	}
)

ImageFade:Play()
TextFade:Play()

--------------------------------------------------
-- CLEAN UP
--------------------------------------------------

task.wait(FADE_TIME)

ScreenGui:Destroy()