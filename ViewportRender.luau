-- License: MIT
-- Copyright: @svyixiu (https://github.com/svyixiu/PolyRenderer)

local _0 = game:GetService("RunService")
local _1 = _0:IsStudio()

local function _2(_30)
	local _31, _32 = pcall(function()
		local _33 = (getgenv and getgenv()) or getfenv(0)
		return _33[_30]
	end)
	if _31 and type(_32) == "function" then
		return _32
	end
	return nil
end

local _3 = if _1 then nil else _2("cloneref")
local _4 = if _1 then nil else _2("gethui")

local function _5(_34)
	local _35 = game:GetService(_34)
	if _3 then
		local _36, _37 = pcall(_3, _35)
		if _36 and _37 then
			return _37
		end
	end
	return _35
end

local _6 = _5("Players")
local _7 = _5("Lighting")
local _8 = _5("Workspace")
local _9 = _5("HttpService")
local _10 = _6.LocalPlayer

local function _11()
	if not _1 then
		if _4 then
			local _38, _39 = pcall(_4)
			if _38 and _39 then
				return _39
			end
		end
		local _40, _41 = pcall(function()
			return game:GetService("CoreGui")
		end)
		if _40 and _41 then
			return _41
		end
	end
	return _10:WaitForChild("PlayerGui", 9e9)
end

local _12 = {}
local _13 = setmetatable({}, { __mode = "k" })
local _14 = Enum.RenderPriority.Last.Value - 1
local _15 = {
	"BaseScript", "Sound", "ParticleEmitter", "Fire", "Smoke", "Sparkles",
	"Beam", "Trail", "Light", "BillboardGui", "Explosion",
}

local function _16(_42)
	local _43 = {}
	if not _42.Archivable then
		_42.Archivable = true
		table.insert(_43, _42)
	end
	for _, _44 in _42:GetDescendants() do
		if not _44.Archivable then
			_44.Archivable = true
			table.insert(_43, _44)
		end
	end
	return _43
end

local function _17(_45, _46)
	if not _46 then
		if not _45.Archivable then
			warn(("[PolyRenderer] %s is not Archivable and AllowArchiving is off"):format(_45:GetFullName()))
			return nil
		end
		for _, _47 in _45:GetDescendants() do
			if not _47.Archivable then
				warn(("[PolyRenderer] %s is not Archivable, it will be missing from the copy"):format(_47:GetFullName()))
			end
		end
	end
	local _48 = if _46 then _16(_45) else {}
	local _49, _50 = pcall(function()
		return _45:Clone()
	end)
	for _, _51 in _48 do
		if _51.Parent then
			_51.Archivable = false
		end
	end
	if not _49 or not _50 then
		warn(("[PolyRenderer] could not clone %s"):format(_45:GetFullName()))
		return nil
	end
	return _50
end

local function _18(_52, _53, _54)
	if _52:IsA("BasePart") and _53:IsA("BasePart") then
		table.insert(_54, { real = _52, copy = _53 })
	end
	local _55, _56 = _52:GetChildren(), _53:GetChildren()
	for _57 = 1, math.min(#_55, #_56) do
		_18(_55[_57], _56[_57], _54)
	end
end

local function _19(_58)
	return setmetatable({}, {
		__index = function(_, _59)
			if _59 == "Fps" then return _58.fps end
			if _59 == "MirrorTransparency" then return _58.mirrorTransparency end
			if _59 == "Source" then return _58.source end
			if _59 == "Clone" then return _58.clone end
			if _58.props[_59] ~= nil then return _58.props[_59] end
			local _60, _61 = pcall(function()
				return _58.clone[_59]
			end)
			if _60 then return _61 end
			return nil
		end,

		__newindex = function(_, _62, _63)
			if _62 == "Fps" then
				assert(_63 == nil or (type(_63) == "number" and _63 >= 0), "Fps must be nil or a number >= 0")
				_58.fps = _63
				_58.lastPose = 0
				return
			elseif _62 == "MirrorTransparency" then
				_58.mirrorTransparency = _63 and true or false
				return
			elseif _62 == "Source" or _62 == "Clone" then
				error(_62 .. " is read only", 2)
			end
			local _64 = pcall(function()
				_58.clone[_62] = _63
			end)
			if not _64 then
				_58.props[_62] = _63
			end
		end,

		__tostring = function()
			return ("PolyRenderer.Entry(%s, Fps=%s)"):format(_58.source.Name, tostring(_58.fps))
		end,
	})
end

local function _20(_65, _66)
	if type(_66) ~= "table" then return end
	local _67 = _65.handle
	if _66.Fps ~= nil then
		_67.Fps = _66.Fps
	end
	for _68, _69 in _66 do
		if _68 ~= "Fps" then
			_67[_68] = _69
		end
	end
end

local function _21(_70)
	for _, _71 in _70.conns do
		_71:Disconnect()
	end
	table.clear(_70.conns)
	if _70.clone then
		_70.clone:Destroy()
		_70.clone = nil
	end
	table.clear(_70.pairs)
end

local function _22(_72, _73)
	local _74 = _17(_73, _72.allowArchiving)
	if not _74 then return nil end

	local _75 = {}
	_18(_73, _74, _75)

	for _, _76 in _74:GetDescendants() do
		for _, _77 in _15 do
			if _76:IsA(_77) then
				_76:Destroy()
				break
			end
		end
	end

	local _78 = _74:FindFirstChildOfClass("Humanoid")
	if _78 then
		_78.EvaluateStateMachine = false
		_78.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		_78.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end

	for _, _79 in _75 do
		_79.copy.Anchored = true
		_79.copy.CanCollide = false
		_79.copy.CanQuery = false
		_79.copy.CanTouch = false
		_79.copy.CFrame = _79.real.CFrame
	end

	_74.Name = "Copy_" .. _73.Name
	_74.Parent = _72.viewport
	return _74, _75
end

local function _23(_80, _81)
	if not _81.source.Parent then return end
	local _82, _83 = _22(_80, _81.source)
	if not _82 then return end

	if _81.clone then
		_80.clones[_81.clone] = nil
		_81.clone:Destroy()
	end
	_81.clone = _82
	_81.pairs = _83
	_80.clones[_82] = _81
end

local function _24(_84, _85)
	if _85.rebuildQueued then return end
	_85.rebuildQueued = true
	task.defer(function()
		_85.rebuildQueued = false
		if _84.alive and _84.entries[_85.source] then
			_23(_84, _85)
		end
	end)
end

local function _25(_86, _87)
	if typeof(_87) ~= "Instance" then return nil end
	return _86.entries[_87] or _86.clones[_87]
end

local function _26(_88)
	local _89 = false
	local _90 = _88.mirrorTransparency
	for _, _91 in _88.pairs do
		local _92, _93 = _91.real, _91.copy
		if _92.Parent == nil or _93.Parent == nil then
			_89 = true
			continue
		end
		_93.CFrame = _92.CFrame
		if _90 and _93.Transparency ~= _92.Transparency then
			_93.Transparency = _92.Transparency
		end
	end
	return _89
end

local function _27(_94)
	local _95 = _8.CurrentCamera
	if not _95 then return end

	local _96 = os.clock()

	if _94.fps <= 0 or _96 - _94.lastStep >= 1 / _94.fps then
		_94.lastStep = _96
		_94.camera.CFrame = _95.CFrame
		_94.camera.FieldOfView = _95.FieldOfView

		if _94.syncLighting then
			local _97 = Color3.new(1, 1, 1)
			_94.viewport.Ambient = _7.OutdoorAmbient:Lerp(_97, 0.7)
			_94.viewport.LightColor = _97:Lerp(_7.ColorShift_Top, 0.15)
			_94.viewport.LightDirection = -_7:GetSunDirection()
		end
	end

	for _98, _99 in _94.entries do
		if not _98.Parent then
			_94.clones[_99.clone] = nil
			_21(_99)
			_94.entries[_98] = nil
			continue
		end

		local _100 = if _99.fps ~= nil then _99.fps else _94.fps
		if _100 > 0 then
			if _96 - _99.lastPose < 1 / _100 then continue end
			_99.lastPose = _96
		end

		if _26(_99) and _94.autoRebuild then
			_24(_94, _99)
		end
	end
end

local _28 = {}

function _28:Add(_101, _102)
	local _103 = _13[self]
	if not _103 or not _103.alive then return nil end
	if typeof(_101) ~= "Instance" then return nil end
	if _103.entries[_101] then return nil end

	local _104, _105 = _22(_103, _101)
	if not _104 then return nil end

	local _106 = {
		source = _101,
		clone = _104,
		pairs = _105,
		fps = nil,
		mirrorTransparency = true,
		props = {},
		lastPose = 0,
		rebuildQueued = false,
		conns = {},
	}
	_106.handle = _19(_106)

	table.insert(_106.conns, _101.Destroying:Connect(function()
		self:Remove(_101)
	end))
	table.insert(_106.conns, _101.DescendantAdded:Connect(function()
		if _103.autoRebuild then _24(_103, _106) end
	end))
	table.insert(_106.conns, _101.DescendantRemoving:Connect(function()
		if _103.autoRebuild then _24(_103, _106) end
	end))

	_103.entries[_101] = _106
	_103.clones[_104] = _106

	_20(_106, _102)
	return _106.clone
end

function _28:Edit(_107, _108)
	local _109 = _13[self]
	if not _109 then return nil end
	local _110 = _25(_109, _107)
	if not _110 then return nil end
	if _108 ~= nil then
		_20(_110, _108)
	end
	return _110.handle
end

function _28:Remove(_111)
	local _112 = _13[self]
	if not _112 then return false end
	local _113 = _25(_112, _111)
	if not _113 then return false end
	_112.entries[_113.source] = nil
	_112.clones[_113.clone] = nil
	_21(_113)
	return true
end

function _28:RemoveAll()
	local _114 = _13[self]
	if not _114 then return false end
	local _115 = false
	for _116, _117 in _114.entries do
		_114.clones[_117.clone] = nil
		_21(_117)
		_114.entries[_116] = nil
		_115 = true
	end
	return _115
end

function _28:Destroy()
	local _118 = _13[self]
	if not _118 or not _118.alive then return end
	_118.alive = false

	self:RemoveAll()
	if _118.heartbeat then
		_118.heartbeat:Disconnect()
		_118.heartbeat = nil
	end
	pcall(function()
		_0:UnbindFromRenderStep(_118.bindName)
	end)
	_118.gui:Destroy()
	_13[self] = nil
end

local function _29()
	local _119, _120 = pcall(function()
		return _9:GenerateGUID(false)
	end)
	if _119 and _120 then
		return "PolyRenderer_" .. _120
	end
	return ("PolyRenderer_%d_%d"):format(os.time(), math.random(0, 2 ^ 30))
end

function _12.new()
	local _121 = Instance.new("ScreenGui")
	_121.Name = "PolyRenderer"
	_121.ResetOnSpawn = false
	_121.IgnoreGuiInset = true
	_121.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local _122 = Instance.new("ViewportFrame")
	_122.Name = "Render"
	_122.Size = UDim2.fromScale(1, 1)
	_122.Position = UDim2.fromScale(0, 0)
	_122.BackgroundTransparency = 1
	_122.Ambient = Color3.fromRGB(200, 200, 200)
	_122.LightColor = Color3.fromRGB(255, 255, 255)
	_122.Parent = _121

	local _123 = Instance.new("Camera")
	_123.Name = "PolyCamera"
	_123.Parent = _122
	_122.CurrentCamera = _123

	_121.Parent = _11()

	local _124 = {
		alive = true,
		gui = _121,
		viewport = _122,
		camera = _123,
		entries = {},
		clones = {},
		props = {},
		fps = 0,
		lastStep = 0,
		autoRebuild = true,
		syncLighting = false,
		allowArchiving = true,
		bindName = _29(),
	}

	local _125 = {}

	setmetatable(_125, {
		__index = function(_, _126)
			if _28[_126] then return _28[_126] end
			if _126 == "Fps" then return _124.fps end
			if _126 == "AutoRebuild" then return _124.autoRebuild end
			if _126 == "SyncLighting" then return _124.syncLighting end
			if _126 == "AllowArchiving" then return _124.allowArchiving end
			if _126 == "ViewportFrame" then return _124.viewport end
			if _126 == "ScreenGui" then return _124.gui end
			if _126 == "Camera" then return _124.camera end
			if _124.props[_126] ~= nil then return _124.props[_126] end
			local _127, _128 = pcall(function()
				return _124.viewport[_126]
			end)
			if _127 then return _128 end
			return nil
		end,

		__newindex = function(_, _129, _130)
			if _129 == "Fps" then
				assert(type(_130) == "number" and _130 >= 0, "Fps must be a number >= 0")
				_124.fps = _130
				return
			elseif _129 == "AutoRebuild" then
				_124.autoRebuild = _130 and true or false
				return
			elseif _129 == "SyncLighting" then
				_124.syncLighting = _130 and true or false
				return
			elseif _129 == "AllowArchiving" then
				_124.allowArchiving = _130 and true or false
				return
			end
			local _131 = pcall(function()
				_124.viewport[_129] = _130
			end)
			if not _131 then
				_124.props[_129] = _130
			end
		end,

		__tostring = function()
			local _132 = 0
			for _ in _124.entries do _132 += 1 end
			return ("PolyRenderer(%d rendering, Fps=%s)"):format(_132, tostring(_124.fps))
		end,
	})

	_13[_125] = _124

	_124.heartbeat = _0.Heartbeat:Connect(function()
		if _124.alive then _27(_124) end
	end)
	_0:BindToRenderStep(_124.bindName, _14, function()
		if _124.alive then _27(_124) end
	end)

	return _125
end

return _12
