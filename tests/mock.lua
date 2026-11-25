-- A small imitation of the Roblox + executor environment (runs on texlua / Lua 5.3).
-- Purpose: load the hub without the game and test its logic. Nothing is drawn.
local M = {}
M.errors = {}          -- errors thrown inside coroutines / events (like Roblox's output)
M.remotes = {}         -- FireServer calls: { name, args... }
M.teleports = {}
M.drawings = {}
M.queued = {}
M.files = {}
M.httpRoutes = {}
M.onFire = setmetatable({}, { __mode = "k" })   -- [remote] = function(...) imitation of the server's response
M.now = 0

local unpack = table.unpack
local function pack(...) return { n = select("#", ...), ... } end

----- Luau library extras -----
function table.clone(t) local o = {} for k, v in pairs(t) do o[k] = v end return o end
function table.find(t, v, init) for i = init or 1, #t do if t[i] == v then return i end end return nil end
function table.clear(t) for k in pairs(t) do t[k] = nil end end
function math.clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
function math.round(x) return math.floor(x + 0.5) end
function math.sign(x) return x > 0 and 1 or x < 0 and -1 or 0 end
function string.split(s, sep)
	local out, start = {}, 1
	sep = sep or ","
	while true do
		local i, j = string.find(s, sep, start, true)
		if not i then out[#out + 1] = s:sub(start) break end
		out[#out + 1] = s:sub(start, i - 1)
		start = j + 1
	end
	return out
end
local realFloor = math.floor
math.floor = function(x) return realFloor(x) end

----- Scheduler (virtual clock) -----
local tasks = {}           -- { co, wake, args }
local current = nil
local function report(err, co)
	local tb = co and debug.traceback(co, tostring(err)) or tostring(err)
	M.errors[#M.errors + 1] = tb
end
local function resume(co, ...)
	local prev = current
	current = co
	local ok, err = coroutine.resume(co, ...)
	current = prev
	if not ok then report(err, co) end
	return ok
end
local function schedule(co, wake, args) tasks[#tasks + 1] = { co = co, wake = wake, args = args } end

task = {}
function task.spawn(f, ...)
	local co = type(f) == "thread" and f or coroutine.create(f)
	resume(co, ...)
	return co
end
function task.defer(f, ...)
	local co = type(f) == "thread" and f or coroutine.create(f)
	schedule(co, M.now, pack(...))
	return co
end
function task.delay(t, f, ...)
	local co = coroutine.create(f)
	schedule(co, M.now + (t or 0), pack(...))
	return co
end
function task.wait(t)
	t = t or 0
	local co = coroutine.running()
	assert(co and coroutine.isyieldable(), "task.wait ana thread'de çağrıldı")
	local start = M.now
	schedule(co, M.now + math.max(t, 1 / 60), nil)
	coroutine.yield()
	return M.now - start
end
function task.cancel(co) for i = #tasks, 1, -1 do if tasks[i].co == co then table.remove(tasks, i) end end end
wait = task.wait
spawn = task.spawn
delay = task.delay

function M.runReady()
	for _ = 1, 10000 do
		local idx
		for i, t in ipairs(tasks) do if t.wake <= M.now + 1e-9 then idx = i break end end
		if not idx then return end
		local t = table.remove(tasks, idx)
		if coroutine.status(t.co) == "suspended" then
			if t.args then resume(t.co, unpack(t.args, 1, t.args.n)) else resume(t.co) end
		end
	end
	error("zamanlayıcı döngüye girdi")
end
function M.pendingTasks() return #tasks end

----- Data types -----
local TYPE = setmetatable({}, { __mode = "k" })
function typeof(v)
	local t = type(v)
	if t == "table" then
		local mt = getmetatable(v)
		if mt and mt.__type then return mt.__type end
	end
	return t
end

-- Vector3
local V3 = { __type = "Vector3" }
local function v3(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, V3) end
V3.__index = function(v, k)
	if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) end
	if k == "Unit" then local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z) if m == 0 then return v3(0, 0, 0) end return v3(v.X / m, v.Y / m, v.Z / m) end
	if k == "x" then return v.X elseif k == "y" then return v.Y elseif k == "z" then return v.Z end
	if k == "Dot" then return function(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end end
	if k == "Cross" then return function(a, b) return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end end
	if k == "Lerp" then return function(a, b, t) return a + (b - a) * t end end
end
V3.__add = function(a, b) return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
V3.__sub = function(a, b) return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
V3.__mul = function(a, b)
	if type(a) == "number" then return v3(b.X * a, b.Y * a, b.Z * a) end
	if type(b) == "number" then return v3(a.X * b, a.Y * b, a.Z * b) end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3.__div = function(a, b) if type(b) == "number" then return v3(a.X / b, a.Y / b, a.Z / b) end return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z) end
V3.__unm = function(a) return v3(-a.X, -a.Y, -a.Z) end
V3.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
V3.__tostring = function(a) return ("%g, %g, %g"):format(a.X, a.Y, a.Z) end
Vector3 = { new = v3, zero = v3(0, 0, 0), one = v3(1, 1, 1), xAxis = v3(1, 0, 0), yAxis = v3(0, 1, 0), zAxis = v3(0, 0, 1) }

-- Vector2
local V2 = { __type = "Vector2" }
local function v2(x, y) return setmetatable({ X = x or 0, Y = y or 0 }, V2) end
V2.__index = function(v, k)
	if k == "Magnitude" then return math.sqrt(v.X * v.X + v.Y * v.Y) end
	if k == "Unit" then local m = math.sqrt(v.X * v.X + v.Y * v.Y) if m == 0 then return v2(0, 0) end return v2(v.X / m, v.Y / m) end
	if k == "Dot" then return function(a, b) return a.X * b.X + a.Y * b.Y end end
end
V2.__add = function(a, b) return v2(a.X + b.X, a.Y + b.Y) end
V2.__sub = function(a, b) return v2(a.X - b.X, a.Y - b.Y) end
V2.__mul = function(a, b)
	if type(a) == "number" then return v2(b.X * a, b.Y * a) end
	if type(b) == "number" then return v2(a.X * b, a.Y * b) end
	return v2(a.X * b.X, a.Y * b.Y)
end
V2.__div = function(a, b) if type(b) == "number" then return v2(a.X / b, a.Y / b) end return v2(a.X / b.X, a.Y / b.Y) end
V2.__unm = function(a) return v2(-a.X, -a.Y) end
V2.__eq = function(a, b) return a.X == b.X and a.Y == b.Y end
V2.__tostring = function(a) return ("%g, %g"):format(a.X, a.Y) end
Vector2 = { new = v2, zero = v2(0, 0), one = v2(1, 1) }

-- CFrame (position + 3x3 rotation; columns: right, up, back)
local CFm = { __type = "CFrame" }
local function cf(px, py, pz, r) -- r = { rx,ry,rz, ux,uy,uz, bx,by,bz }
	return setmetatable({ p = v3(px, py, pz), r = r or { 1, 0, 0, 0, 1, 0, 0, 0, 1 } }, CFm)
end
local function rotate(r, x, y, z) -- r * (x,y,z)
	return r[1] * x + r[4] * y + r[7] * z, r[2] * x + r[5] * y + r[8] * z, r[3] * x + r[6] * y + r[9] * z
end
CFm.__index = function(c, k)
	if k == "Position" then return c.p end
	if k == "X" then return c.p.X elseif k == "Y" then return c.p.Y elseif k == "Z" then return c.p.Z end
	if k == "RightVector" then return v3(c.r[1], c.r[2], c.r[3]) end
	if k == "UpVector" then return v3(c.r[4], c.r[5], c.r[6]) end
	if k == "LookVector" then return v3(-c.r[7], -c.r[8], -c.r[9]) end
	if k == "Rotation" then return cf(0, 0, 0, c.r) end
	if k == "Inverse" then return function(self)
		local r = self.r
		local t = { r[1], r[4], r[7], r[2], r[5], r[8], r[3], r[6], r[9] }
		local x, y, z = rotate(t, -self.p.X, -self.p.Y, -self.p.Z)
		return cf(x, y, z, t)
	end end
	if k == "PointToObjectSpace" then return function(self, v) return self:Inverse() * v end end
	if k == "PointToWorldSpace" then return function(self, v) return self * v end end
	if k == "ToWorldSpace" then return function(self, o) return self * o end end
	if k == "ToObjectSpace" then return function(self, o) return self:Inverse() * o end end
	if k == "GetComponents" then return function(self) local r = self.r return self.p.X, self.p.Y, self.p.Z, r[1], r[4], r[7], r[2], r[5], r[8], r[3], r[6], r[9] end end
end
CFm.__mul = function(a, b)
	if typeof(b) == "Vector3" then
		local x, y, z = rotate(a.r, b.X, b.Y, b.Z)
		return v3(a.p.X + x, a.p.Y + y, a.p.Z + z)
	end
	local r = {}
	for col = 0, 2 do
		local x, y, z = rotate(a.r, b.r[col * 3 + 1], b.r[col * 3 + 2], b.r[col * 3 + 3])
		r[col * 3 + 1], r[col * 3 + 2], r[col * 3 + 3] = x, y, z
	end
	local x, y, z = rotate(a.r, b.p.X, b.p.Y, b.p.Z)
	return cf(a.p.X + x, a.p.Y + y, a.p.Z + z, r)
end
CFm.__add = function(a, b) return cf(a.p.X + b.X, a.p.Y + b.Y, a.p.Z + b.Z, a.r) end
CFm.__sub = function(a, b) return cf(a.p.X - b.X, a.p.Y - b.Y, a.p.Z - b.Z, a.r) end
CFm.__eq = function(a, b) return a.p == b.p end
CFm.__tostring = function(a) return "CFrame(" .. tostring(a.p) .. ")" end
local function lookAt(pos, target)
	local f = (target - pos).Unit
	if f.Magnitude == 0 then return cf(pos.X, pos.Y, pos.Z) end
	local up = v3(0, 1, 0)
	local right = f:Cross(up)
	if right.Magnitude < 1e-6 then right = v3(1, 0, 0) end
	right = right.Unit
	local u = right:Cross(f).Unit
	return cf(pos.X, pos.Y, pos.Z, { right.X, right.Y, right.Z, u.X, u.Y, u.Z, -f.X, -f.Y, -f.Z })
end
CFrame = {
	new = function(a, b, c, ...)
		if typeof(a) == "Vector3" then
			if typeof(b) == "Vector3" then return lookAt(a, b) end
			return cf(a.X, a.Y, a.Z)
		end
		return cf(a or 0, b or 0, c or 0)
	end,
	lookAt = lookAt,
	Angles = function(rx, ry, rz)
		local cy, sy = math.cos(ry or 0), math.sin(ry or 0)
		return cf(0, 0, 0, { cy, 0, -sy, 0, 1, 0, sy, 0, cy })
	end,
	identity = cf(0, 0, 0),
}
CFrame.fromEulerAnglesXYZ = CFrame.Angles

-- Color3
local C3 = { __type = "Color3" }
local function toHSV(c)
	local r, g, b = c.R, c.G, c.B
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local d, h = mx - mn, 0
	if d > 0 then
		if mx == r then h = ((g - b) / d) % 6 elseif mx == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
		h = h / 6
	end
	return h, mx > 0 and d / mx or 0, mx
end
C3.__index = function(c, k)
	if k == "ToHSV" then return toHSV end
	if k == "ToHex" then return function(x) return ("%02X%02X%02X"):format(math.floor(x.R * 255 + 0.5), math.floor(x.G * 255 + 0.5), math.floor(x.B * 255 + 0.5)) end end
	if k == "Lerp" then return function(a, b, t) return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t) end end
	if k == "ToHex" then return function(self) return ("%02x%02x%02x"):format(self.R * 255, self.G * 255, self.B * 255) end end end
C3.__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end
C3.__tostring = function(c) return ("%g, %g, %g"):format(c.R, c.G, c.B) end
Color3 = {
	new = function(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3) end,
	fromRGB = function(r, g, b) return setmetatable({ R = (r or 0) / 255, G = (g or 0) / 255, B = (b or 0) / 255 }, C3) end,
	fromHSV = function(h, s, v)
		local i = math.floor(h * 6) % 6
		local f = h * 6 - math.floor(h * 6)
		local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
		local row = ({ { v, t, p }, { q, v, p }, { p, v, t }, { p, q, v }, { t, p, v }, { v, p, q } })[i + 1]
		return setmetatable({ R = row[1], G = row[2], B = row[3] }, C3)
	end,
	fromHex = function() return setmetatable({ R = 1, G = 1, B = 1 }, C3) end,
}

-- UDim / UDim2
local UD = { __type = "UDim" }
UD.__index = UD
UDim = { new = function(s, o) return setmetatable({ Scale = s or 0, Offset = o or 0 }, UD) end }
local UD2 = { __type = "UDim2" }
UD2.__index = UD2
UD2.__eq = function(a, b) return a.X.Scale == b.X.Scale and a.X.Offset == b.X.Offset and a.Y.Scale == b.Y.Scale and a.Y.Offset == b.Y.Offset end
UDim2 = {
	new = function(xs, xo, ys, yo) return setmetatable({ X = UDim.new(xs, xo), Y = UDim.new(ys, yo), Width = UDim.new(xs, xo), Height = UDim.new(ys, yo) }, UD2) end,
}
UDim2.fromOffset = function(x, y) return UDim2.new(0, x or 0, 0, y or 0) end
UDim2.fromScale = function(x, y) return UDim2.new(x or 0, 0, y or 0, 0) end

-- Ray, RaycastParams, others
local RAY = { __type = "Ray" }
RAY.__index = function(r, k) if k == "Unit" then return Ray.new(r.Origin, r.Direction.Unit) end end
Ray = { new = function(o, d) return setmetatable({ Origin = o, Direction = d }, RAY) end }
local RP = { __type = "RaycastParams" }
RP.__index = RP
RaycastParams = { new = function() return setmetatable({ FilterDescendantsInstances = {}, FilterType = nil, IgnoreWater = false }, RP) end }
local function dummyType(name)
	local mt = { __type = name }
	mt.__index = mt
	return { new = function(...) return setmetatable({ args = { ... } }, mt) end }
end
TweenInfo = dummyType("TweenInfo")
NumberSequence = dummyType("NumberSequence")
NumberSequenceKeypoint = { new = function(t, v) return { Time = t, Value = v } end }
ColorSequence = dummyType("ColorSequence")
ColorSequenceKeypoint = dummyType("ColorSequenceKeypoint")
NumberRange = dummyType("NumberRange")
Rect = dummyType("Rect")
PhysicalProperties = dummyType("PhysicalProperties")
Font = dummyType("Font")
do
	-- Family / Weight / Style like Roblox's Font; fromName / fromId / fromEnum give the family paths Roblox uses
	local new = Font.new
	local function make(family, weight, style)
		local face = new(family, weight, style)
		face.Family = family
		face.Weight = weight or Enum.FontWeight.Regular
		face.Style = style or Enum.FontStyle.Normal
		return face
	end
	Font.new = make
	Font.fromName = function(name, weight, style) return make("rbxasset://fonts/families/" .. name .. ".json", weight, style) end
	Font.fromId = function(id, weight, style) return make("rbxassetid://" .. tostring(id), weight, style) end
	Font.fromEnum = function(font) return make("rbxasset://fonts/families/" .. (type(font) == "table" and font.Name or tostring(font)) .. ".json") end
end

-- Enum
local EnumItemMT = { __type = "EnumItem" }
EnumItemMT.__index = EnumItemMT
EnumItemMT.__tostring = function(e) return "Enum." .. e.EnumType .. "." .. e.Name end
local enumCache = {}
Enum = setmetatable({}, { __index = function(_, typeName)
	local t = enumCache[typeName]
	if not t then
		t = setmetatable({}, { __index = function(self, name)
			local item = setmetatable({ Name = name, EnumType = typeName, Value = 0 }, EnumItemMT)
			rawset(self, name, item)
			return item
		end })
		t.GetEnumItems = function() return {} end
		enumCache[typeName] = t
	end
	return t
end })

----- Signals -----
local SignalMT = { __type = "RBXScriptSignal" }
SignalMT.__index = SignalMT
local ConnMT = { __type = "RBXScriptConnection" }
ConnMT.__index = ConnMT
function ConnMT:Disconnect() self.Connected = false self.signal.conns[self] = nil end
local function newSignal() return setmetatable({ conns = {}, order = {}, waiting = {} }, SignalMT) end
function SignalMT:Connect(fn)
	local c = setmetatable({ Connected = true, fn = fn, signal = self }, ConnMT)
	self.conns[c] = true
	self.order[#self.order + 1] = c
	return c
end
SignalMT.connect = SignalMT.Connect
function SignalMT:Once(fn)
	local c
	c = self:Connect(function(...) c:Disconnect() fn(...) end)
	return c
end
function SignalMT:Wait()
	local co = coroutine.running()
	self.waiting[#self.waiting + 1] = co
	return coroutine.yield()
end
function SignalMT:Fire(...)
	local list = {}
	for _, c in ipairs(self.order) do if c.Connected then list[#list + 1] = c end end
	local live = {}
	for _, c in ipairs(self.order) do if c.Connected then live[#live + 1] = c end end
	self.order = live
	for _, c in ipairs(list) do
		if c.Connected then
			local co = coroutine.create(c.fn)
			resume(co, ...)
		end
	end
	local w = self.waiting
	self.waiting = {}
	for _, co in ipairs(w) do resume(co, ...) end
end
function SignalMT:Count() local n = 0 for c in pairs(self.conns) do if c.Connected then n = n + 1 end end return n end
M.newSignal = newSignal

----- Instance -----
local InstMT = { __type = "Instance" }
local METHODS = {}
local GETTERS = {}       -- [class][prop] = function(self) ... end
local SETTERS = {}
local DEFAULTS = {}
local EVENTS = {
	Changed = true, ChildAdded = true, ChildRemoved = true, DescendantAdded = true, DescendantRemoving = true, AncestryChanged = true, Destroying = true,
	MouseEnter = true, MouseLeave = true, MouseMoved = true, Activated = true, MouseButton1Click = true, MouseButton1Down = true, MouseButton1Up = true,
	MouseButton2Click = true, InputBegan = true, InputEnded = true, InputChanged = true, FocusLost = true, Focused = true, Touched = true, TouchEnded = true,
	OnClientEvent = true, Event = true, Died = true, HealthChanged = true, StateChanged = true, Completed = true, CharacterAdded = true, CharacterRemoving = true,
	PlayerAdded = true, PlayerRemoving = true, RenderStepped = true, Heartbeat = true, Stepped = true, PreRender = true, PreSimulation = true, Idled = true, JumpRequest = true,
	MouseClick = true, Chatted = true, OnTeleport = true, TeleportInitFailed = true, ViewportSizeChanged = true,
}
local NILABLE = { Character = true, Team = true, PrimaryPart = true, Adornee = true, CameraSubject = true, Target = true, Value = true,
	Image = true, Font = true, FontFace = true, Archivable = true, Locked = true }
local ISA = {
	BasePart = { Part = true, MeshPart = true, UnionOperation = true, SpawnLocation = true, Seat = true, WedgePart = true, TrussPart = true },
	GuiObject = { Frame = true, TextLabel = true, TextButton = true, TextBox = true, ImageLabel = true, ImageButton = true, ScrollingFrame = true, ViewportFrame = true, CanvasGroup = true },
	GuiButton = { TextButton = true, ImageButton = true },
	UIGridStyleLayout = { UIListLayout = true, UIGridLayout = true },
	GuiBase2d = { Frame = true, TextLabel = true, TextButton = true, TextBox = true, ImageLabel = true, ImageButton = true, ScrollingFrame = true, ScreenGui = true },
	LayerCollector = { ScreenGui = true, BillboardGui = true, SurfaceGui = true },
	ValueBase = { StringValue = true, IntValue = true, NumberValue = true, BoolValue = true, ObjectValue = true, Vector3Value = true, CFrameValue = true, Color3Value = true, IntConstrainedValue = true, DoubleConstrainedValue = true },
	PVInstance = { Model = true, Part = true, MeshPart = true },
	LuaSourceContainer = { LocalScript = true, ModuleScript = true, Script = true },
	Model = { Model = true, Workspace = true },
}

local function rawprops(o) return rawget(o, "__p") end
local function newInstance(class, parent)
	local o = setmetatable({ __p = { ClassName = class, Name = class }, __kids = {}, __sig = {}, __psig = {} }, InstMT)
	for k, v in pairs(DEFAULTS[class] or {}) do
		o.__p[k] = type(v) == "function" and v() or v
	end
	if parent then o.Parent = parent end
	return o
end
M.newInstance = newInstance

local function isA(class, want)
	if class == want or want == "Instance" then return true end
	local set = ISA[want]
	return set ~= nil and set[class] == true
end

InstMT.__index = function(o, k)
	local p = rawprops(o)
	local class = p.ClassName
	local cm = METHODS[class]
	if cm and cm[k] ~= nil then return cm[k] end
	if METHODS.Instance[k] ~= nil then return METHODS.Instance[k] end
	local g = GETTERS[class] and GETTERS[class][k] or GETTERS.Any[k]
	if g then return g(o) end
	if k == "Parent" then return rawget(o, "__parent") end
	if p[k] ~= nil then return p[k] end
	for _, c in ipairs(o.__kids) do if rawprops(c).Name == k then return c end end
	if NILABLE[k] then return nil end
	if EVENTS[k] then
		local s = o.__sig[k]
		if not s then s = newSignal() o.__sig[k] = s end
		return s
	end
	error(("%s is not a valid member of %s \"%s\""):format(tostring(k), class, tostring(p.Name)), 2)
end
-- layout / decoration objects have no GuiObject properties (as in Roblox: setting one is an error)
local GuiOnly = { BackgroundTransparency = true, BackgroundColor3 = true, Size = true, Position = true, Visible = true, ZIndex = true }
local NotGui = { UICorner = true, UIStroke = true, UIGradient = true, UIListLayout = true, UIPadding = true, UIGridLayout = true, UISizeConstraint = true }
InstMT.__newindex = function(o, k, v)
	local p = rawprops(o)
	if GuiOnly[k] and NotGui[p.ClassName] then
		error(("%s is not a valid member of %s \"%s\""):format(tostring(k), p.ClassName, tostring(p.Name)), 2)
	end
	if k == "Parent" then
		local old = rawget(o, "__parent")
		if old == v then return end
		local function subtree()                               -- the object and all of its descendants (Roblox fires Descendant* for each)
			local list = { o }
			local function walk(x) for _, c in ipairs(x.__kids) do list[#list + 1] = c walk(c) end end
			walk(o)
			return list
		end
		if old then
			local anc = old
			while anc do
				if anc.__sig.DescendantRemoving then for _, d in ipairs(subtree()) do anc.__sig.DescendantRemoving:Fire(d) end end
				anc = rawget(anc, "__parent")
			end
			for i, c in ipairs(old.__kids) do if c == o then table.remove(old.__kids, i) break end end
			if old.__sig.ChildRemoved then old.__sig.ChildRemoved:Fire(o) end
		end
		rawset(o, "__parent", v)
		if v then
			v.__kids[#v.__kids + 1] = o
			if v.__sig.ChildAdded then v.__sig.ChildAdded:Fire(o) end
			local anc = v
			while anc do
				if anc.__sig.DescendantAdded then for _, d in ipairs(subtree()) do anc.__sig.DescendantAdded:Fire(d) end end
				anc = rawget(anc, "__parent")
			end
		end
		return
	end
	local s = SETTERS[p.ClassName] and SETTERS[p.ClassName][k] or SETTERS.Any[k]
	if s then return s(o, v) end
	local old = p[k]
	p[k] = v
	if old ~= v then
		local ps = o.__psig[k]
		if ps then ps:Fire() end
		if o.__sig.Changed then o.__sig.Changed:Fire(k) end
	end
end
InstMT.__tostring = function(o) return tostring(rawprops(o).Name) end

METHODS.Instance = {
	FindFirstChild = function(self, name, recursive)
		for _, c in ipairs(self.__kids) do if rawprops(c).Name == name then return c end end
		if recursive then
			for _, c in ipairs(self.__kids) do local f = c:FindFirstChild(name, true) if f then return f end end
		end
		return nil
	end,
	FindFirstChildOfClass = function(self, class)
		for _, c in ipairs(self.__kids) do if rawprops(c).ClassName == class then return c end end
	end,
	FindFirstChildWhichIsA = function(self, class, recursive)
		for _, c in ipairs(self.__kids) do if isA(rawprops(c).ClassName, class) then return c end end
		if recursive then for _, c in ipairs(self.__kids) do local f = c:FindFirstChildWhichIsA(class, true) if f then return f end end end
	end,
	FindFirstAncestor = function(self, name) local p = rawget(self, "__parent") while p do if rawprops(p).Name == name then return p end p = rawget(p, "__parent") end end,
	FindFirstAncestorOfClass = function(self, class) local p = rawget(self, "__parent") while p do if rawprops(p).ClassName == class then return p end p = rawget(p, "__parent") end end,
	FindFirstAncestorWhichIsA = function(self, class) local p = rawget(self, "__parent") while p do if isA(rawprops(p).ClassName, class) then return p end p = rawget(p, "__parent") end end,
	GetChildren = function(self) local t = {} for i, c in ipairs(self.__kids) do t[i] = c end return t end,
	GetDescendants = function(self)
		local out = {}
		local function walk(o) for _, c in ipairs(o.__kids) do out[#out + 1] = c walk(c) end end
		walk(self)
		return out
	end,
	IsA = function(self, class) return isA(rawprops(self).ClassName, class) end,
	IsDescendantOf = function(self, anc) local p = rawget(self, "__parent") while p do if p == anc then return true end p = rawget(p, "__parent") end return false end,
	IsAncestorOf = function(self, d) return d:IsDescendantOf(self) end,
	Destroy = function(self)
		if self.__sig.Destroying then self.__sig.Destroying:Fire() end
		for _, c in ipairs(self:GetChildren()) do c:Destroy() end
		self.Parent = nil
		rawset(self, "__destroyed", true)
	end,
	Remove = function(self) self.Parent = nil end,
	ClearAllChildren = function(self) for _, c in ipairs(self:GetChildren()) do c:Destroy() end end,
	Clone = function(self)
		local o = newInstance(rawprops(self).ClassName)
		for k, v in pairs(rawprops(self)) do o.__p[k] = v end
		for _, c in ipairs(self.__kids) do c:Clone().Parent = o end
		return o
	end,
	WaitForChild = function(self, name, timeout)
		local c = self:FindFirstChild(name)
		if c then return c end
		local t0 = M.now
		while not c do
			if timeout and M.now - t0 > timeout then return nil end
			if not coroutine.isyieldable() then error("WaitForChild ana thread'de: " .. name) end
			task.wait(0.1)
			c = self:FindFirstChild(name)
			if M.now - t0 > 30 then error("WaitForChild zaman aşımı: " .. name) end
		end
		return c
	end,
	GetPropertyChangedSignal = function(self, prop)
		local s = self.__psig[prop]
		if not s then s = newSignal() self.__psig[prop] = s end
		return s
	end,
	GetFullName = function(self)
		local parts, o = {}, self
		while o and rawprops(o).ClassName ~= "DataModel" do table.insert(parts, 1, rawprops(o).Name) o = rawget(o, "__parent") end
		return table.concat(parts, ".")
	end,
	GetAttribute = function(self, k) return (rawget(self, "__attr") or {})[k] end,
	SetAttribute = function(self, k, v) local a = rawget(self, "__attr") or {} rawset(self, "__attr", a) a[k] = v end,
	GetAttributes = function(self) return rawget(self, "__attr") or {} end,
	GetAttributeChangedSignal = function(self) return newSignal() end,
}
GETTERS.Any = {}
SETTERS.Any = {}

-- BasePart: Position ↔ CFrame
local function partGetters()
	return {
		Position = function(o) return rawprops(o).CFrame.p end,
		Orientation = function() return v3(0, 0, 0) end,
	}
end
local function partSetters()
	return {
		Position = function(o, v) local c = rawprops(o).CFrame rawprops(o).CFrame = cf(v.X, v.Y, v.Z, c.r) end,
		CFrame = function(o, v)
			assert(typeof(v) == "CFrame", "CFrame'e " .. typeof(v) .. " atandı")
			local old = rawprops(o).CFrame
			rawprops(o).CFrame = v
			-- when the character's root moves, the other (welded) parts move with it, as in real Roblox
			local ch = rawprops(o).Name == "HumanoidRootPart" and o.Parent
			if ch and ch:FindFirstChildOfClass("Humanoid") then
				local d = v.p - old.p
				for _, c in ipairs(ch:GetChildren()) do
					if c ~= o and c:IsA("BasePart") then local pc = rawprops(c).CFrame rawprops(c).CFrame = cf(pc.X + d.X, pc.Y + d.Y, pc.Z + d.Z, pc.r) end
				end
			end
		end,
	}
end
for class in pairs(ISA.BasePart) do
	GETTERS[class] = partGetters()
	SETTERS[class] = partSetters()
	DEFAULTS[class] = { CFrame = function() return cf(0, 0, 0) end, Size = function() return v3(2, 1, 2) end, Anchored = false, CanCollide = true,
		Transparency = 0, AssemblyLinearVelocity = function() return v3(0, 0, 0) end, Velocity = function() return v3(0, 0, 0) end, Color = function() return Color3.new(0.64, 0.64, 0.64) end }
end
for class in pairs(ISA.ValueBase) do DEFAULTS[class] = { Value = (class == "StringValue" and "") or (class == "BoolValue" and false) or (class == "ObjectValue" and nil) or 0 } end
local GUI = { Visible = true, BackgroundTransparency = 0, ZIndex = 1, LayoutOrder = 0, Size = function() return UDim2.new(0, 0, 0, 0) end,
	Position = function() return UDim2.new(0, 0, 0, 0) end, AnchorPoint = function() return v2(0, 0) end, Rotation = 0, BorderSizePixel = 1,
	BackgroundColor3 = function() return Color3.new(1, 1, 1) end, AbsolutePosition = function() return v2(0, 0) end, AbsoluteSize = function() return v2(100, 20) end,
	Text = "", TextSize = 14, TextColor3 = function() return Color3.new(0, 0, 0) end, TextTransparency = 0, TextStrokeTransparency = 1, Image = "", ImageTransparency = 0, AutomaticSize = nil,
	ClipsDescendants = false, Active = false, Selectable = false }
for class in pairs(ISA.GuiObject) do DEFAULTS[class] = GUI end
-- an image (an icon) sized in pixels is that big on screen, unless a test says otherwise
for _, class in ipairs({ "ImageLabel", "ImageButton" }) do
	GETTERS[class] = { AbsoluteSize = function(o)
		local p = rawprops(o)
		-- (every gui starts with the 100 x 20 default; anything else was set by a test)
		local set = p.AbsoluteSize
		if set and not (set.X == 100 and set.Y == 20) then return set end
		local size = p.Size
		-- (rawset(image, "__uiScale", 1.25): drawn inside a 125 % UI scale)
		local scale = rawget(o, "__uiScale") or 1
		if size and size.X.Scale == 0 and size.Y.Scale == 0 and size.X.Offset > 0 then return v2(size.X.Offset * scale, size.Y.Offset * scale) end
		return v2(100, 20)
	end }
end
for _, class in ipairs({ "TextLabel", "TextButton", "TextBox" }) do
	GETTERS[class] = { TextBounds = function(o) local p = rawprops(o) return v2(#tostring(p.Text or "") * (p.TextSize or 14) * 0.55, p.TextSize or 14) end }
end
DEFAULTS.ScreenGui = { Enabled = true, DisplayOrder = 0, IgnoreGuiInset = false, ResetOnSpawn = true }
-- layouts and scrolling frames: what the lib reads back while it sizes things (nothing is laid out here)
DEFAULTS.UIListLayout = { AbsoluteContentSize = function() return v2(0, 0) end, Padding = function() return UDim.new(0, 0) end }
DEFAULTS.UIGridLayout = { AbsoluteContentSize = function() return v2(0, 0) end }
do
	local scroll = {}
	for k, v in pairs(GUI) do scroll[k] = v end
	scroll.CanvasPosition = function() return v2(0, 0) end
	scroll.CanvasSize = function() return UDim2.new(0, 0, 0, 0) end
	scroll.AbsoluteCanvasSize = function() return v2(0, 0) end
	scroll.AbsoluteWindowSize = function() return v2(100, 100) end
	scroll.ScrollingEnabled = true
	DEFAULTS.ScrollingFrame = scroll
end
DEFAULTS.UIStroke = { Enabled = true, Thickness = 1, Transparency = 0, Color = function() return Color3.new(0, 0, 0) end }
DEFAULTS.Highlight = { Enabled = true, FillTransparency = 0.5, OutlineTransparency = 0, FillColor = function() return Color3.new(1, 0, 0) end, OutlineColor = function() return Color3.new(1, 1, 1) end }
DEFAULTS.Humanoid = { Health = 100, MaxHealth = 100, WalkSpeed = 16, JumpPower = 50, UseJumpPower = false, AutoRotate = true,
	MoveDirection = function() return v3(0, 0, 0) end }
-- as in Roblox: Humanoid.Health is clamped between 0 and MaxHealth (negative values become 0)
SETTERS.Humanoid = SETTERS.Humanoid or {}
SETTERS.Humanoid.Health = function(o, v)
	local maxh = rawprops(o).MaxHealth or 100
	rawprops(o).Health = math.max(0, math.min(v, maxh))
end
METHODS.Humanoid = { ChangeState = function() end, GetState = function() return Enum.HumanoidStateType.Running end, MoveTo = function() end,
	LoadAnimation = function() return { Play = function() end, Stop = function() end } end, TakeDamage = function(self, d) self.Health = self.Health - d end }
METHODS.RemoteEvent = {
	FireServer = function(self, ...)
		M.remotes[#M.remotes + 1] = { name = rawprops(self).Name, owner = rawget(self, "__parent") and rawprops(rawget(self, "__parent")).Name, args = pack(...), t = M.now }
		local h = M.onFire[self]
		if h then h(...) end
	end,
}
METHODS.RemoteFunction = { InvokeServer = function(self, ...) M.remotes[#M.remotes + 1] = { name = rawprops(self).Name, args = pack(...), t = M.now } return nil end }
METHODS.BindableEvent = { Fire = function(self, ...) self.Event:Fire(...) end }
METHODS.Model = {
	GetPivot = function(self) local r = self:FindFirstChild("HumanoidRootPart") or self.PrimaryPart return r and r.CFrame or cf(0, 0, 0) end,
	PivotTo = function(self, c) local r = self:FindFirstChild("HumanoidRootPart") if r then r.CFrame = c end end,
	GetBoundingBox = function(self) return self:GetPivot(), v3(4, 5, 2) end,
	GetExtentsSize = function() return v3(4, 5, 2) end,
}
METHODS.ClickDetector = {}
METHODS.Sound = { Play = function() end, Stop = function() end }
METHODS.TextBox = { CaptureFocus = function() end, ReleaseFocus = function() end }

Instance = { new = function(class, parent) return newInstance(class, parent) end }

----- Services, game -----
local game_ = newInstance("DataModel")
game_.__p.Name = "Game"
M.game = game_
local services = {}
local function service(name)
	local s = services[name]
	if not s then
		s = newInstance(name == "Workspace" and "Workspace" or name)
		s.__p.Name = name
		s.Parent = game_
		services[name] = s
	end
	return s
end
METHODS.DataModel = {
	GetService = function(_, name) return service(name) end,
	service = function(_, name) return service(name) end,          -- legacy spelling (game:service)
	FindService = function(_, name) return services[name] end,
	IsLoaded = function() return true end,
	HttpGet = function(_, url) return M.http(url) end,
	HttpGetAsync = function(_, url) return M.http(url) end,
	BindToClose = function() end,
}
GETTERS.DataModel = { Workspace = function() return service("Workspace") end }
M.service = service

function M.http(url)
	for pattern, handler in pairs(M.httpRoutes) do
		if url:find(pattern, 1, true) then return type(handler) == "function" and handler(url) or handler end
	end
	error("HttpGet: bilinmeyen adres " .. url)
end

-- RunService
local RS = service("RunService")
METHODS.RunService = { IsStudio = function() return false end, IsClient = function() return true end, IsServer = function() return false end,
	BindToRenderStep = function() end, UnbindFromRenderStep = function() end }

-- Workspace + camera
local WS = service("Workspace")
workspace = WS
Workspace = WS
local cam = newInstance("Camera")
cam.__p.Name = "Camera"
cam.__p.CFrame = cf(0, 10, 30)
cam.__p.FieldOfView = 70
cam.__p.ViewportSize = v2(1280, 720)
cam.Parent = WS
WS.__p.CurrentCamera = cam
WS.__p.Gravity = 196.2
local function project(c, pos)
	local rel = c.CFrame:PointToObjectSpace(pos)          -- the camera looks along -Z
	local depth = -rel.Z
	local vs = c.ViewportSize
	local f = (vs.Y / 2) / math.tan(math.rad(c.FieldOfView / 2))
	if depth <= 0.01 then return v3(vs.X / 2 - rel.X * 1e4, vs.Y / 2 + rel.Y * 1e4, depth), false end
	local x = vs.X / 2 + rel.X / depth * f
	local y = vs.Y / 2 - rel.Y / depth * f
	local on = x >= 0 and x <= vs.X and y >= 0 and y <= vs.Y
	return v3(x, y, depth), on
end
METHODS.Camera = {
	WorldToViewportPoint = function(self, pos) return project(self, pos) end,
	WorldToScreenPoint = function(self, pos) return project(self, pos) end,
	ScreenPointToRay = function(self) return Ray.new(self.CFrame.p, self.CFrame.LookVector) end,
	ViewportPointToRay = function(self) return Ray.new(self.CFrame.p, self.CFrame.LookVector) end,
}
M.raycastResult = nil
METHODS.Workspace = {
	Raycast = function(self, origin, dir, params)
		M.lastRaycast = { origin = origin, dir = dir }
		if type(M.raycastResult) == "function" then return M.raycastResult(origin, dir, params) end
		return M.raycastResult
	end,
	FindPartOnRay = function(self, ray) M.lastRay = ray return nil, ray.Origin + ray.Direction end,
	FindPartOnRayWithIgnoreList = function(self, ray) M.lastRay = ray return nil, ray.Origin + ray.Direction end,
	FindPartOnRayWithWhitelist = function(self, ray) M.lastRay = ray return nil, ray.Origin + ray.Direction end,
	GetServerTimeNow = function() return M.now end,
}
local terrain = newInstance("Terrain") terrain.__p.Name = "Terrain" terrain.Parent = WS

-- Lighting
local LT = service("Lighting")
for k, v in pairs({ Brightness = 1, ClockTime = 14, FogEnd = 1000, FogStart = 0, GlobalShadows = true }) do LT.__p[k] = v end
LT.__p.Ambient = Color3.new(0.5, 0.5, 0.5)
LT.__p.OutdoorAmbient = Color3.new(0.5, 0.5, 0.5)

-- UserInputService
local UIS = service("UserInputService")
M.mouse = v2(640, 360)
M.keys = {}
UIS.__p.TouchEnabled = false UIS.__p.KeyboardEnabled = true UIS.__p.MouseEnabled = true UIS.__p.MouseBehavior = Enum.MouseBehavior.Default
UIS.__p.MouseIconEnabled = true
METHODS.UserInputService = {
	GetMouseLocation = function() return M.mouse end,
	IsKeyDown = function(_, k) return M.keys[k.Name] == true end,
	IsMouseButtonPressed = function() return false end,
	GetFocusedTextBox = function() return nil end,
	GetKeysPressed = function() return {} end,
}

-- TeleportService
local TS = service("TeleportService")
METHODS.TeleportService = {
	Teleport = function(_, place, plr) M.teleports[#M.teleports + 1] = { kind = "Teleport", place = place } end,
	TeleportToPlaceInstance = function(_, place, job, plr) M.teleports[#M.teleports + 1] = { kind = "Instance", place = place, job = job } end,
	TeleportAsync = function(_, place) M.teleports[#M.teleports + 1] = { kind = "Async", place = place } end,
}

-- HttpService (minimal JSON)
local HS = service("HttpService")
local json = {}
local function esc(s) return (s:gsub('[%c"\\]', function(c) return ({ ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\t"] = "\\t", ["\r"] = "\\r" })[c] or ("\\u%04x"):format(c:byte()) end)) end
function json.encode(v)
	local t = type(v)
	if t == "nil" then return "null" elseif t == "boolean" then return tostring(v)
	elseif t == "number" then return (v % 1 == 0 and ("%d"):format(v)) or ("%.14g"):format(v)
	elseif t == "string" then return '"' .. esc(v) .. '"'
	elseif t == "table" then
		if #v > 0 or next(v) == nil then
			local parts = {} for i, x in ipairs(v) do parts[i] = json.encode(x) end
			if next(v) == nil then return "[]" end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local parts, keys = {}, {}
		for k in pairs(v) do keys[#keys + 1] = tostring(k) end
		table.sort(keys)
		for _, k in ipairs(keys) do parts[#parts + 1] = '"' .. esc(k) .. '":' .. json.encode(v[k]) end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	error("JSONEncode: " .. t)
end
function json.decode(s)
	local i = 1
	local function ws() i = s:find("[^%s]", i) or #s + 1 end
	local val
	local function str()
		local out = {} i = i + 1
		while true do
			local c = s:sub(i, i)
			if c == '"' then i = i + 1 break end
			if c == "\\" then
				local n = s:sub(i + 1, i + 1)
				if n == "u" then out[#out + 1] = utf8.char(tonumber(s:sub(i + 2, i + 5), 16)) i = i + 6
				else out[#out + 1] = ({ n = "\n", t = "\t", r = "\r", b = "\b", f = "\f" })[n] or n i = i + 2 end
			else out[#out + 1] = c i = i + 1 end
			if i > #s then error("JSON: kapanmamış string") end
		end
		return table.concat(out)
	end
	function val()
		ws()
		local c = s:sub(i, i)
		if c == "{" then
			local t = {} i = i + 1 ws()
			if s:sub(i, i) == "}" then i = i + 1 return t end
			while true do
				ws() local k = str() ws() assert(s:sub(i, i) == ":", "JSON ':'") i = i + 1
				t[k] = val() ws()
				local d = s:sub(i, i) i = i + 1
				if d == "}" then return t end
				assert(d == ",", "JSON ','")
			end
		elseif c == "[" then
			local t = {} i = i + 1 ws()
			if s:sub(i, i) == "]" then i = i + 1 return t end
			while true do
				t[#t + 1] = val() ws()
				local d = s:sub(i, i) i = i + 1
				if d == "]" then return t end
				assert(d == ",", "JSON ','")
			end
		elseif c == '"' then return str()
		elseif s:sub(i, i + 3) == "true" then i = i + 4 return true
		elseif s:sub(i, i + 4) == "false" then i = i + 5 return false
		elseif s:sub(i, i + 3) == "null" then i = i + 4 return nil
		else
			local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
			assert(num and #num > 0, "JSON: beklenmeyen karakter " .. c)
			i = i + #num
			return tonumber(num)
		end
	end
	return val()
end
local guid = 0
METHODS.HttpService = {
	JSONEncode = function(_, v) return json.encode(v) end,
	JSONDecode = function(_, s) return json.decode(s) end,
	GenerateGUID = function() guid = guid + 1 return ("GUID-%04d"):format(guid) end,
	UrlEncode = function(_, s) return s end,
}
M.json = json

-- other services
service("ReplicatedStorage") service("CoreGui") service("StarterGui") service("VirtualUser") service("TweenService") service("SoundService")
service("GuiService") service("TextService") service("Stats") service("ContentProvider") service("MarketplaceService") service("Teams") service("Debris")
METHODS.VirtualUser = { CaptureController = function() end, ClickButton2 = function() M.antiAfkClicks = (M.antiAfkClicks or 0) + 1 end, Button2Down = function() end, Button2Up = function() end }
METHODS.TweenService = { Create = function(_, obj, info, props) return { Play = function() for k, v in pairs(props or {}) do obj[k] = v end end, Cancel = function() end, Pause = function() end, Completed = newSignal() } end }
METHODS.TextService = {
	GetTextSize = function(_, text, size) return v2(#text * size * 0.55, size) end,
	-- (the font's own widths: capitals wider, a lone space trimmed to 0 like Roblox does)
	GetTextBoundsAsync = function(_, params)
		local text, size = tostring(params.Text or ""), params.Size or 14
		if text == " " then return v2(0, size) end
		local width = 0
		for i = 1, #text do
			local c = text:sub(i, i)
			width = width + (c == " " and 0.3 or c:match("%u") and 0.68 or 0.55)
		end
		return v2(width * size, size)
	end,
}
METHODS.StarterGui = { SetCore = function() end, GetCore = function() return nil end, SetCoreGuiEnabled = function() end }
METHODS.GuiService = { GetGuiInset = function() return v2(0, 36), v2(0, 0) end }
METHODS.ContentProvider = { PreloadAsync = function() end }
METHODS.Debris = { AddItem = function() end }
METHODS.MarketplaceService = { GetProductInfo = function() return { Name = "Shindo Life" } end }
METHODS.Stats = {}

-- Players
local PS = service("Players")
PS.__p.MaxPlayers = 20
METHODS.Players = {
	GetPlayers = function(self) local t = {} for _, c in ipairs(self.__kids) do if rawprops(c).ClassName == "Player" then t[#t + 1] = c end end return t end,
	GetPlayerFromCharacter = function(self, ch) for _, p in ipairs(self:GetPlayers()) do if p.Character == ch then return p end end end,
	GetUserThumbnailAsync = function() return "rbxthumb://", true end,
	GetNameFromUserIdAsync = function() return "Player" end,
}
local MouseMT
METHODS.Player = {
	GetMouse = function(self)
		local m = rawget(self, "__mouse")
		if not m then
			m = newInstance("Mouse")
			m.__p.Hit = cf(0, 0, 0)
			m.__p.Target = nil
			m.__p.X = 0 m.__p.Y = 0
			rawset(self, "__mouse", m)
		end
		return m
	end,
	GetNetworkPing = function() return 0.032 end,
	IsFriendsWith = function() return false end,
	GetRankInGroup = function(self, gid) return (rawget(self, "__ranks") or {})[gid] or 0 end,
	GetRoleInGroup = function() return "Guest" end,
	IsInGroup = function() return false end,
	Kick = function(self, msg) M.kicked = msg or "" end,
	LoadCharacter = function() end,
	GetFriendsOnline = function() return {} end,
}

----- Helpers (for tests) -----
function M.value(class, name, value, parent)
	local v = newInstance(class)
	v.__p.Name = name
	v.__p.Value = value
	v.Parent = parent
	return v
end
function M.folder(name, parent, class)
	local f = newInstance(class or "Folder")
	f.__p.Name = name
	f.Parent = parent
	return f
end
function M.part(name, pos, parent, class)
	local p = newInstance(class or "Part")
	p.__p.Name = name
	p.__p.CFrame = cf(pos.X, pos.Y, pos.Z)
	p.Parent = parent
	return p
end
function M.character(name, pos, parent)
	local ch = M.folder(name, parent or WS, "Model")
	local hum = newInstance("Humanoid") hum.__p.Name = "Humanoid" hum.Parent = ch
	M.part("HumanoidRootPart", pos, ch)
	M.part("Head", pos + v3(0, 1.5, 0), ch)
	M.part("UpperTorso", pos + v3(0, 0.5, 0), ch)
	M.part("LowerTorso", pos + v3(0, -0.5, 0), ch)
	return ch
end
local uid = 1000
function M.player(name, pos, opts)
	opts = opts or {}
	uid = uid + 1
	local p = newInstance("Player")
	p.__p.Name = name
	p.__p.DisplayName = opts.DisplayName or name
	p.__p.UserId = opts.UserId or uid
	p.__p.Neutral = true
	p.__p.Team = nil
	p.__p.TeamColor = { Color = Color3.new(1, 1, 1) }
	p.__p.AccountAge = 100
	p.__p.MembershipType = Enum.MembershipType.None
	p.__p.CameraMaxZoomDistance = 128
	if pos then p.__p.Character = M.character(name, pos) end
	p.Parent = PS
	if not opts.silent then PS.PlayerAdded:Fire(p) end
	return p
end
function M.removePlayer(p)
	p.Parent = nil
	PS.PlayerRemoving:Fire(p)
	if p.__p.Character then p.__p.Character:Destroy() end
end

----- Executor functions -----
M.genv = {}
function getgenv() return M.genv end
getrenv = function() return _G end
M.checkcaller = true
function checkcaller() return M.checkcaller end
M.namecallMethod = nil
function getnamecallmethod() return M.namecallMethod end
newcclosure = function(f) return f end
clonefunction = function(f) return f end
M.hooks = {}
function hookmetamethod(obj, name, fn)
	local original = function(self, ...)
		if name == "__namecall" then
			local method = M.namecallMethod
			return self[method](self, ...)
		elseif name == "__index" then
			return self[...]
		end
	end
	M.hooks[name] = fn
	return original
end
-- the game's own code making a namecall (goes through the hook if there is one)
function M.gameNamecall(obj, method, ...)
	local prevCaller, prevMethod = M.checkcaller, M.namecallMethod
	M.checkcaller = false
	M.namecallMethod = method
	local h = M.hooks.__namecall
	local res
	if h then res = pack(h(obj, ...)) else res = pack(obj[method](obj, ...)) end
	M.checkcaller, M.namecallMethod = prevCaller, prevMethod
	return unpack(res, 1, res.n)
end
function M.gameIndex(obj, key)
	local prev = M.checkcaller
	M.checkcaller = false
	local h = M.hooks.__index
	local r
	if h then r = h(obj, key) else r = obj[key] end
	M.checkcaller = prev
	return r
end
local proxies = setmetatable({}, { __mode = "k" })
cloneref = function(real)
	if proxies[real] then return proxies[real] end
	local proxy
	proxy = setmetatable({}, {
		__type = "Instance",
		__index = function(_, k)
			local v = real[k]
			if type(v) == "function" then
				return function(s, ...) if s == proxy then s = real end return v(s, ...) end
			end
			return v
		end,
		__newindex = function(_, k, v) real[k] = v end,
		__tostring = function() return tostring(real) end,
	})
	proxies[real] = proxy
	return proxy
end
M.cloneref = cloneref
gethui = function() return service("CoreGui") end
setclipboard = function(s) M.clipboard = s end
toclipboard = setclipboard
queue_on_teleport = function(code) M.queued[#M.queued + 1] = code end
fireclickdetector = function(cd) M.clicked = (M.clicked or 0) + 1 end
firetouchinterest = function() end
identifyexecutor = function() return "Mock", "1.0" end
getfenv = getfenv or function() return _G end                    -- Luau has it; Lua 5.3 does not
getexecutorname = identifyexecutor
request = function() return { StatusCode = 200, Body = "{}" } end
http_request = request
writefile = function(p, s) M.files[p] = s end
appendfile = function(p, s) M.files[p] = (M.files[p] or "") .. s end
readfile = function(p) local s = M.files[p] if s == nil then error("dosya yok: " .. p) end return s end
isfile = function(p) return M.files[p] ~= nil end
isfolder = function(p) return M.files[p .. "/"] ~= nil end
makefolder = function(p) M.files[p .. "/"] = "" end
listfiles = function(p) local t = {} for k in pairs(M.files) do if k:sub(1, #p + 1) == p .. "/" then t[#t + 1] = k end end return t end
delfile = function(p) M.files[p] = nil end
loadstring = function(s, name) return load(s, name or "=loadstring") end
warn = function(...) M.warnings = M.warnings or {} M.warnings[#M.warnings + 1] = table.concat({ ... }, " ") end
local realPrint = print
M.prints = {}
print = function(...) M.prints[#M.prints + 1] = table.concat((function(...) local t = {} for i = 1, select("#", ...) do t[i] = tostring((select(i, ...))) end return t end)(...), " ") end
M.realPrint = realPrint
os.clock = function() return M.now end
tick = function() return M.now end
time = function() return M.now end
DateTime = { now = function() return { UnixTimestamp = 0, UnixTimestampMillis = 0, FormatLocalTime = function() return "00:00" end } end }
utf8 = utf8

-- Drawing API (records calls)
M.drawingMode = "ok"          -- "ok" | "none" | "noTextBounds" | "noTriangle"
local DrawMT = { __type = "table" }
local function newDrawing(kind)
	if M.drawingMode == "noTriangle" and kind == "Triangle" then error("Drawing.new: Triangle desteklenmiyor") end
	local d = { __kind = kind, __props = { Visible = false, Transparency = 1, Color = Color3.new(1, 1, 1) }, __removed = false }
	local mt = {
		__index = function(self, k)
			if k == "Remove" or k == "Destroy" then return function(s) s.__removed = true end end
			if k == "TextBounds" then
				if M.drawingMode == "noTextBounds" then error("TextBounds is not a valid member") end
				local p = rawget(self, "__props")
				return v2(#tostring(p.Text or "") * (p.Size or 13) * 0.5, p.Size or 13)
			end
			if M.drawingMode == "writeOnly" then return nil end     -- some executors: properties cannot be read
			return rawget(self, "__props")[k]
		end,
		__newindex = function(self, k, v)
			if rawget(self, "__removed") then error("Drawing objesi silinmiş") end
			rawget(self, "__props")[k] = v
		end,
	}
	setmetatable(d, mt)
	M.drawings[#M.drawings + 1] = d
	return d
end
Drawing = setmetatable({ Fonts = { UI = 0, System = 1, Plex = 2, Monospace = 3 } }, {
	__index = function(_, k)
		if k == "new" then
			if M.drawingMode == "none" then return nil end
			return newDrawing
		end
	end,
})
function M.drawingsOf(kind, visibleOnly)
	local out = {}
	for _, d in ipairs(M.drawings) do
		if d.__kind == kind and not d.__removed and (not visibleOnly or d.__props.Visible) then out[#out + 1] = d end
	end
	return out
end

----- Frames / time -----
local RunServiceRef = RS
function M.frame(dt)
	dt = dt or 1 / 60
	M.now = M.now + dt
	RunServiceRef.PreSimulation:Fire(dt)
	RunServiceRef.Stepped:Fire(M.now, dt)
	RunServiceRef.RenderStepped:Fire(dt)
	RunServiceRef.Heartbeat:Fire(dt)
	M.runReady()
end
function M.advance(seconds, dt)
	dt = dt or 1 / 30
	local target = M.now + seconds
	while M.now < target - 1e-9 do M.frame(math.min(dt, target - M.now)) end
end
function M.remotesSince(t, name)
	local out = {}
	for _, r in ipairs(M.remotes) do
		if r.t >= t and (not name or r.name == name) then out[#out + 1] = r end
	end
	return out
end

-- game global
game = game_
M.WS, M.PS, M.UIS, M.LT, M.RS, M.cam = WS, PS, UIS, LT, RS, cam
return M
