-- License: MIT
-- Copyright: @svyixiu (https://github.com/svyixiu/PolyRenderer)

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")

local Drawing = {}

Drawing.VERSION = "1.0.0"

Drawing.Fonts = table.freeze({ UI = 0, System = 1, Plex = 2, Monospace = 3 })

local FONT_FACES = {
	[0] = Font.fromEnum(Enum.Font.SourceSans),
	[1] = Font.fromEnum(Enum.Font.Arial),
	[2] = Font.fromEnum(Enum.Font.Gotham),
	[3] = Font.fromEnum(Enum.Font.RobotoMono),
}

local SMOOTH_CIRCLE_SIDES = 32
local SEAM_OVERLAP = 1   -- px each right-triangle piece grows along its legs
local HYP_OVERLAP = 1    -- px the diagonal cut is pushed outward
local CLONE_TRANSPARENCY = 0.999
local REBUILD_COOLDOWN = 0.25   -- s between clone rebuilds caused by adornee part changes
local HIGHLIGHT_LIMIT = 31      -- Roblox renders at most this many Highlights at once
local WHITE = Color3.new(1, 1, 1)
local UDIM_ZERO = UDim.new(0, 0)
local UDIM_ROUND = UDim.new(0.5, 0)

---------------------------------------------------------------- containers

local function randomName(): string
	return (HttpService:GenerateGUID(false):gsub("-", ""))
end

local screenGui: ScreenGui? = nil

local function container(): ScreenGui
	if screenGui and screenGui.Parent then return screenGui end
	assert(RunService:IsClient(), "Drawing can only be used from the client")
	local g = Instance.new("ScreenGui")
	g.Name = "Drawing"
	g.IgnoreGuiInset = true       -- GUI pixels == viewport pixels
	g.ResetOnSpawn = false
	g.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	g.DisplayOrder = 1000
	g.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	screenGui = g
	return g
end

-- one full-screen, transparent Frame per GUI object; it carries Visible and ZIndex
local function newFrame(name: string): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Visible = false
	frame.Parent = container()
	return frame
end

local function isAlive(inst: Instance?): boolean
	return inst ~= nil and inst.Parent ~= nil and inst:IsDescendantOf(game)
end

-- where Highlight instances live: gethui(), else CoreGui, else a folder in the camera
local hiddenFolder: Folder? = nil

-- Parenting to CoreGui from a LocalScript doesn't error: it silently leaves Parent nil,
-- so each candidate is verified by reading Parent back.
local function tryParent(folder: Instance, target: any): boolean
	if typeof(target) ~= "Instance" then return false end
	pcall(function() folder.Parent = target end)
	return folder.Parent == target
end

local function protectedFolder(): Folder
	if hiddenFolder and hiddenFolder:IsDescendantOf(game) then return hiddenFolder end
	local folder = Instance.new("Folder")
	folder.Name = randomName()
	local okHui, hui = pcall(function() return gethui() end)
	if not (okHui and tryParent(folder, hui)) and not tryParent(folder, game:GetService("CoreGui")) then
		folder.Parent = workspace.CurrentCamera
	end
	hiddenFolder = folder
	return folder
end

-- where clones live: they must be under workspace to render, so always the camera
local cloneFolder: Folder? = nil

local function worldFolder(): Folder
	local camera = workspace.CurrentCamera
	if cloneFolder and cloneFolder.Parent == camera then return cloneFolder end
	local folder = Instance.new("Folder")
	folder.Name = randomName()
	folder.Parent = camera
	cloneFolder = folder
	return folder
end

---------------------------------------------------------------- part pools
-- Every GUI drawing object owns one full-screen Frame (carries Visible/ZIndex) and draws into it
-- with pooled parts, so shapes made of many pieces (polygons, filled triangles) reuse instances.

local sub = setmetatable({}, { __mode = "k" })   -- part -> { stroke, corner, gradient }

local MAKERS = {}

function MAKERS.line(): GuiObject
	local f = Instance.new("Frame")
	f.Name = "Line"
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BorderSizePixel = 0
	return f
end

-- right triangle: a rectangle cut along its diagonal by a hard-edged UIGradient.
-- The filled half is the one containing the frame's top-left corner.
local CUT = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0),
	NumberSequenceKeypoint.new(0.5, 0),
	NumberSequenceKeypoint.new(0.5001, 1),
	NumberSequenceKeypoint.new(1, 1),
})
function MAKERS.rtri(): GuiObject
	local f = Instance.new("Frame")
	f.Name = "Piece"
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.BorderSizePixel = 0
	local g = Instance.new("UIGradient")
	g.Transparency = CUT
	g.Parent = f
	sub[f] = { gradient = g }
	return f
end

function MAKERS.rect(): GuiObject
	local f = Instance.new("Frame")
	f.Name = "Shape"
	f.BorderSizePixel = 0
	local s = Instance.new("UIStroke")
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.LineJoinMode = Enum.LineJoinMode.Miter
	s.Parent = f
	local c = Instance.new("UICorner")
	c.Parent = f
	sub[f] = { stroke = s, corner = c }
	return f
end

function MAKERS.text(): GuiObject
	local l = Instance.new("TextLabel")
	l.Name = "Text"
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.AutomaticSize = Enum.AutomaticSize.XY
	l.Size = UDim2.fromOffset(0, 0)
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextYAlignment = Enum.TextYAlignment.Top
	l.TextWrapped = false
	l.RichText = false
	return l
end

function MAKERS.image(): GuiObject
	local i = Instance.new("ImageLabel")
	i.Name = "Image"
	i.BackgroundTransparency = 1
	i.BorderSizePixel = 0
	i.ScaleType = Enum.ScaleType.Stretch
	local c = Instance.new("UICorner")
	c.Parent = i
	sub[i] = { corner = c }
	return i
end

local function acquire(st, kind: string): any
	local pool = st.pools[kind]
	if not pool then
		pool = { n = 0, list = {} }
		st.pools[kind] = pool
	end
	pool.n += 1
	local part = pool.list[pool.n]
	if not part then
		part = MAKERS[kind]()
		part.Parent = st.frame
		pool.list[pool.n] = part
	end
	part.Visible = true
	return part
end

---------------------------------------------------------------- UI decorators

-- piece -> { [decorator state] = { inst = the mirrored instance, version = props version } }
local applied = setmetatable({}, { __mode = "k" })
local warnedFilled = setmetatable({}, { __mode = "k" })

-- Forget the mirror records of a piece that is going away, including records nested inside
-- its mirrored strokes. Required, not just tidy: `applied` is weak on the piece, but its values
-- reference decorator states whose Parent references the drawing, whose pools reference the
-- piece - a cycle Luau's weak tables (no ephemerons) never collect.
local function forgetApplied(piece: Instance?)
	local have = piece and applied[piece]
	if not have then return end
	applied[piece] = nil
	for _, rec in have do forgetApplied(rec.inst) end
end

-- the drawing a decorator ultimately renders on (a UIGradient may sit inside a UIStroke)
local function ownerOf(st)
	while st and st.def.decorator do st = st.parentSt end
	return st
end

-- the first UICorner decorator's radius (only the first counts, like the engine)
local function firstCorner(st): UDim?
	local list = st.decorators
	if not list then return nil end
	for _, d in list do
		if d.def.name == "UICorner" then return d.props.CornerRadius end
	end
	return nil
end

