-- License: MIT
-- Copyright: @svyixiu (https://github.com/svyixiu/PolyRenderer)

local RunService = game:GetService("RunService")
local IS_STUDIO = RunService:IsStudio()

local function getExecutorFunction(name)
	local ok, result = pcall(function()
		local env = (getgenv and getgenv()) or getfenv(0)
		return env[name]
	end)
	if ok and type(result) == "function" then
		return result
	end
	return nil
end

local cloneref = if IS_STUDIO then nil else getExecutorFunction("cloneref")
local gethui = if IS_STUDIO then nil else getExecutorFunction("gethui")

local function getService(serviceName)
	local service = game:GetService(serviceName)
	if cloneref then
		local ok, cloned = pcall(cloneref, service)
		if ok and cloned then
			return cloned
		end
	end
	return service
end

local Players = getService("Players")
local Lighting = getService("Lighting")
local Workspace = getService("Workspace")
local HttpService = getService("HttpService")
local LocalPlayer = Players.LocalPlayer

local function getGuiParent()
	if not IS_STUDIO then
		if gethui then
			local ok, hiddenUi = pcall(gethui)
			if ok and hiddenUi then
				return hiddenUi
			end
		end
		local ok, coreGui = pcall(function()
			return game:GetService("CoreGui")
		end)
		if ok and coreGui then
			return coreGui
		end
	end
	return LocalPlayer:WaitForChild("PlayerGui", 9e9)
end

local PolyRenderer = {}
local rendererStates = setmetatable({}, { __mode = "k" })
local RENDER_PRIORITY = Enum.RenderPriority.Last.Value - 1
local STRIPPED_CLASSES = {
	"BaseScript", "Sound", "ParticleEmitter", "Fire", "Smoke", "Sparkles",
	"Beam", "Trail", "Light", "BillboardGui", "Explosion",
}

local function forceArchivable(instance)
	local changed = {}
	if not instance.Archivable then
		instance.Archivable = true
		table.insert(changed, instance)
	end
	for _, descendant in instance:GetDescendants() do
		if not descendant.Archivable then
			descendant.Archivable = true
			table.insert(changed, descendant)
		end
	end
	return changed
end

local function safeClone(source, allowArchiving)
	if not allowArchiving then
		if not source.Archivable then
			warn(("[PolyRenderer] %s is not Archivable and AllowArchiving is off"):format(source:GetFullName()))
			return nil
		end
		for _, descendant in source:GetDescendants() do
			if not descendant.Archivable then
				warn(("[PolyRenderer] %s is not Archivable, it will be missing from the copy"):format(descendant:GetFullName()))
			end
		end
	end
	local changed = if allowArchiving then forceArchivable(source) else {}
	local ok, clone = pcall(function()
		return source:Clone()
	end)
	for _, instance in changed do
		if instance.Parent then
			instance.Archivable = false
		end
	end
	if not ok or not clone then
		warn(("[PolyRenderer] could not clone %s"):format(source:GetFullName()))
		return nil
	end
	return clone
end

local function collectPartPairs(real, copy, pairList)
	if real:IsA("BasePart") and copy:IsA("BasePart") then
		table.insert(pairList, { real = real, copy = copy })
	end
	local realChildren, copyChildren = real:GetChildren(), copy:GetChildren()
	for i = 1, math.min(#realChildren, #copyChildren) do
		collectPartPairs(realChildren[i], copyChildren[i], pairList)
	end
end

local function createEntryHandle(entry)
	return setmetatable({}, {
		__index = function(_, key)
			if key == "Fps" then return entry.fps end
			if key == "MirrorTransparency" then return entry.mirrorTransparency end
			if key == "Source" then return entry.source end
			if key == "Clone" then return entry.clone end
			if entry.props[key] ~= nil then return entry.props[key] end
			local ok, value = pcall(function()
				return entry.clone[key]
			end)
			if ok then return value end
			return nil
		end,

		__newindex = function(_, key, value)
			if key == "Fps" then
				assert(value == nil or (type(value) == "number" and value >= 0), "Fps must be nil or a number >= 0")
				entry.fps = value
				entry.lastPose = 0
				return
			elseif key == "MirrorTransparency" then
				entry.mirrorTransparency = value and true or false
				return
			elseif key == "Source" or key == "Clone" then
				error(key .. " is read only", 2)
			end
			local ok = pcall(function()
				entry.clone[key] = value
			end)
			if not ok then
				entry.props[key] = value
			end
		end,

		__tostring = function()
			return ("PolyRenderer.Entry(%s, Fps=%s)"):format(entry.source.Name, tostring(entry.fps))
		end,
	})
end

local function applyProperties(entry, properties)
	if type(properties) ~= "table" then return end
	local handle = entry.handle
	if properties.Fps ~= nil then
		handle.Fps = properties.Fps
	end
	for key, value in properties do
		if key ~= "Fps" then
			handle[key] = value
		end
	end
end

local function cleanupEntry(entry)
	for _, connection in entry.conns do
		connection:Disconnect()
	end
	table.clear(entry.conns)
	if entry.clone then
		entry.clone:Destroy()
		entry.clone = nil
	end
	table.clear(entry.pairs)
end

local function buildCopy(state, source)
	local copy = safeClone(source, state.allowArchiving)
	if not copy then return nil end

	local partPairs = {}
	collectPartPairs(source, copy, partPairs)

	for _, descendant in copy:GetDescendants() do
		for _, className in STRIPPED_CLASSES do
			if descendant:IsA(className) then
				descendant:Destroy()
				break
			end
		end
	end

	local humanoid = copy:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.EvaluateStateMachine = false
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end

	for _, pair in partPairs do
		pair.copy.Anchored = true
		pair.copy.CanCollide = false
		pair.copy.CanQuery = false
		pair.copy.CanTouch = false
		pair.copy.CFrame = pair.real.CFrame
	end

	copy.Name = "Copy_" .. source.Name
	copy.Parent = state.viewport
	return copy, partPairs
end

local function rebuildEntry(state, entry)
	if not entry.source.Parent then return end
	local newClone, newPairs = buildCopy(state, entry.source)
	if not newClone then return end

	if entry.clone then
		state.clones[entry.clone] = nil
		entry.clone:Destroy()
	end
	entry.clone = newClone
	entry.pairs = newPairs
	state.clones[newClone] = entry
end

local function queueRebuild(state, entry)
	if entry.rebuildQueued then return end
	entry.rebuildQueued = true
	task.defer(function()
		entry.rebuildQueued = false
		if state.alive and state.entries[entry.source] then
			rebuildEntry(state, entry)
		end
	end)
end

local function findEntry(state, instance)
	if typeof(instance) ~= "Instance" then return nil end
	return state.entries[instance] or state.clones[instance]
end

local function syncPoses(entry)
	local needsRebuild = false
	local mirrorTransparency = entry.mirrorTransparency
	for _, pair in entry.pairs do
		local real, copy = pair.real, pair.copy
		if real.Parent == nil or copy.Parent == nil then
			needsRebuild = true
			continue
		end
		copy.CFrame = real.CFrame
		if mirrorTransparency and copy.Transparency ~= real.Transparency then
			copy.Transparency = real.Transparency
		end
	end
	return needsRebuild
end

local function step(state)
	local worldCamera = Workspace.CurrentCamera
	if not worldCamera then return end

	local now = os.clock()

	if state.fps <= 0 or now - state.lastStep >= 1 / state.fps then
		state.lastStep = now
		state.camera.CFrame = worldCamera.CFrame
		state.camera.FieldOfView = worldCamera.FieldOfView

		if state.syncLighting then
			local white = Color3.new(1, 1, 1)
			state.viewport.Ambient = Lighting.OutdoorAmbient:Lerp(white, 0.7)
			state.viewport.LightColor = white:Lerp(Lighting.ColorShift_Top, 0.15)
			state.viewport.LightDirection = -Lighting:GetSunDirection()
		end
	end

	for source, entry in state.entries do
		if not source.Parent then
			state.clones[entry.clone] = nil
			cleanupEntry(entry)
			state.entries[source] = nil
			continue
		end

		local fps = if entry.fps ~= nil then entry.fps else state.fps
		if fps > 0 then
			if now - entry.lastPose < 1 / fps then continue end
			entry.lastPose = now
		end

		if syncPoses(entry) and state.autoRebuild then
			queueRebuild(state, entry)
		end
	end
end

local RendererMethods = {}

function RendererMethods:Add(source, properties)
	local state = rendererStates[self]
	if not state or not state.alive then return nil end
	if typeof(source) ~= "Instance" then return nil end
	if state.entries[source] then return nil end

	local clone, partPairs = buildCopy(state, source)
	if not clone then return nil end

	local entry = {
		source = source,
		clone = clone,
		pairs = partPairs,
		fps = nil,
		mirrorTransparency = true,
		props = {},
		lastPose = 0,
		rebuildQueued = false,
		conns = {},
	}
	entry.handle = createEntryHandle(entry)

	table.insert(entry.conns, source.Destroying:Connect(function()
		self:Remove(source)
	end))
	table.insert(entry.conns, source.DescendantAdded:Connect(function()
		if state.autoRebuild then queueRebuild(state, entry) end
	end))
	table.insert(entry.conns, source.DescendantRemoving:Connect(function()
		if state.autoRebuild then queueRebuild(state, entry) end
	end))

	state.entries[source] = entry
	state.clones[clone] = entry

	applyProperties(entry, properties)
	return entry.clone
end

function RendererMethods:Edit(instance, properties)
	local state = rendererStates[self]
	if not state then return nil end
	local entry = findEntry(state, instance)
	if not entry then return nil end
	if properties ~= nil then
		applyProperties(entry, properties)
	end
	return entry.handle
end

function RendererMethods:Remove(instance)
	local state = rendererStates[self]
	if not state then return false end
	local entry = findEntry(state, instance)
	if not entry then return false end
	state.entries[entry.source] = nil
	state.clones[entry.clone] = nil
	cleanupEntry(entry)
	return true
end

function RendererMethods:RemoveAll()
	local state = rendererStates[self]
	if not state then return false end
	local removedAny = false
	for source, entry in state.entries do
		state.clones[entry.clone] = nil
		cleanupEntry(entry)
		state.entries[source] = nil
		removedAny = true
	end
	return removedAny
end

function RendererMethods:Destroy()
	local state = rendererStates[self]
	if not state or not state.alive then return end
	state.alive = false

	self:RemoveAll()
	if state.heartbeat then
		state.heartbeat:Disconnect()
		state.heartbeat = nil
	end
	pcall(function()
		RunService:UnbindFromRenderStep(state.bindName)
	end)
	state.gui:Destroy()
	rendererStates[self] = nil
end

local function generateBindName()
	local ok, guid = pcall(function()
		return HttpService:GenerateGUID(false)
	end)
	if ok and guid then
		return "PolyRenderer_" .. guid
	end
	return ("PolyRenderer_%d_%d"):format(os.time(), math.random(0, 2 ^ 30))
end

function PolyRenderer.new()
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "PolyRenderer"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Render"
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Position = UDim2.fromScale(0, 0)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(200, 200, 200)
	viewport.LightColor = Color3.fromRGB(255, 255, 255)
	viewport.Parent = screenGui

	local camera = Instance.new("Camera")
	camera.Name = "PolyCamera"
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	screenGui.Parent = getGuiParent()

	local state = {
		alive = true,
		gui = screenGui,
		viewport = viewport,
		camera = camera,
		entries = {},
		clones = {},
		props = {},
		fps = 0,
		lastStep = 0,
		autoRebuild = true,
		syncLighting = false,
		allowArchiving = true,
		bindName = generateBindName(),
	}

	local renderer = {}

	setmetatable(renderer, {
		__index = function(_, key)
			if RendererMethods[key] then return RendererMethods[key] end
			if key == "Fps" then return state.fps end
			if key == "AutoRebuild" then return state.autoRebuild end
			if key == "SyncLighting" then return state.syncLighting end
			if key == "AllowArchiving" then return state.allowArchiving end
			if key == "ViewportFrame" then return state.viewport end
			if key == "ScreenGui" then return state.gui end
			if key == "Camera" then return state.camera end
			if state.props[key] ~= nil then return state.props[key] end
			local ok, value = pcall(function()
				return state.viewport[key]
			end)
			if ok then return value end
			return nil
		end,

		__newindex = function(_, key, value)
			if key == "Fps" then
				assert(type(value) == "number" and value >= 0, "Fps must be a number >= 0")
				state.fps = value
				return
			elseif key == "AutoRebuild" then
				state.autoRebuild = value and true or false
				return
			elseif key == "SyncLighting" then
				state.syncLighting = value and true or false
				return
			elseif key == "AllowArchiving" then
				state.allowArchiving = value and true or false
				return
			end
			local ok = pcall(function()
				state.viewport[key] = value
			end)
			if not ok then
				state.props[key] = value
			end
		end,

		__tostring = function()
			local count = 0
			for _ in state.entries do count += 1 end
			return ("PolyRenderer(%d rendering, Fps=%s)"):format(count, tostring(state.fps))
		end,
	})

	rendererStates[renderer] = state

	state.heartbeat = RunService.Heartbeat:Connect(function()
		if state.alive then step(state) end
	end)
	RunService:BindToRenderStep(state.bindName, RENDER_PRIORITY, function()
		if state.alive then step(state) end
	end)

	return renderer
end

return PolyRenderer
