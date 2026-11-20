-- A fake Qustah UI lib: draws nothing, records every tab / card / element that is created.
-- Like the real lib: Callback does not run when an element is created (silent); :Set and Window:SetFlag run it.
local mock = ...
local L = { Flags = {}, windows = {}, elements = {}, notifications = {}, modules = {}, reported = {}, warnings = {} }

local function noop() end
local ElementMT = {}
ElementMT.__index = function(self, k)
	local v = rawget(ElementMT, k)
	if v ~= nil then return v end
	-- unknown methods (SetX, AddX...) pass silently; things read like properties (Row etc.) are nil
	if k == "Destroyed" then return nil end                          -- a property in the lib (false until :Destroy)
	if type(k) == "string" and (k:match("^Set") or k:match("^Get") or k:match("^Add") or k:match("^Remove") or k:match("^Clear")
		or k:match("^Update") or k:match("^Refresh") or k:match("^Push") or k:match("^Flash") or k:match("^Move") or k:match("^Reset")
		or k:match("^Run") or k:match("^Select") or k:match("^Print") or k:match("^Log") or k:match("^Destroy") or k:match("^Show")
		or k:match("^Hide") or k:match("^Sort") or k:match("^Section")) then
		return function() return self end
	end
	return nil
end
function ElementMT:Set(v, ...)
	if self.Kind == "Swatches" then                                 -- as in the lib: Set(name, silent), Callback(color, name)
		local silent = ...
		local color
		if typeof(v) == "Color3" then                                  -- a colour picks the preset with that colour
			color = v
			for _, item in ipairs(self.cfg.Items or {}) do if item[2] == v then v = item[1] break end end
		else
			for _, item in ipairs(self.cfg.Items or {}) do if item[1] == v then color = item[2] break end end
		end
		local changed = self.Value ~= v
		self.Value = v
		if self.Flag then L.Flags[self.Flag] = v end
		if not silent and changed and self.cfg.Callback and not self.Locked then
			local ok, err = pcall(self.cfg.Callback, color, v)
			if not ok then L.reported[#L.reported + 1] = { tag = "callback:" .. tostring(self.Title), err = err } end
		end
		return self
	end
	self.Value = v
	if self.Flag then L.Flags[self.Flag] = v end
	if self.cfg.Callback and not self.Locked then
		local ok, err = pcall(self.cfg.Callback, v, ...)
		if not ok then L.reported[#L.reported + 1] = { tag = "callback:" .. tostring(self.Title), err = err } end
	end
	for _, f in ipairs(self._changed) do f(v) end
	return self
end
function ElementMT:Get() return self.Value end
function ElementMT:OnChanged(f) self._changed[#self._changed + 1] = f end
function ElementMT:Lock(reason) self.Locked = true self.LockReason = reason end
function ElementMT:Unlock() self.Locked = false end
function ElementMT:SetItems(items) self.Items = items end
function ElementMT:Refresh(items) self.Items = items end
function ElementMT:SetDesc(t) self.Desc = t end
function ElementMT:SetTitle(t) self.Title = t end
function ElementMT:SetVisible(v) self.Visible = v ~= false end
function ElementMT:SetTileVisible(title, v) self.Hidden = self.Hidden or {} self.Hidden[tostring(title)] = v == false end
function ElementMT:SetVisible(v) self.Visible = v end
function ElementMT:Update(p) self.last = p end
function ElementMT:Append(t, kind) self.lines = self.lines or {} self.lines[#self.lines + 1] = t end
-- Button: press
function ElementMT:Press(arg)
	assert(self.Kind == "Button" or self.Kind == "ActionInput" or self.Kind == "ListItem", "Press: " .. self.Kind)
	if self.Locked then return false end
	local f = self.cfg.Callback
	if not f then return end
	local ok, err
	if self.cfg.Toggle then
		self.Value = not self.Value
		ok, err = pcall(f, self.Value)
	else
		ok, err = pcall(f, arg)
	end
	if not ok then error(err, 2) end
end

local Container = {}
local function newElement(card, kind, cfg)
	if type(cfg) == "string" then cfg = { Title = cfg } end
	cfg = cfg or {}
	local e = setmetatable({ Kind = kind, cfg = cfg, Title = cfg.Title, Flag = cfg.Flag, Value = cfg.Default, card = card, _changed = {},
		Items = cfg.Items, Desc = cfg.Desc, Visible = true }, ElementMT)
	if kind == "Toggle" and e.Value == nil then e.Value = false end
	if kind == "Button" and cfg.Toggle then e.Value = false end
	if cfg.Toggle and kind == "ListItem" and e.Value == nil then e.Value = false end
	local w = card.window
	if cfg.Flag then
		assert(not w.flagEls[cfg.Flag], "aynı Flag iki kez: " .. cfg.Flag)
		w.flagEls[cfg.Flag] = e
		w.flags[cfg.Flag] = e
		L.Flags[cfg.Flag] = e.Value
		if w.pending[cfg.Flag] ~= nil then local v = w.pending[cfg.Flag] w.pending[cfg.Flag] = nil e:Set(v) end
	end
	if cfg.Locked then e.Locked = true end
	-- elements a script draws into: a frame for Canvas, a frame + camera for Viewport
	-- a toggle with an inline slider: the slider is its own element (own flag)
	if kind == "Toggle" and type(cfg.Slider) == "table" then
		local sc = {}
		for k, v in pairs(cfg.Slider) do sc[k] = v end
		sc.Title = (cfg.Title or "") .. " amount"
		e.Slider = newElement(card, "Slider", sc)
	end
	if kind == "Canvas" then e.Frame = mock.newInstance("Frame") end
	if kind == "Viewport" then
		e.Frame = mock.newInstance("Frame")
		e.View = mock.newInstance("ViewportFrame")
		e.View.Parent = e.Frame
		e.Camera = mock.newInstance("Camera")
		e.Model = nil
		function e:SetObject(o) self.Value = o self.Model = o end
	end
	e.tab, e.page = card.tab, card.page
	e.Maid = { give = function(_, f) return f end }
	card.items[#card.items + 1] = e
	L.elements[#L.elements + 1] = e
	return e
end

local CardMT = {}
CardMT.__index = function(self, k)
	local v = rawget(CardMT, k)
	if v ~= nil then return v end
	return function(card, cfg) return newElement(card, k, cfg) end
end
local orderN = 0
local function newContainer(window, tab, page, cfg, parentCard)
	local body = mock.newInstance("Frame")
	local c = setmetatable({ window = window, tab = tab, page = page, cfg = cfg or {}, Title = cfg and cfg.Title, items = {}, children = {},
		body = body, parentCard = parentCard, frame = { LayoutOrder = 0 } }, CardMT)
	return c
end
function CardMT:_order() orderN = orderN + 1 return orderN end
function CardMT:Row(cfg) local r = newContainer(self.window, self.tab, self.page, { Title = self.Title }, self) r.Kind = "Row" self.children[#self.children + 1] = r return r end
function CardMT:Column(cfg) local r = newContainer(self.window, self.tab, self.page, { Title = self.Title }, self) r.Kind = "Column" self.children[#self.children + 1] = r return r end
function CardMT:Section(cfg) local r = newContainer(self.window, self.tab, self.page, cfg, self) r.Kind = "Section" self.children[#self.children + 1] = r return r end
function CardMT:Group(cfg) local r = newContainer(self.window, self.tab, self.page, cfg, self) r.Kind = "Group" self.children[#self.children + 1] = r return r end
function CardMT:Tabs(names)
	local out = {}
	for _, n in ipairs(names) do out[n] = self:Section({ Title = n }) end
	return out
end
function CardMT:HeaderSwitch(cfg) return newElement(self, "Toggle", cfg) end
-- a small header button: a Button element (press it with :Press() / its Callback)
function CardMT:HeaderButton(cfg) return newElement(self, "Button", cfg) end
function CardMT:Presets(list, cfg) return newElement(self, "Presets", { Items = list }) end
function CardMT:SetDesc(t) self.Desc = t end
-- runs callback every interval seconds (the fake is always on screen); returns the stop function
function CardMT:WhileVisible(interval, callback)
	local alive = true
	task.spawn(function()
		while alive and self.window.alive do
			callback()
			task.wait(interval)
		end
	end)
	return function() alive = false end
end
-- swatches + a picker that share the value (as Card:ColorChoice in the lib)
function CardMT:ColorChoice(cfg)
	local picker, dots, syncing
	local swatch, custom = {}, {}
	for k, v in pairs(cfg.Swatches or {}) do swatch[k] = v end
	for k, v in pairs(cfg.Picker or {}) do custom[k] = v end
	swatch.Callback = function(value) if picker and not syncing then picker:Set(value) end end
	dots = newElement(self, "Swatches", swatch)
	custom.Callback = function(value, alpha)
		syncing = true
		pcall(dots.Set, dots, value, true)
		syncing = false
		if cfg.Callback then cfg.Callback(value, alpha) end
	end
	picker = newElement(cfg.PickerCard or self, "ColorPicker", custom)
	return { Swatches = dots, Picker = picker }
end
function CardMT:SetTitle(t) self.Title = t end
function CardMT:SetVisible(v) self.Visible = v end
function CardMT:SetCollapsed(v) self.Collapsed = v end

local function newPage(window, tab, name, opts)
	local p = { window = window, tab = tab, Title = name, cards = {}, warnings = {} }
	function p:Card(cfg)
		local c = newContainer(window, tab, p, cfg)
		c.Kind = "Card"
		p.cards[#p.cards + 1] = c
		return c
	end
	function p:Warning(text, o) p.warnings[#p.warnings + 1] = text L.warnings[#L.warnings + 1] = text end
	function p:MatchHeights() end
	function p:FillColumn() end
	return p
end
local function newTab(window, cfg)
	local t = { window = window, Title = cfg.Title, Pages = {} }
	function t:Page(name, opts)
		local p = newPage(window, t, name, opts)
		t.Pages[#t.Pages + 1] = p
		return p
	end
	function t:Card(cfg2)
		if #t.Pages == 0 then t:Page("Main") end
		return t.Pages[1]:Card(cfg2)
	end
	function t:FitHeight() end                                    -- the lib sizes a card to its column; nothing to size here
	function t:SetBadge() end
	function t:SetActive() end
	function t:SetHidden() end
	function t:Select() end
	window.tabs[#window.tabs + 1] = t
	return t
end

function L:CreateWindow(cfg)
	local w = { cfg = cfg, tabs = {}, flags = {}, flagEls = {}, pending = {}, alive = true, kicks = {}, Flags = L.Flags }
	function w:Tab(c) return newTab(w, c) end
	function w:DashboardTab(c) w.dashboard = c return newTab(w, { Title = "Dashboard" }) end
	function w:SettingsTab() return newTab(w, { Title = "Settings" }) end
	function w:Notify(n) L.notifications[#L.notifications + 1] = n return { SetStep = noop, SetProgress = noop, Close = noop } end
	function w:Toast(n) L.notifications[#L.notifications + 1] = type(n) == "table" and n or { Title = n } end
	function w:SetModule(name, state, detail) L.modules[name] = state end
	function w:ReportError(tag, err, quiet, context) L.reported[#L.reported + 1] = { tag = tag, err = err, context = context } end
	function w:_safe(source, fn, ...)
		local ok, err = pcall(fn, ...)
		if not ok then w:ReportError(source, err) end
		return ok, err
	end
	w._tip, w._hideTip = noop, noop
	w.maid = { give = function(_, f) return f end }
	function w:SetFlag(flag, v)
		local e = w.flagEls[flag]
		if e then e:Set(v) else w.pending[flag] = v end
	end
	-- a flag with no row (Window:Value in the lib): kept as an element of Kind "Value" so tests can find and set it
	function w:Value(c)
		local e = setmetatable({ Kind = "Value", Flag = c.Flag, Title = c.Flag, Value = c.Default, cfg = c, items = {}, _changed = {} }, ElementMT)
		w.flagEls[c.Flag] = e
		w.flags[c.Flag] = e
		L.Flags[c.Flag] = c.Default
		L.elements[#L.elements + 1] = e
		if w.pending[c.Flag] ~= nil then local v = w.pending[c.Flag] w.pending[c.Flag] = nil e:Set(v) end
		return e
	end
	function w:GetElement(flag) return w.flagEls[flag] end
	w.GetFlag = w.GetElement
	function w:OnKick(f) w.kicks[#w.kicks + 1] = f end
	function w:Destroy()
		if not w.alive then return end
		w.alive = false
		if cfg.OnClose then cfg.OnClose() end
	end
	for _, m in ipairs({ "HeaderButton", "AddTag", "Dialog", "Confirm", "Watermark", "KeybindList", "SessionBar", "StatsMonitor", "KeyHint",
		"SetVisible", "Toggle", "Minimize", "SetFooter", "SetStatus", "SelectTab", "Tour", "Count", "SetUIScale" }) do
		w[m] = noop
	end
	w.Config = { LoadAutoLoad = noop, Save = noop, Load = noop, SetAutoLoad = noop, List = function() return {} end }
	L.windows[#L.windows + 1] = w
	L.window = w
	return w
end

-- the lib's Util / Theme / Icons parts (used by the server list)
L.Util = {
	create = function(class, props, children)
		local o = mock.newInstance(class)
		local parent
		for k, v in pairs(props or {}) do if k == "Parent" then parent = v else o[k] = v end end
		for _, c in ipairs(children or {}) do c.Parent = o end
		if parent then o.Parent = parent end
		return o
	end,
}
L.Util.corner = function(o, r) return L.Util.create("UICorner", { Parent = o }) end
L.Util.stroke = function(o) return L.Util.create("UIStroke", { Parent = o }) end
L.Util.padding = function(o) return L.Util.create("UIPadding", { Parent = o }) end
L.Util.list = function(o) return L.Util.create("UIListLayout", { Parent = o }) end
L.Util.label = function(parent, text, size, props)
	local l = L.Util.create("TextLabel", { Text = text, TextSize = size, Parent = parent })
	for k, v in pairs(props or {}) do l[k] = v end
	return l
end
L.Util.tween = noop
L.Util.textWidth = function(t, s) return #t * s * 0.55 end
L.Util.shown = function() return true end
L.Util.inView = function() return true end
L.Util.watchInView = function(_, callback) task.defer(function() callback(true) end) return function() end end
L.Util.Services = setmetatable({}, { __index = function(_, name) return mock.game:GetService(name) end })
-- per-frame work while on screen (the fake is always on screen): connects at once, returns stop, sync
L.Util.animateInView = function(_, signal, tick)
	local c = signal:Connect(function(dt) tick(dt or 1 / 60) end)
	return function() c:Disconnect() end, noop
end
L.Util.captureScroll = function() return { Sync = noop, Destroy = noop } end
L.Util.dependencyIcons = function() return noop end
L.Theme = { bind = noop, tweenTo = noop, get = function() return Color3.new(1, 1, 1) end }
L.Icons = { Image = function(name, o) return L.Util.create("ImageLabel", o or {}) end, Get = function() return "" end }

-- lookup helpers for tests
function L.find(title, kind, tabTitle)
	local found = {}
	for _, e in ipairs(L.elements) do
		if e.Title == title and (not kind or e.Kind == kind) and (not tabTitle or (e.tab and e.tab.Title == tabTitle)) then found[#found + 1] = e end
	end
	return found[1], #found
end
function L.flag(flag) return L.window.flagEls[flag] end
function L.tab(title) for _, t in ipairs(L.window.tabs) do if t.Title == title then return t end end end
function L.card(tabTitle, cardTitle)
	local t = L.tab(tabTitle)
	if not t then return nil end
	for _, p in ipairs(t.Pages) do for _, c in ipairs(p.cards) do if c.Title == cardTitle then return c end end end
end
-- every element title on a tab (including those inside Row / Section)
function L.titles(tabTitle)
	local out = {}
	for _, e in ipairs(L.elements) do if e.tab and e.tab.Title == tabTitle and e.Title then out[e.Title] = true end end
	return out
end
return L