-- mirror st's decorators onto one rendering piece, and drop ones that were detached
local applyDecorators
function applyDecorators(st, piece: GuiObject, kind: string)
	local list = st.decorators
	local have = applied[piece]
	if not list or #list == 0 then
		if have then
			for _, rec in have do rec.inst:Destroy() end
			forgetApplied(piece)
		end
		return
	end
	if kind == "rtri" then
		-- filled pieces already carry the UIGradient that cuts their diagonal
		if not warnedFilled[st] then
			warnedFilled[st] = true
			warn(("[Drawing] UIStroke/UICorner/UIGradient don't apply to the filled pieces of Drawing.%s"):format(st.def.name))
		end
		return
	end
	if not have then
		have = {}
		applied[piece] = have
	end
	for d, rec in have do
		if d.parentSt ~= st or not d.alive then
			forgetApplied(rec.inst)
			rec.inst:Destroy()
			have[d] = nil
		end
	end
	for _, d in list do
		-- Squares and Images have a built-in UICorner, driven by firstCorner instead
		if d.def.name == "UICorner" and (kind == "rect" or kind == "image") then continue end
		local rec = have[d]
		if not rec then
			rec = { inst = Instance.new(d.def.name), version = -1 }
			rec.inst.Parent = piece
			have[d] = rec
		end
		if rec.version ~= d.version then
			rec.version = d.version
			for key, value in d.props do
				if key ~= "Parent" then rec.inst[key] = value end
			end
		end
		-- a UIGradient parented to this UIStroke goes inside each mirrored stroke
		if #d.decorators > 0 or applied[rec.inst] then
			applyDecorators(d, rec.inst, "stroke")
		end
	end
end

local function forgetPieces(st)
	for _, pool in st.pools do
		for _, piece in pool.list do forgetApplied(piece) end
	end
	table.clear(st.pools)
	forgetApplied(st.viewport)
end

---------------------------------------------------------------- 2D primitives

local function segment(st, a: Vector2, b: Vector2, thickness: number, color: Color3, transparency: number, cap: boolean?)
	local d = b - a
	local len = d.Magnitude
	if cap then len += thickness end   -- square caps close the corners of outlines
	local f = acquire(st, "line")
	f.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
	f.Size = UDim2.fromOffset(len, thickness)
	f.Rotation = math.deg(math.atan2(d.Y, d.X))
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency
end

-- right triangle with the right angle at `d` and legs d->p, d->q
local function rightTriangle(st, d: Vector2, p: Vector2, q: Vector2, color: Color3, transparency: number)
	local lp, lq = (p - d).Magnitude, (q - d).Magnitude
	if lp < 1e-3 or lq < 1e-3 then return end
	local u, v = (p - d) / lp, (q - d) / lq
	-- the frame's local y axis is its x axis turned 90° clockwise; swap legs if v is the other way
	if Vector2.new(-u.Y, u.X):Dot(v) < 0 then
		u, v, lp, lq = v, u, lq, lp
	end
	local f = acquire(st, "rtri")
	local center = d + (u * lp + v * lq) / 2
	f.Position = UDim2.fromOffset(center.X, center.Y)
	-- grow each piece by SEAM_OVERLAP so anti-aliased edges of neighbouring pieces overlap
	local w, h = lp + SEAM_OVERLAP, lq + SEAM_OVERLAP
	f.Size = UDim2.fromOffset(w, h)
	f.Rotation = math.deg(math.atan2(u.Y, u.X))
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency
	-- UIGradient rotation is in pixels, so this angle puts the cut exactly on the diagonal
	local g = sub[f].gradient
	g.Rotation = math.deg(math.atan2(w, h))
	-- push the cut HYP_OVERLAP px outward along the gradient direction (Offset is in size units)
	local n = Vector2.new(h, w).Unit
	g.Offset = Vector2.new(n.X * HYP_OVERLAP / w, n.Y * HYP_OVERLAP / h)
end

-- any triangle = two right triangles split at the foot of the altitude onto the longest edge
local function fillTriangle(st, a: Vector2, b: Vector2, c: Vector2, color: Color3, transparency: number)
	local ab, bc, ca = (b - a).Magnitude, (c - b).Magnitude, (a - c).Magnitude
	if ab >= bc and ab >= ca then
		a, b, c = c, a, b
	elseif ca >= ab and ca >= bc then
		a, b, c = b, c, a
	end
	-- base is b->c (longest edge), apex is a
	local base = c - b
	local len = base.Magnitude
	if len < 1e-3 then return end
	local dir = base / len
	local foot = b + dir * (a - b):Dot(dir)
	if (a - foot).Magnitude < 1e-3 then return end
	rightTriangle(st, foot, b, a, color, transparency)
	rightTriangle(st, foot, c, a, color, transparency)
end

-- per-object scratch list for polygon points, reused across renders
local function scratchPoints(st): { Vector2 }
	local t = st.points
	if t then
		table.clear(t)
	else
		t = {}
		st.points = t
	end
	return t
end

