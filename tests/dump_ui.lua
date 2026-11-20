-- runs the setup part of run.lua and dumps the hub's UI as JSON (for rendering previews)
local W, L, mock = ...
local function esc(s) return (tostring(s):gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end)) end
local function enc(v)
	local t = type(v)
	if t == "table" then
		if v.__p or getmetatable(v) then return "null" end
		if #v > 0 or next(v) == nil then
			local o = {}
			for _, x in ipairs(v) do o[#o + 1] = enc(x) end
			return "[" .. table.concat(o, ",") .. "]"
		end
		local o = {}
		for k, x in pairs(v) do if type(k) == "string" and type(x) ~= "function" then o[#o + 1] = '"' .. esc(k) .. '":' .. enc(x) end end
		return "{" .. table.concat(o, ",") .. "}"
	elseif t == "string" then return '"' .. esc(v) .. '"'
	elseif t == "number" or t == "boolean" then return tostring(v)
	end
	return "null"
end
local function top(c) while rawget(c, "parentCard") do c = rawget(c, "parentCard") end return c end
local cardIds, out = {}, { tabs = {} }
for _, tab in ipairs(W.tabs) do
	local T = { title = tab.Title, pages = {} }
	for _, p in ipairs(tab.Pages) do
		local P = { title = p.Title, cards = {}, warnings = p.warnings }
		local sorted = {}
		for i, c in ipairs(p.cards) do sorted[i] = c end
		local pos = {}
		for i, c in ipairs(p.cards) do pos[c] = i end
		table.sort(sorted, function(a, b)
			local oa, ob = rawget(a, "frame").LayoutOrder, rawget(b, "frame").LayoutOrder
			if oa ~= ob then return oa < ob end
			return pos[a] < pos[b]
		end)
		for _, c in ipairs(sorted) do
			local C = { title = c.cfg.Title, icon = c.cfg.Icon, side = c.cfg.Side, wide = c.cfg.Wide, desc = rawget(c, "Desc") or c.cfg.Desc, items = {} }
			cardIds[c] = C
			P.cards[#P.cards + 1] = C
		end
		T.pages[#T.pages + 1] = P
	end
	out.tabs[#out.tabs + 1] = T
end
for _, e in ipairs(L.elements) do
	local C = cardIds[top(e.card)]
	if C then
		local cfg = {}
		for _, k in ipairs({ "Flag", "Title", "Desc", "Default", "Min", "Max", "Suffix", "Items", "Multi", "Style", "Icon", "Value", "Placeholder", "Content", "Bind" }) do
			local v = cfg[k] or e.cfg[k]
			if type(v) ~= "function" and type(v) ~= "userdata" then cfg[k] = v end
		end
		if type(e.cfg.Bind) ~= "nil" then cfg.Bind = tostring(e.cfg.Bind):gsub("Enum.KeyCode.", "") end
		if e.cfg.DependsOn then cfg.Dep = e.cfg.DependsOn.Flag cfg.DepHide = e.cfg.DependsOn.Mode == "Hide" end
		cfg.Kind = e.Kind
		cfg.Row = e.card ~= top(e.card) and tostring(e.card):match("0x%x+") or nil
		cfg.Cur = (type(e.Value) ~= "table" or not getmetatable(e.Value)) and e.Value or nil
		C.items[#C.items + 1] = cfg
	end
end
local f = assert(io.open(os.getenv("UI_DUMP"), "w"))
f:write(enc(out))
f:close()