local function polygon(st, points: { Vector2 }, filled: boolean, thickness: number, color: Color3, transparency: number)
	if filled then
		for i = 2, #points - 1 do
			fillTriangle(st, points[1], points[i], points[i + 1], color, transparency)
		end
	else
		for i = 1, #points do
			segment(st, points[i], points[i % #points + 1], thickness, color, transparency, true)
		end
	end
end

-- project a world-space segment to the screen, clipping it at the camera's near plane so
-- edges that pass behind the camera still point the right way (nil when fully behind)
local NEAR = 0.1
local function projectSegment(camera: Camera, a: Vector3, b: Vector3): (Vector2?, Vector2?)
	local camCF = camera.CFrame
	local la, lb = camCF:PointToObjectSpace(a), camCF:PointToObjectSpace(b)
	local aIn, bIn = la.Z < -NEAR, lb.Z < -NEAR
	if not aIn and not bIn then return nil, nil end
	if not (aIn and bIn) then
		local t = (-NEAR - la.Z) / (lb.Z - la.Z)
		local clipped = camCF:PointToWorldSpace(la:Lerp(lb, t))
		if aIn then b = clipped else a = clipped end
	end
	local sa, sb = camera:WorldToViewportPoint(a), camera:WorldToViewportPoint(b)
	return Vector2.new(sa.X, sa.Y), Vector2.new(sb.X, sb.Y)
end

-- axis-aligned rectangle (optionally rounded); outlines are centred on the edge
local function rect(st, pos: Vector2, size: Vector2, filled: boolean, thickness: number, color: Color3, transparency: number, corner: UDim, name: string)
	local f = acquire(st, "rect")
	local parts = sub[f]
	if parts.name ~= name then
		f.Name = name
		parts.name = name
	end
	if parts.cornerValue ~= corner then
		parts.cornerValue = corner
		parts.corner.CornerRadius = corner
		-- miter joins square off rounded corners, so round shapes need round joins
		parts.stroke.LineJoinMode = if corner == UDIM_ZERO then Enum.LineJoinMode.Miter else Enum.LineJoinMode.Round
	end
	-- normalise negative sizes
	local x0, y0 = math.min(pos.X, pos.X + size.X), math.min(pos.Y, pos.Y + size.Y)
	local w, h = math.abs(size.X), math.abs(size.Y)
	f.BackgroundColor3 = color
	if filled then
		f.Position = UDim2.fromOffset(x0, y0)
		f.Size = UDim2.fromOffset(w, h)
		f.BackgroundTransparency = transparency
		parts.stroke.Enabled = false
	else
		local half = thickness / 2
		f.Position = UDim2.fromOffset(x0 + half, y0 + half)
		f.Size = UDim2.fromOffset(math.max(w - thickness, 0), math.max(h - thickness, 0))
		f.BackgroundTransparency = 1
		parts.stroke.Enabled = true
		parts.stroke.Color = color
		parts.stroke.Thickness = thickness
		parts.stroke.Transparency = transparency
	end
end

local warnedRawImage = false
local function resolveImage(data: any): string
	if typeof(data) == "number" then
		return "rbxassetid://" .. data
	end
	if data == "" or data:match("^rbx") or data:match("^https?://") then
		return data
	end
	if data:match("^%d+$") then
		return "rbxassetid://" .. data
	end
	if not warnedRawImage then
		warnedRawImage = true
		warn("Drawing.Image: raw image bytes are not supported; pass an asset id instead")
	end
	return ""
end

local function fontFace(font: any): Font
	if typeof(font) == "Font" then return font end
	if typeof(font) == "EnumItem" then return Font.fromEnum(font) end
	return FONT_FACES[font] or FONT_FACES[0]
end

---------------------------------------------------------------- clones (Highlight + Mesh)
-- Both types render a posed clone of their adornee. Mesh is adapted from PolyRenderer
-- (MIT, @svyixiu, https://github.com/svyixiu/PolyRenderer).

-- temporarily make everything Archivable so the clone is complete; returns what to restore
local function forceArchivable(root: Instance): { Instance }
	local changed = {}
	if not root.Archivable then
		root.Archivable = true
		table.insert(changed, root)
	end
	for _, d in root:GetDescendants() do
		if not d.Archivable then
			d.Archivable = true
			table.insert(changed, d)
		end
	end
	return changed
end

-- walk source and clone side by side (Clone keeps child order)
local function pairParts(src: Instance, cln: Instance, srcParts: { BasePart }, clnParts: { BasePart })
	if src:IsA("BasePart") and cln:IsA("BasePart") then
		table.insert(srcParts, src :: BasePart)
		table.insert(clnParts, cln :: BasePart)
	end
	local a, b = src:GetChildren(), cln:GetChildren()
	for i = 1, math.min(#a, #b) do
		if a[i].ClassName == b[i].ClassName and a[i].Name == b[i].Name then
			pairParts(a[i], b[i], srcParts, clnParts)
		end
	end
end

local function isAny(inst: Instance, classes: { string }): boolean
	for _, className in classes do
		if inst:IsA(className) then return true end
	end
	return false
end

local function configureHumanoid(humanoid: Humanoid)
	humanoid.EvaluateStateMachine = false
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.AutomaticScalingEnabled = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
end

local function anchorParts(model: Instance, transparencyModifier: number?)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.CastShadow = false
			d.Massless = true
			if transparencyModifier then d.LocalTransparencyModifier = transparencyModifier end
		end
	end
end

-- Highlight: geometry only, hidden with LocalTransparencyModifier, posed in the camera folder
local HIGHLIGHT_PROFILE = {
	strip = {
		"LuaSourceContainer", "Humanoid", "AnimationController", "JointInstance", "WeldConstraint",
		"Constraint", "BodyMover", "Sound", "ForceField", "ParticleEmitter", "Trail", "Beam", "Light",
		"Fire", "Smoke", "Sparkles", "LayerCollector", "ProximityPrompt", "ClickDetector", "Explosion",
	},
	prepare = function(model: Model)
		anchorParts(model, CLONE_TRANSPARENCY)
		for _, d in model:GetDescendants() do
			if d:IsA("Decal") then d.Transparency = 1 end
		end
		-- unwrap accessories into plain parts, otherwise the Humanoid below re-attaches them
		-- with fresh AccessoryWelds
		for _, accessory in model:GetDescendants() do
			if accessory:IsA("Accoutrement") then
				for _, child in accessory:GetChildren() do
					if child:IsA("BasePart") then child.Parent = model end
				end
				accessory:Destroy()
			end
		end
		-- Highlights skip parts hidden by LocalTransparencyModifier unless their model has a
		-- Humanoid, so the clone gets a fresh inert one (no state machine, no neck, no name tag)
		local humanoid = Instance.new("Humanoid")
		configureHumanoid(humanoid)
		humanoid.Parent = model
	end,
	parent = function(_st) return worldFolder() end,
	bulkMove = true,
}

-- Mesh: a visible copy (clothing, accessories, joints kept) rendered inside a ViewportFrame
local MESH_PROFILE = {
	strip = {
		"LuaSourceContainer", "Animator", "Sound", "ForceField", "ParticleEmitter", "Trail", "Beam",
		"Light", "Fire", "Smoke", "Sparkles", "LayerCollector", "ProximityPrompt", "ClickDetector",
		"Explosion", "BodyMover", "Constraint",
	},
	prepare = function(model: Model)
		anchorParts(model, nil)
		for _, d in model:GetDescendants() do
			if d:IsA("Humanoid") then configureHumanoid(d) end
		end
	end,
	parent = function(st) return st.viewport end,
	bulkMove = false,             -- BulkMoveTo only works on parts in the workspace
	mirrorTransparency = true,
}

local function teardownClone(st)
	if st.watch then
		for _, conn in st.watch do conn:Disconnect() end
	end
	if st.clone then st.clone:Destroy() end
	st.watch, st.clone, st.source, st.srcParts, st.clnParts, st.cframes, st.lastT = nil, nil, nil, nil, nil, nil, nil
end

local stats = { builds = 0 }

local function buildClone(st, target: Instance, profile)
	teardownClone(st)
	st.source = target
	stats.builds += 1

	local changed = forceArchivable(target)
	local ok, copy = pcall(target.Clone, target)
	local srcParts, clnParts = {}, {}
	if ok and copy then pairParts(target, copy, srcParts, clnParts) end
	for _, inst in changed do
		pcall(function() inst.Archivable = false end)
	end
	if not (ok and copy) then return end

	local model = copy
	if target:IsA("BasePart") then
		model = Instance.new("Model")
		copy.Parent = model
	end
	for _, d in model:GetDescendants() do
		if isAny(d, profile.strip) then d:Destroy() end
	end
	profile.prepare(model)

	-- keep only pairs whose copy survived the strip
	local keptSrc, keptCln = {}, {}
	for i, part in clnParts do
		if part:IsDescendantOf(model) then
			table.insert(keptSrc, srcParts[i])
			table.insert(keptCln, part)
		end
	end

	model.Name = randomName()
	model.Parent = profile.parent(st)
	st.clone, st.srcParts, st.clnParts = model, keptSrc, keptCln
	st.cframes, st.lastT = {}, {}   -- last written values; empty so the first sync writes all

	-- rebuild when parts are added to / removed from the adornee (tools, accessories, limbs)
	local function onChange(d: Instance)
		if d:IsA("BasePart") then st.rebuild = true end
	end
	st.watch = { target.DescendantAdded:Connect(onChange), target.DescendantRemoving:Connect(onChange) }
end

-- copy the adornee's pose (and Transparency for Mesh), writing only what changed so an idle
-- adornee costs no instance writes (and a Mesh's ViewportFrame doesn't re-render)
local function syncClone(st, profile)
	local src, cln, cframes = st.srcParts, st.clnParts, st.cframes
	local bulk = profile.bulkMove
	local moved = false
	for i, part in src do
		local cf = part.CFrame
		if cf ~= cframes[i] then
			cframes[i] = cf
			moved = true
			if not bulk then cln[i].CFrame = cf end
		end
	end
	if bulk and moved then
		workspace:BulkMoveTo(cln, cframes, Enum.BulkMoveMode.FireCFrameChanged)
	end
	if profile.mirrorTransparency and st.props.MirrorTransparency then
		local lastT = st.lastT
		for i, part in src do
			local t = part.Transparency
			if t ~= lastT[i] then
				lastT[i] = t
				cln[i].Transparency = t
			end
		end
	end
end

local function adorneeTarget(adornee: Instance?): Instance?
	if adornee and adornee:IsA("Player") then return adornee.Character end
	return adornee
end

-- per tick while active: follow the adornee, (re)build the clone if needed, copy its pose.
-- Returns true when the clone is live and posed this tick.
local function followAdornee(st, profile): boolean
	local target = adorneeTarget(st.props.Adornee)
	if not (target and (target:IsA("Model") or target:IsA("BasePart")) and target:IsDescendantOf(workspace)) then
		if st.clone or st.source then teardownClone(st) end
		return false
	end
	-- a new target builds at once; a lost clone or part changes rebuild at most every
	-- REBUILD_COOLDOWN, so adornees that churn parts every frame can't force a clone per frame
	local lost = st.clone == nil or st.clone.Parent ~= profile.parent(st)
	local now = os.clock()
	if target ~= st.source or ((lost or st.rebuild) and now - st.builtAt >= REBUILD_COOLDOWN) then
		st.rebuild = false
		st.builtAt = now
		buildClone(st, target, profile)
	end
	if st.clone == nil or st.clone.Parent ~= profile.parent(st) then return false end
	syncClone(st, profile)
	return true
end

---------------------------------------------------------------- Highlight instance

local enabledHighlights = 0
local warnedHighlightLimit = false

local function newHighlightInstance(): Highlight
	local hl = Instance.new("Highlight")
	hl.Name = randomName()
	hl.Enabled = false
	hl.Parent = protectedFolder()
	return hl
end

local function applyHighlightAppearance(hl: Highlight, p)
	hl.DepthMode = p.DepthMode
	hl.FillColor = p.FillColor
	hl.FillTransparency = p.FillTransparency
	hl.OutlineColor = p.OutlineColor
	hl.OutlineTransparency = p.OutlineTransparency
end

local function setHighlightEnabled(st, on: boolean)
	if (st.hlOn == true) == on then return end   -- hlOn starts nil (= off)
	st.hlOn = on
	st.hl.Enabled = on
	enabledHighlights += if on then 1 else -1
	if on and enabledHighlights > HIGHLIGHT_LIMIT and not warnedHighlightLimit then
		warnedHighlightLimit = true
		warn(("[Drawing] %d Highlights are enabled; Roblox only renders %d at once"):format(enabledHighlights, HIGHLIGHT_LIMIT))
	end
end

-- the Highlight can be orphaned (its camera replaced) or destroyed from outside: reattach or replace
local function ensureHighlight(st)
	local hl = st.hl
	if hl:IsDescendantOf(game) then return end
	if pcall(function() hl.Parent = protectedFolder() end) and hl:IsDescendantOf(game) then return end
	if st.hlOn then
		enabledHighlights -= 1
		st.hlOn = false
	end
	pcall(hl.Destroy, hl)
	st.hl = newHighlightInstance()
	applyHighlightAppearance(st.hl, st.props)
end

local function stepHighlight(st)
	ensureHighlight(st)
	local posed = followAdornee(st, HIGHLIGHT_PROFILE)
	if st.hl.Adornee ~= st.clone then st.hl.Adornee = st.clone end
	setHighlightEnabled(st, posed)
end

---------------------------------------------------------------- Mesh instances

local function buildMeshFrame(st)
	local frame = newFrame(("Mesh_%d"):format(st.id))
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Mesh"
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.Parent = frame
	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	st.frame, st.viewport, st.camera = frame, viewport, camera
	st.camCF, st.camFov, st.syncAmbient, st.syncColor, st.syncDirection = nil, nil, nil, nil, nil
end

local function applyMeshAppearance(st, p)
	st.frame.Visible = p.Visible
	st.frame.ZIndex = math.floor(p.ZIndex)
	local viewport = st.viewport
	viewport.ImageColor3 = p.Color
	viewport.ImageTransparency = p.Transparency
	if not p.SyncLighting then
		viewport.Ambient = p.Ambient
		viewport.LightColor = p.LightColor
		viewport.LightDirection = p.LightDirection
		st.syncAmbient, st.syncColor, st.syncDirection = nil, nil, nil
	end
	applyDecorators(st, viewport, "viewport")
end

-- the Mesh's frame/viewport can be destroyed from outside (PlayerGui cleared): rebuild them
local function ensureMesh(st)
	if isAlive(st.frame) and st.viewport.Parent == st.frame and st.camera.Parent == st.viewport then return end
	teardownClone(st)
	pcall(st.frame.Destroy, st.frame)
	forgetPieces(st)
	buildMeshFrame(st)
	applyMeshAppearance(st, st.props)
end

-- The viewport camera mirrors the viewer's camera EVERY frame, whatever the Mesh's fps: it is
-- where you look from, not part of the drawn object. Throttling it made the copy stick to the
-- screen and snap back each tick while your camera moved, which reads as camera jitter.
-- Only written when it changes.
local function syncMeshCamera(st)
	ensureMesh(st)
	local world = workspace.CurrentCamera
	if not world then return end
	local cf, fov = world.CFrame, world.FieldOfView
	if cf ~= st.camCF then
		st.camCF = cf
		st.camera.CFrame = cf
	end
	if fov ~= st.camFov then
		st.camFov = fov
		st.camera.FieldOfView = fov
	end
end

-- pose and lighting follow the Mesh's fps tick; values are only written when they change
local function stepMesh(st)
	ensureMesh(st)
	local p = st.props
	followAdornee(st, MESH_PROFILE)
	if p.SyncLighting then
		local viewport = st.viewport
		local ambient = Lighting.OutdoorAmbient:Lerp(WHITE, 0.7)
		local color = WHITE:Lerp(Lighting.ColorShift_Top, 0.15)
		local direction = -Lighting:GetSunDirection()
		if ambient ~= st.syncAmbient then
			st.syncAmbient = ambient
			viewport.Ambient = ambient
		end
		if color ~= st.syncColor then
			st.syncColor = color
			viewport.LightColor = color
		end
		if direction ~= st.syncDirection then
			st.syncDirection = direction
			viewport.LightDirection = direction
		end
	end
end

-- GUI objects: rebuild the container Frame if it was destroyed from outside
local function ensureFrame(st)
	if isAlive(st.frame) then return end
	pcall(st.frame.Destroy, st.frame)
	forgetPieces(st)   -- the pooled parts died with the old frame
	st.frame = newFrame(("%s_%d"):format(st.def.name, st.id))
end

---------------------------------------------------------------- 3D ESP (Skeleton + Box3D)
-- The pose / box is sampled on the object's fps tick into st.samples (pairs of world points);
-- every frame the pairs are projected with the viewer's camera. Redraws happen only when the
-- sample or the camera changed.

local function bumpSample(st)
	st.sampleVersion = (st.sampleVersion or 0) + 1
end

-- A joint links a parent part to a child part. Rigs use either Motor6D (classic) or
-- AnimationConstraint (the newer avatar joints, between Attachment0 on the parent and
-- Attachment1 on the child); both are read the same way.
-- joint = { part0, part1, motor = Motor6D? , attachment = Attachment? }
local function jointPosition(joint): Vector3?
	local motor = joint.motor
	if motor then
		local part0 = motor.Part0
		return if part0 then (part0.CFrame * motor.C0).Position else nil
	end
	local attachment = joint.attachment
	return if attachment.Parent then attachment.WorldPosition else nil
end

-- bone endpoints: { joint = joint } | { center = BasePart } | { tip = BasePart, from = joint }
local function evalPoint(spec): Vector3?
	if spec.center then return spec.center.Position end
	local position = jointPosition(spec.joint or spec.from)
	if not position or spec.joint then return position end
	return spec.tip.Position * 2 - position   -- mirror the joint through the part: its far end
end

local function releaseRig(st)
	if st.rigWatch then
		for _, conn in st.rigWatch do conn:Disconnect() end
	end
	st.rigWatch, st.rig, st.rigSource = nil, nil, nil
	if st.samples and #st.samples > 0 then
		table.clear(st.samples)
		bumpSample(st)
	end
end

local function readJoint(d: Instance)
	if d:IsA("Motor6D") then
		if d.Part0 and d.Part1 then return { part0 = d.Part0, part1 = d.Part1, motor = d } end
	elseif d:IsA("AnimationConstraint") then
		local a0, a1 = d.Attachment0, d.Attachment1
		local p0, p1 = a0 and a0.Parent, a1 and a1.Parent
		if p0 and p1 and p0:IsA("BasePart") and p1:IsA("BasePart") then
			return { part0 = p0, part1 = p1, attachment = a0 }
		end
	end
	return nil
end

local function buildRig(st, target: Instance)
	releaseRig(st)
	st.rigSource = target
	st.rigBuiltAt = os.clock()
	local joints, proximal, hasChild = {}, {}, {}
	for _, d in target:GetDescendants() do
		local joint = readJoint(d)
		if joint and not proximal[joint.part1] then   -- one joint per child part
			table.insert(joints, joint)
			proximal[joint.part1] = joint
			hasChild[joint.part0] = true
		end
	end
	local bones = {}
	for _, joint in joints do
		local parentPart = joint.part0
		if parentPart.Name ~= "HumanoidRootPart" then
			local from = proximal[parentPart]
			table.insert(bones, { if from then { joint = from } else { center = parentPart }, { joint = joint } })
		end
		if not hasChild[joint.part1] then
			table.insert(bones, { { joint = joint }, { tip = joint.part1, from = joint } })
		end
	end
	st.rig = bones
	local function onChange(d: Instance)
		if d:IsA("JointInstance") or d:IsA("AnimationConstraint") or d:IsA("BasePart") then st.rigDirty = true end
	end
	st.rigWatch = { target.DescendantAdded:Connect(onChange), target.DescendantRemoving:Connect(onChange) }
end

local function stepSkeleton(st)
	local target = adorneeTarget(st.props.Adornee)
	if not (target and target:IsDescendantOf(workspace)) then
		releaseRig(st)
		return
	end
	if target ~= st.rigSource or (st.rigDirty and os.clock() - st.rigBuiltAt >= REBUILD_COOLDOWN) then
		st.rigDirty = false
		buildRig(st, target)
	end
	local samples = st.samples
	if not samples then
		samples = {}
		st.samples = samples
	end
	local changed, n = false, 0
	for _, bone in st.rig do
		local a, b = evalPoint(bone[1]), evalPoint(bone[2])
		if a and b then
			if samples[n + 1] ~= a or samples[n + 2] ~= b then
				samples[n + 1], samples[n + 2] = a, b
				changed = true
			end
			n += 2
		end
	end
	for i = #samples, n + 1, -1 do
		samples[i] = nil
		changed = true
	end
	if changed then bumpSample(st) end
end

-- corners are indexed by bits (x = 1, y = 2, z = 4) + 1; edges join corners one bit apart
local BOX_EDGES = {
	{ 1, 2 }, { 3, 4 }, { 5, 6 }, { 7, 8 },   -- along x
	{ 1, 3 }, { 2, 4 }, { 5, 7 }, { 6, 8 },   -- along y
	{ 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 },   -- along z
}

local function stepBox3D(st)
	local p = st.props
	local cf, size = nil, nil
	local target = adorneeTarget(p.Adornee)
	if target then
		if target:IsDescendantOf(workspace) then
			if target:IsA("Model") then
				-- an empty Model gives a zero-size box at the origin: treat it as nothing to draw
				local ok, boxCF, boxSize = pcall(target.GetBoundingBox, target)
				if ok and boxSize.Magnitude > 0 then cf, size = boxCF, boxSize end
			elseif target:IsA("BasePart") then
				cf, size = target.CFrame, target.Size
			end
		end
	elseif p.Size.Magnitude > 0 then
		cf, size = p.CFrame, p.Size
	end
	if cf == st.boxCF and size == st.boxSize then return end
	st.boxCF, st.boxSize = cf, size
	local samples = st.samples
	if not samples then
		samples = {}
		st.samples = samples
	end
	table.clear(samples)
	if cf then
		local half = size / 2
		local corners = st.corners or table.create(8)
		st.corners = corners
		for i = 0, 7 do
			corners[i + 1] = cf:PointToWorldSpace(Vector3.new(
				if i % 2 == 1 then half.X else -half.X,
				if i % 4 >= 2 then half.Y else -half.Y,
				if i >= 4 then half.Z else -half.Z))
		end
		for _, edge in BOX_EDGES do
			table.insert(samples, corners[edge[1]])
			table.insert(samples, corners[edge[2]])
		end
	end
	bumpSample(st)
end

-- draw st.samples as projected segments (joins get square caps)
local function drawSamples(st, p)
	local camera = workspace.CurrentCamera
	local samples = st.samples
	if not (camera and samples) then return end
	for i = 1, #samples - 1, 2 do
		local a, b = projectSegment(camera, samples[i], samples[i + 1])
		if a then segment(st, a, b, p.Thickness, p.Color, p.Transparency, true) end
	end
end

---------------------------------------------------------------- types

local function shared(extra)
	local t = { Visible = false, ZIndex = 1, Transparency = 0, Color = Color3.new(1, 1, 1), fps = 0 }
	for k, v in extra do t[k] = v end
	return table.freeze(t)
end

local TYPES = {}

TYPES.Line = {
	gui = true,
	defaults = shared({ From = Vector2.zero, To = Vector2.zero, Thickness = 1 }),
	render = function(st, p)
		segment(st, p.From, p.To, p.Thickness, p.Color, p.Transparency)
	end,
}

TYPES.Square = {
	gui = true,
	defaults = shared({ Position = Vector2.zero, Size = Vector2.zero, Thickness = 1, Filled = false }),
	render = function(st, p)
		rect(st, p.Position, p.Size, p.Filled, p.Thickness, p.Color, p.Transparency, firstCorner(st) or UDIM_ZERO, "Square")
	end,
}

TYPES.Circle = {
	gui = true,
	defaults = shared({ Position = Vector2.zero, Radius = 0, NumSides = 0, Thickness = 1, Filled = false }),
	render = function(st, p)
		local sides = math.floor(p.NumSides)
		if sides < 3 or sides >= SMOOTH_CIRCLE_SIDES then
			local r = math.abs(p.Radius)
			rect(st, p.Position - Vector2.new(r, r), Vector2.new(r * 2, r * 2), p.Filled, p.Thickness,
				p.Color, p.Transparency, UDIM_ROUND, "Circle")
		else
			local points = scratchPoints(st)
			for i = 1, sides do
				local angle = (i - 1) / sides * math.pi * 2
				points[i] = p.Position + Vector2.new(math.cos(angle), math.sin(angle)) * p.Radius
			end
			polygon(st, points, p.Filled, p.Thickness, p.Color, p.Transparency)
		end
	end,
}

TYPES.Triangle = {
	gui = true,
	defaults = shared({ PointA = Vector2.zero, PointB = Vector2.zero, PointC = Vector2.zero, Thickness = 1, Filled = false }),
	render = function(st, p)
		local points = scratchPoints(st)
		points[1], points[2], points[3] = p.PointA, p.PointB, p.PointC
		polygon(st, points, p.Filled, p.Thickness, p.Color, p.Transparency)
	end,
}

TYPES.Quad = {
	gui = true,
	defaults = shared({
		PointA = Vector2.zero, PointB = Vector2.zero, PointC = Vector2.zero, PointD = Vector2.zero,
		Thickness = 1, Filled = false,
	}),
	render = function(st, p)
		local points = scratchPoints(st)
		points[1], points[2], points[3], points[4] = p.PointA, p.PointB, p.PointC, p.PointD
		polygon(st, points, p.Filled, p.Thickness, p.Color, p.Transparency)
	end,
}

TYPES.Text = {
	gui = true,
	defaults = shared({
		Text = "", Font = Drawing.Fonts.UI, Size = 13, Position = Vector2.zero,
		Center = false, Outline = false, OutlineColor = Color3.new(0, 0, 0),
	}),
	accepts = { Font = { EnumItem = true, Font = true } },
	render = function(st, p)
		local l = acquire(st, "text")
		l.Text = p.Text
		l.FontFace = fontFace(p.Font)
		l.TextSize = p.Size
		l.TextColor3 = p.Color
		l.TextTransparency = p.Transparency
		l.TextStrokeColor3 = p.OutlineColor
		l.TextStrokeTransparency = if p.Outline then p.Transparency else 1
		l.AnchorPoint = Vector2.new(if p.Center then 0.5 else 0, 0)
		l.Position = UDim2.fromOffset(p.Position.X, p.Position.Y)
	end,
	getters = {
		TextBounds = function(st)
			local pool = st.pools.text
			local label = pool and pool.list[1]
			return if label then label.TextBounds else Vector2.zero
		end,
	},
}

TYPES.Image = {
	gui = true,
	defaults = shared({ Data = "", Size = Vector2.zero, Position = Vector2.zero, Rounding = 0 }),
	accepts = { Data = { number = true } },
	render = function(st, p)
		local i = acquire(st, "image")
		i.Image = resolveImage(p.Data)
		i.ImageColor3 = p.Color
		i.ImageTransparency = p.Transparency
		i.Position = UDim2.fromOffset(p.Position.X, p.Position.Y)
		i.Size = UDim2.fromOffset(p.Size.X, p.Size.Y)
		sub[i].corner.CornerRadius = firstCorner(st) or UDim.new(0, p.Rounding)
	end,
}

TYPES.Highlight = {
	gui = false,
	defaults = table.freeze({
		Enabled = false,
		DepthMode = Enum.HighlightDepthMode.AlwaysOnTop,
		FillColor = Color3.fromRGB(255, 0, 0),
		FillTransparency = 0.5,
		OutlineColor = Color3.new(1, 1, 1),
		OutlineTransparency = 0,
		fps = 0,
	}),
	accepts = { Adornee = { Instance = true, ["nil"] = true } },
	enums = { DepthMode = Enum.HighlightDepthMode },
	aliases = { Visible = "Enabled" },
	create = function(st)
		st.hl = newHighlightInstance()
	end,
	ensure = ensureHighlight,
	render = function(st, p)
		applyHighlightAppearance(st.hl, p)
		if not p.Enabled then
			-- inactive: stop stepping (see needsFrame) and release the clone
			setHighlightEnabled(st, false)
			teardownClone(st)
			st.hl.Adornee = nil
		end
	end,
	active = function(p) return p.Enabled end,
	step = stepHighlight,
	destroy = function(st)
		setHighlightEnabled(st, false)
		teardownClone(st)
		st.hl:Destroy()
	end,
	primary = function(st) return st.hl end,
}

TYPES.Mesh = {
	gui = false,
	decoratable = true,
	defaults = shared({
		MirrorTransparency = true,
		SyncLighting = false,
		Ambient = Color3.fromRGB(200, 200, 200),
		LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-1, -1, -1),
	}),
	accepts = { Adornee = { Instance = true, ["nil"] = true } },
	create = buildMeshFrame,
	ensure = ensureMesh,
	render = function(st, p)
		applyMeshAppearance(st, p)
		if not p.Visible then teardownClone(st) end   -- inactive: release the clone
	end,
	active = function(p) return p.Visible end,
	step = stepMesh,              -- on the fps tick: pose, transparency, lighting
	everyFrame = syncMeshCamera,  -- every frame while visible: the viewer's camera
	destroy = function(st)
		teardownClone(st)
		st.frame:Destroy()
	end,
	primary = function(st) return st.viewport end,
}

TYPES.Skeleton = {
	gui = true,
	defaults = shared({ Thickness = 1.5 }),
	accepts = { Adornee = { Instance = true, ["nil"] = true } },
	render = function(st, p)
		if not p.Visible then
			releaseRig(st)   -- inactive: drop the rig and its watchers
			return
		end
		drawSamples(st, p)
	end,
	active = function(p) return p.Visible end,
	step = stepSkeleton,   -- on the fps tick: sample the joints
	-- everyFrame (project with the viewer's camera) is assigned once render() exists
}

TYPES.Box3D = {
	gui = true,
	defaults = shared({ Thickness = 1.5, CFrame = CFrame.identity, Size = Vector3.zero }),
	accepts = { Adornee = { Instance = true, ["nil"] = true } },
	render = function(st, p)
		if not p.Visible then
			st.boxCF, st.boxSize = nil, nil   -- resample when shown again
			return
		end
		drawSamples(st, p)
	end,
	active = function(p) return p.Visible end,
	step = stepBox3D,
}

local DECORATOR_PARENT = { userdata = true, ["nil"] = true }

TYPES.UIStroke = {
	decorator = true,
	defaults = table.freeze({
		Color = Color3.new(0, 0, 0),
		Thickness = 1,
		Transparency = 0,
		LineJoinMode = Enum.LineJoinMode.Round,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
		Enabled = true,
	}),
	accepts = { Parent = DECORATOR_PARENT },
	enums = { LineJoinMode = Enum.LineJoinMode, ApplyStrokeMode = Enum.ApplyStrokeMode },
	primary = function() return nil end,
}

TYPES.UICorner = {
	decorator = true,
	defaults = table.freeze({ CornerRadius = UDim.new(0, 8) }),
	accepts = { Parent = DECORATOR_PARENT },
	primary = function() return nil end,
}

TYPES.UIGradient = {
	decorator = true,
	defaults = table.freeze({
		Color = ColorSequence.new(Color3.new(1, 1, 1)),
		Transparency = NumberSequence.new(0),
		Rotation = 0,
		Offset = Vector2.zero,
		Enabled = true,
	}),
	accepts = { Parent = DECORATOR_PARENT, Color = { Color3 = true }, Transparency = { number = true } },
	primary = function() return nil end,
}

for name, def in TYPES do
	def.name = name
	if def.gui then def.ensure = ensureFrame end
end
TYPES.Box = TYPES.Square

---------------------------------------------------------------- property schema

local function isMember(def, key): boolean
	return def.defaults[key] ~= nil or (def.accepts ~= nil and def.accepts[key] ~= nil)
end

local function editDistance(a: string, b: string): number
	local prev = table.create(#b + 1)
	for j = 0, #b do prev[j + 1] = j end
	for i = 1, #a do
		local cur = { i }
		for j = 1, #b do
			local cost = if a:byte(i) == b:byte(j) then 0 else 1
			cur[j + 1] = math.min(prev[j + 1] + 1, cur[j] + 1, prev[j] + cost)
		end
		prev = cur
	end
	return prev[#b + 1]
end

local function unknownMember(def, key): string
	local message = ("%s is not a valid member of Drawing.%s"):format(tostring(key), def.name)
	if type(key) ~= "string" then return message end
	local names = {}
	for k in def.defaults do table.insert(names, k) end
	for k in def.accepts or {} do table.insert(names, k) end
	for k in def.aliases or {} do table.insert(names, k) end
	local best, bestDistance = nil, 3
	for _, name in names do
		local d = editDistance(key:lower(), name:lower())
		if d < bestDistance then best, bestDistance = name, d end
	end
	return if best then message .. (" (did you mean %s?)"):format(best) else message
end

local function expectedType(def, key): string
	local list = {}
	if def.defaults[key] ~= nil then table.insert(list, typeof(def.defaults[key])) end
	for t in (def.accepts and def.accepts[key]) or {} do table.insert(list, t) end
	table.sort(list)
	return table.concat(list, " or ")
end

---------------------------------------------------------------- objects + scheduling

local states = setmetatable({}, { __mode = "k" })   -- proxy -> state (every object ever made)
local live = {}                                       -- proxy -> state (not yet destroyed)

local function render(st)
	st.dirty = false
	st.rendered = true
	local def, p = st.def, st.props
	def.ensure(st)
	if not def.gui then
		def.render(st, p)
		return
	end
	st.frame.Visible = p.Visible
	st.frame.ZIndex = math.floor(p.ZIndex)
	for _, pool in st.pools do pool.n = 0 end
	def.render(st, p)
	local decorators = st.decorators
	if #decorators > 0 or st.hadDecorators then
		for kind, pool in st.pools do
			for i = 1, pool.n do applyDecorators(st, pool.list[i], kind) end
		end
		st.hadDecorators = #decorators > 0
	end
	for _, pool in st.pools do
		for i = pool.n + 1, #pool.list do pool.list[i].Visible = false end
	end
end

-- Skeleton / Box3D: project the latest sample with the viewer's camera every frame, but only
-- redraw when the sample or the camera actually changed
local function redraw3D(st)
	local camera = workspace.CurrentCamera
	if not camera then return end
	local cf, size, fov = camera.CFrame, camera.ViewportSize, camera.FieldOfView
	if st.sampleVersion == st.drawnVersion and cf == st.viewCF and size == st.viewSize and fov == st.viewFov then return end
	st.drawnVersion, st.viewCF, st.viewSize, st.viewFov = st.sampleVersion, cf, size, fov
	render(st)
end
TYPES.Skeleton.everyFrame = redraw3D
TYPES.Box3D.everyFrame = redraw3D

-- one warning per object, and the error never stops other objects from updating
local function report(st, phase: string, err: any)
	if st.faulted then return end
	st.faulted = true
	warn(("[Drawing] %s %s failed (further errors from this object are silenced): %s"):format(st.def.name, phase, tostring(err)))
end

local function safeRender(st)
	local ok, err = pcall(render, st)
	if not ok then report(st, "render", err) end
end

local function safeStep(st)
	local ok, err = pcall(st.def.step, st)
	if not ok then
		report(st, "update", err)
		pcall(teardownClone, st)   -- start from a fresh clone next time
	end
end

-- fps == 0: dirty objects are rebuilt at the end of the current resumption point (same frame)
local deferQueue = {}
local flushScheduled = false

local function flush()
	flushScheduled = false
	for st in deferQueue do
		deferQueue[st] = nil
		if st.alive and st.dirty and st.props.fps <= 0 then safeRender(st) end
	end
end

-- The frame loop only holds objects that need it right now: a pending fps>0 render, or an
-- active Highlight/Mesh. It disconnects itself when that set is empty.
local timed = {}
local loop: RBXScriptConnection? = nil

local function needsFrame(st): boolean
	if not st.alive then return false end
	if st.dirty and st.props.fps > 0 then return true end
	return st.def.step ~= nil and st.def.active(st.props)
end

local function onFrame()
	local now = os.clock()
	-- invariant: nothing below adds keys to `timed` (only schedule() does, never from here)
	for st in timed do
		local fps = st.props.fps
		local due = true
		if fps > 0 then
			local interval = 1 / fps
			local elapsed = now - st.lastTick
			if elapsed < interval then
				due = false
			else
				-- keep a steady cadence, but don't try to catch up after a long gap
				st.lastTick = if elapsed < interval * 2 then st.lastTick + interval else now
				if st.dirty then safeRender(st) end
			end
		end
		local def = st.def
		if st.alive and def.step and def.active(st.props) then
			if due then safeStep(st) end
			if def.everyFrame then
				local ok, err = pcall(def.everyFrame, st)
				if not ok then report(st, "frame update", err) end
			end
		end
		if not needsFrame(st) then timed[st] = nil end
	end
	if next(timed) == nil and loop then
		loop:Disconnect()
		loop = nil
	end
end

local function schedule(st)
	if needsFrame(st) then
		timed[st] = true
		if not loop then loop = RunService.RenderStepped:Connect(onFrame) end
	end
end

local function markDirty(st)
	st.dirty = true
	if st.props.fps <= 0 then
		deferQueue[st] = true
		if not flushScheduled then
			flushScheduled = true
			task.defer(flush)
		end
	end
	schedule(st)
end

local destroy
function destroy(proxy)
	local st = states[proxy]
	if not st or not st.alive then return end
	st.alive = false
	deferQueue[st] = nil
	timed[st] = nil
	live[proxy] = nil
	st.proxy = nil
	if st.def.decorator then
		for _, d in table.clone(st.decorators) do   -- e.g. a UIGradient inside this UIStroke
			if d.proxy then destroy(d.proxy) end
		end
		local parent = st.parentSt
		st.parentSt = nil
		st.props.Parent = nil   -- like a destroyed Roblox instance; also breaks a reference cycle
		if parent then
			local index = table.find(parent.decorators, st)
			if index then table.remove(parent.decorators, index) end
			local owner = ownerOf(parent)
			if owner and owner.alive then markDirty(owner) end
		end
		return
	end
	-- like Roblox children, a drawing's decorators are destroyed with it
	if st.decorators then
		for _, d in table.clone(st.decorators) do
			if d.proxy then destroy(d.proxy) end
		end
	end
	if st.def.destroy then
		pcall(st.def.destroy, st)
	else
		pcall(st.frame.Destroy, st.frame)
	end
	forgetPieces(st)   -- drop mirror records + pool references so nothing keeps this object alive
end

local METHODS = {
	Destroy = destroy,
	Remove = destroy,
}

-- the instance that renders the object: the single part for one-piece shapes, else the container
local function primaryInstance(st): Instance?
	if st.def.primary then return st.def.primary(st) end
	if not st.rendered then safeRender(st) end
	local only, count = nil, 0
	for _, pool in st.pools do
		for i = 1, pool.n do
			only = pool.list[i]
			count += 1
		end
	end
	return if count == 1 then only else st.frame
end

local meta = {}
meta.__metatable = "The metatable is locked"

function meta.__index(proxy, key)
	local st = states[proxy]
	local def = st.def
	if key == "__OBJECT_EXISTS" then return st.alive end
	local method = METHODS[key]
	if method then return method end
	key = (def.aliases and def.aliases[key]) or key
	local getter = def.getters and def.getters[key]
	if getter then
		if st.dirty and st.alive then safeRender(st) end
		return getter(st)
	end
	if not isMember(def, key) then error(unknownMember(def, key), 2) end
	return st.props[key]
end

function meta.__newindex(proxy, key, value)
	local st = states[proxy]
	local def = st.def
	key = (def.aliases and def.aliases[key]) or key
	if def.decorator and key == "Parent" then
		local target = value ~= nil and states[value] or nil
		if value ~= nil and not (target and target.alive) then
			error(("Drawing.%s.Parent expects a live Drawing object or nil"):format(def.name), 2)
		end
		local intoStroke = target ~= nil and def.name == "UIGradient" and target.def.name == "UIStroke"
		if target and not (target.def.gui or target.def.decoratable or intoStroke) then
			error(("Drawing.%s can't be parented to Drawing.%s"):format(def.name, target.def.name), 2)
		end
		if not st.alive or st.parentSt == target then return end
		local old = st.parentSt
		if old then
			local index = table.find(old.decorators, st)
			if index then table.remove(old.decorators, index) end
			local oldOwner = ownerOf(old)
			if oldOwner and oldOwner.alive then markDirty(oldOwner) end
		end
		st.parentSt = target
		st.props.Parent = value
		if target then
			table.insert(target.decorators, st)
			local owner = ownerOf(target)
			if owner and owner.alive then markDirty(owner) end
		end
		return
	end
	if key == "__OBJECT_EXISTS" or (def.getters and def.getters[key]) then
		error(("Drawing.%s.%s is read-only"):format(def.name, tostring(key)), 2)
	end
	if not isMember(def, key) then error(unknownMember(def, key), 2) end

	local got = typeof(value)
	local default = def.defaults[key]
	local accepts = def.accepts and def.accepts[key]
	if not ((default ~= nil and got == typeof(default)) or (accepts and accepts[got])) then
		error(("Drawing.%s.%s expects %s, got %s"):format(def.name, key, expectedType(def, key), got), 2)
	end
	local enum = def.enums and def.enums[key]
	if enum and value.EnumType ~= enum then
		error(("Drawing.%s.%s expects Enum.%s, got %s"):format(def.name, key, tostring(enum), tostring(value)), 2)
	end
	if key == "fps" and (value < 0 or value ~= value or value == math.huge) then
		error(("Drawing.%s.fps must be a finite number >= 0, got %s"):format(def.name, tostring(value)), 2)
	end

	if def.name == "UIGradient" then   -- conveniences: a single colour / transparency
		if key == "Color" and got == "Color3" then value = ColorSequence.new(value) end
		if key == "Transparency" and got == "number" then value = NumberSequence.new(value) end
	end

	if not st.alive or st.props[key] == value then return end
	st.props[key] = value
	if def.decorator then
		-- decorators render through their parent: re-mirror on its next render/tick
		st.version += 1
		local owner = ownerOf(st.parentSt)
		if owner and owner.alive then markDirty(owner) end
		return
	end
	if key == "fps" then st.lastTick = -math.huge end   -- first tick happens on the next frame
	markDirty(st)
end

function meta.__tostring(proxy)
	local st = states[proxy]
	if not st.alive then return ("Drawing.%s (destroyed)"):format(st.def.name) end
	local inst = primaryInstance(st)
	return if inst then inst:GetFullName() else "Drawing." .. st.def.name
end

local nextId = 0

function Drawing.new(typeName: string, properties: { [string]: any }?)
	if not RunService:IsClient() then
		error("Drawing.new: Drawing only works on the client (require it from a LocalScript)", 2)
	end
	local def = TYPES[typeName]
	if not def then
		error(("Drawing.new: invalid drawing type %q (expected Line, Text, Image, Circle, Square, Quad, Triangle, Highlight, Mesh, Skeleton, Box3D, UIStroke, UICorner or UIGradient)")
			:format(tostring(typeName)), 2)
	end
	nextId += 1

	local st = {
		id = nextId,
		def = def,
		props = table.clone(def.defaults),
		pools = {},
		alive = true,
		dirty = false,
		rendered = false,
		lastTick = -math.huge,
		builtAt = 0,
		decorators = {},   -- UI decorators parented to this object
		version = 0,       -- (decorators) bumped on every property change
	}
	if def.decorator then
		-- nothing to create: a decorator is mirrored onto its parent's pieces
	elseif def.gui then
		st.frame = newFrame(("%s_%d"):format(def.name, nextId))
	else
		def.create(st)
	end

	local proxy = newproxy(true)
	local mt = getmetatable(proxy)
	for k, v in meta do mt[k] = v end
	states[proxy] = st
	live[proxy] = st
	st.proxy = proxy   -- cleared on destroy (a destroyed state must not keep its proxy alive)

	if properties then
		-- a bad property must not leave an unreachable half-made object behind
		local ok, err = pcall(function()
			for k, v in properties do proxy[k] = v end
		end)
		if not ok then
			destroy(proxy)
			-- drop the "Module:line:" prefix of the inner error; report it at the caller
			error((tostring(err):gsub("^[^\n]-:%d+: ", "")), 2)
		end
	end
	if not def.decorator then markDirty(st) end
	return proxy
end

---------------------------------------------------------------- sUNC functions

function Drawing.isrenderobj(value: any): boolean
	return type(value) == "userdata" and states[value] ~= nil
end

function Drawing.getrenderproperty(drawing: any, property: string): any
	assert(Drawing.isrenderobj(drawing), "getrenderproperty: argument #1 must be a Drawing object")
	return drawing[property]
end

function Drawing.setrenderproperty(drawing: any, property: string, value: any)
	assert(Drawing.isrenderobj(drawing), "setrenderproperty: argument #1 must be a Drawing object")
	drawing[property] = value
end

-- health snapshot: how much the library is holding and doing right now
function Drawing.getstats()
	local liveCount, activeCount = 0, 0
	for _ in live do liveCount += 1 end
	for _ in timed do activeCount += 1 end
	return {
		live = liveCount,               -- objects not yet destroyed
		active = activeCount,           -- objects the frame loop is servicing
		loopRunning = loop ~= nil,      -- whether the RenderStepped loop is connected
		cloneBuilds = stats.builds,     -- total clone builds so far (Highlight + Mesh)
		enabledHighlights = enabledHighlights,
	}
end

function Drawing.cleardrawcache()
	for proxy in live do destroy(proxy) end
end

return Drawing
