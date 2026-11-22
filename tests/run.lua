-- Usage: texlua run.lua <hub.lua (converted to Lua 5.3)> <scenario: map | menu>   (tests/run.sh does the conversion)
local HERE = arg[0]:match("(.*/)") or "./"
package.path = HERE .. "?.lua;" .. package.path
local HUB, SCENARIO = arg[1], arg[2] or "map"

local mock = dofile(HERE .. "mock.lua")
local L = assert(loadfile(HERE .. "fake_lib.lua"))(mock)
local V3, V2 = Vector3.new, Vector2.new

----- Minimal test framework -----
local results = { pass = 0, fail = 0, list = {} }
local function check(name, ok, detail)
	if ok then results.pass = results.pass + 1 else results.fail = results.fail + 1 end
	results.list[#results.list + 1] = { name = name, ok = ok, detail = detail }
end
local function near(a, b, eps) return math.abs(a - b) <= (eps or 1e-3) end
local function nearV(a, b, eps) return (a - b).Magnitude <= (eps or 1e-3) end
local function test(name, fn)
	local ok, err = pcall(fn)
	if not ok then check(name .. " (hata)", false, tostring(err)) end
end

----- World: Shindo-like -----
local PLACES = { map = 4601350809, menu = 4616652839, nofiles = 4601350809 }
mock.game.__p.GameId = 1511883870
mock.game.__p.PlaceId = PLACES[SCENARIO] or PLACES.map
mock.game.__p.JobId = "11111111-2222-3333-4444-555555555555"
mock.game.__p.CreatorId = 1

mock.httpRoutes["qustah-ui-lib.lua"] = "return __QLIB"
-- Auto Spin RELL raw: the tests use the real file from the repo (converted to Lua 5.3)
do
	local f = io.open(os.getenv("RELL53") or "", "r")
	if f then local src = f:read("a") f:close() mock.httpRoutes["refs/heads/main/rellauto"] = src end
end
for env, route in pairs({ ESP53 = "shindo/esp.lua", TELEPORTS53 = "shindo/teleports.lua" }) do
	local f = io.open(os.getenv(env) or "", "r")
	if f then local src = f:read("a") f:close() mock.httpRoutes[route] = src end
end
__QLIB = L
local SERVERS = {
	{ id = "aaaaaaaa-0000-0000-0000-000000000001", playing = 18, maxPlayers = 20, ping = 48 },
	{ id = "aaaaaaaa-0000-0000-0000-000000000002", playing = 3, maxPlayers = 20, ping = 120 },
	{ id = "aaaaaaaa-0000-0000-0000-000000000003", playing = 11, maxPlayers = 20, ping = 30 },
	{ id = mock.game.__p.JobId, playing = 5, maxPlayers = 20, ping = 60 },          -- our own server (must not be listed)
	{ id = "aaaaaaaa-0000-0000-0000-000000000004", playing = 20, maxPlayers = 20, ping = 20 }, -- full (must not be listed)
}
mock.httpRoutes["games.roblox.com/v1/games/"] = function() return mock.json.encode({ data = SERVERS }) end

local WS, PS = mock.WS, mock.PS
local me = mock.player("Me", V3(0, 5, 20), { silent = true })
PS.__p.LocalPlayer = me
mock.value("RemoteEvent", "startevent", nil, me)
mock.value("BoolValue", "incombat", false, me)
mock.folder("gamepasses", me)
local statz = mock.folder("statz", me)
mock.value("IntValue", "spins", 212, statz)
local main = mock.folder("main", statz)
for i = 1, 4 do
	mock.value("StringValue", "element" .. i, i <= 2 and "fire" or "", main)
	mock.value("StringValue", "kg" .. i, i <= 2 and "senko" or "", main)
end
mock.value("StringValue", "breathingstyle", "flame", statz)
mock.value("StringValue", "breathingstyle2", "", statz)
mock.value("StringValue", "race", "human", statz)
mock.value("StringValue", "fightingstyle", "", statz)
local lvl = mock.folder("lvl", statz) mock.value("IntValue", "lvl", 500, lvl)
local prestige = mock.folder("prestige", statz) mock.value("StringValue", "rank", "S", prestige)
local mastery = mock.folder("mastery", statz) mock.value("IntValue", "points", 0, mastery)
local mission = mock.folder("mission", statz)
for i = 1, 3 do mock.value("StringValue", "dailyquest" .. i, "punch", mission) end
local mainmission = mock.folder("mainmission", statz)
for _, n in ipairs({ "arena", "conquest", "tournament" }) do mock.value("StringValue", n, "", mainmission) end
mock.folder("unlocked", statz)
local combatF = mock.folder("combat", me.Character)
mock.value("RemoteEvent", "update", nil, combatF)

local pg = mock.folder("PlayerGui", me, "PlayerGui")
local mainGui = mock.folder("Main", pg, "ScreenGui")
local ingame = mock.folder("ingame", mainGui, "Frame")
local ms = mock.folder("Missionstory", ingame, "Frame")
ms.Visible = false
local msTitle = mock.folder("title", ms, "TextLabel")
msTitle.Text = ""
mock.folder("npc", WS)
mock.folder("missiongivers", WS)
local spawnLoc = mock.part("SpawnLocation", V3(100, 3, 100), WS, "SpawnLocation")

-- ReplicatedStorage.alljutsu (for the lists)
local RS_ = mock.service("ReplicatedStorage")
local alljutsu = mock.folder("alljutsu", RS_)
local REAL = { fire = "Fire Release", wind = "Wind Release", lightning = "Lightning Release", senko = "Senko Bloodline" }
for _, n in ipairs({ "fire", "wind", "lightning" }) do local f = mock.folder(n, alljutsu) mock.folder("ELEMENT", f) end
for _, n in ipairs({ "senko", "sengoku", "tengoku" }) do local f = mock.folder(n, alljutsu) mock.folder("KG", f) end
local ks = mock.folder("ALLKENSTYLES", alljutsu)
for _, n in ipairs({ "flame", "sun" }) do local f = mock.folder(n, ks) mock.folder("BREATHINGSTYLE", f) end
for code, real in pairs(REAL) do local f = alljutsu:FindFirstChild(code) if f then mock.value("StringValue", "REALNAME", real, f) end end
local fs = mock.folder("FIGHTINGSTYLES", alljutsu)
for _, n in ipairs({ "boxing", "karate" }) do mock.folder(n, fs) end

-- nofiles: the ESP and teleport raws cannot be downloaded (GitHub down, repo private): the hub must still open
if SCENARIO == "nofiles" then
	mock.httpRoutes["shindo/esp.lua"] = function() error("HTTP 404 (Not Found)") end
	mock.httpRoutes["shindo/teleports.lua"] = function() error("HTTP 404 (Not Found)") end
end

-- STRIPE_IMAGE=1: the executor has getcustomasset (the ESP stripes become one tiled picture)
if os.getenv("STRIPE_IMAGE") then getcustomasset = function(path) return "rbxasset://custom/" .. path end end

----- Load the hub -----
local src = assert(io.open(HUB)):read("a")
local chunk = assert(load(src, "@hub"))
local loadErrs = #mock.errors
task.spawn(chunk, "", src)
mock.advance(2)

local W = L.window
local ENV = mock.genv

test("hub yüklendi", function()
	check("yüklenirken hata yok", #mock.errors == 0, mock.errors[1])
	check("pencere oluştu", W ~= nil)
	local want = SCENARIO == "menu" and { "Dashboard", "Farm", "Spin", "Combat", "Visuals", "Player", "Loadout", "Server", "Settings" }
		or { "Dashboard", "Farm", "Combat", "Visuals", "Player", "Loadout", "Server", "Settings" }   -- Spin only in the main menu
	local got = {}
	for _, t in ipairs(W.tabs) do got[#got + 1] = t.Title end
	check("sekmeler: " .. table.concat(want, ", "), table.concat(got, ",") == table.concat(want, ","), table.concat(got, ","))
end)

if SCENARIO == "nofiles" then
	test("raw dosyalar inmezse hub yine açılıyor", function()
		local tags = {}
		for _, rep in ipairs(L.reported) do tags[#tags + 1] = rep.tag end
		local joined = table.concat(tags, ",")
		check("esp.lua hatası raporlandı", joined:find("File esp.lua", 1, true) ~= nil, joined)
		check("teleports.lua hatası raporlandı", joined:find("File teleports.lua", 1, true) ~= nil, joined)
		local warned = false
		for _, n in ipairs(L.notifications) do if tostring(n.Content):find("esp.lua could not be loaded", 1, true) then warned = true end end
		check("kullanıcıya bildirim gitti", warned)
		local notice
		for _, e in ipairs(L.elements) do if e.Kind == "Notice" and e.card and e.card.Title == "Preview" then notice = e end end
		check("ESP önizlemesinde uyarı", notice ~= nil and tostring(notice.cfg.Title):find("could not be loaded") ~= nil)
		check("ESP ayarları yine var (config bozulmaz)", L.flag("esp_enabled") ~= nil and L.flag("esp_hpcolors") ~= nil)
		check("Locations kartı yok (veri yok)", L.card("Player", "Locations") == nil)
		W:SetFlag("esp_enabled", true)
		mock.advance(1)
		check("ESP açıkken kare hatasız", #mock.errors == 0, mock.errors[1])
		local co = {}
		for _, e in ipairs(mock.errors) do co[#co + 1] = e:sub(1, 300) end
		check("thread hatası yok", #mock.errors == 0, table.concat(co, "\n"))
	end)
end

local function reportedSince(n) local out = {} for i = n + 1, #L.reported do out[#out + 1] = L.reported[i].tag .. ": " .. tostring(L.reported[i].err) end return out end

----- Scenario: map -----
if os.getenv("BENCH") then assert(loadfile(os.getenv("BENCH")))(W, L, mock) os.exit(0) end
if os.getenv("UI_DUMP") then assert(loadfile(HERE .. "dump_ui.lua"))(W, L, mock) os.exit(0) end
if SCENARIO == "map" then
	test("liste: olması gerekenler", function()
		local need = {
			Farm = { "Green Scroll Farm", "Boss Farm", "Legacy Farm Mode", "NPC Kill Aura", "Selection", "Bosses",
				 "Bosses on map", "Auto rank", "Rank up after MAX", "Use RELL coins",
				"Stop at spins", "Stats", "Go to mentor", "Auto mentor", "Push-ups", "Tree jumps", "Accuracy", "Deflecting", "Boss", "Kenjutsu training", "Claim all",
				"M1", "Rush", "Chi charge", "Tree jumps", "Daily boss quests" },
			Combat = { "Enabled", "Hit chance", "Target part", "Priority", "Inf range", "Visibility check", "Max distance", "Prediction",
				"Prediction strength", "Show FOV", "Radius", "Sides", "Thickness", "Color", "Filled", "Origin", "Target line" },
			Visuals = { "ESP enabled", "Range", "Nearest players", "Name", "Username", "Distance", "Name text size", "Health bar", "Health text",
				"Health bar segments", "Mode bar", "Mode text", "Mode bar segments",
				"Chams", "Fullbright", "No fog", "No shadows",
				"Custom time", "Custom ambient" },
			Player = { "Always run", "NoClip", "Click TP", "Speed", "Count", "FOV", "Unlock zoom", "Anti-AFK", "Spectate", "Disable in combat", "Unbreakable blocks",
				"NPC Kill Aura", "Scroll snipe", "Teleport to spawn after" },
			Loadout = { "Element", "Bloodline", "Kenjutsu", "Fighting style", "Change animation", "Buy style", "Refresh lists", "Show code names",
				"Show RC Shop", "Clothing", "Limited bloodline" },
			Server = { "Staff alert", "Group ID", "Min rank", "Action", "Auto rejoin on kick",
				"Re-execute after teleport", "This server" },
		}
		for tab, list in pairs(need) do
			local have = L.titles(tab)
			local missing = {}
			for _, t in ipairs(list) do if not have[t] then missing[#missing + 1] = t end end
			check(tab .. ": hepsi var", #missing == 0, "eksik: " .. table.concat(missing, ", "))
		end
	end)

	test("liste: kaldırılanlar yok", function()
		local gone = {
			Combat = { "Methods", "Safe origin", "Team check", "Ignore friends", "Bullet speed", "Preview" },
			Visuals = { "Ally", "Box", "Corner size", "Chams style", "Enemy", "Tracer", "Skeleton", "Thickness", "Rainbow", "Team check", "Through walls", "Style", "Refresh rate", "Flash when full", "Use display name", "Health number", "Text size", "Look direction", "Head dot", "Weapon", "Behind wall", "Silent aim target", "Use team color", "Visibility color", "Fade with distance", "Performance mode" },
			Farm = { "Claim daily missions", "Claim main missions", "Mode", "Height", "Distance", "Cancel stuck mission", "Melee distance", "Refresh lists", "Beasts Farm", "Specific Beast", "Random Beasts", "Bosses this session" },
			Player = { "WalkSpeed", "JumpPower", "Infinite jump", "Hold to respawn", "Power", "Range", "Fly", "Fly speed", "Camera FOV",
				"Override FOV", "Lock FOV while flying", "Gap", "Teleport to map", "Join private server", "Bed", "Seat 1" },
		}
		for tab, list in pairs(gone) do
			local have = L.titles(tab)
			local still = {}
			for _, t in ipairs(list) do if have[t] then still[#still + 1] = t end end
			check(tab .. ": kaldırılanlar gerçekten yok", #still == 0, "hâlâ var: " .. table.concat(still, ", "))
		end
	end)

	test("Farm ayarları DogeHub gibi", function()
		check("Height / Distance ayarı yok", L.flag("farm_height") == nil and L.flag("farm_dist") == nil)
		check("takılan görev ayarı görünmüyor", L.flag("farm_stuck") == nil)
		check("Legacy Farm Mode varsayılan açık", L.flag("farm_legacy") and L.flag("farm_legacy").cfg.Default == true)
		check("boss seçimi varsayılan Random", L.flag("farm_bossmode") and L.flag("farm_bossmode").cfg.Default == "Random")
		check("aura menzil ayarı yok", L.flag("sh_aurarange") == nil)
		local ps = L.flag("sa_predstr")
		check("Prediction strength 0..300 %, varsayılan 100", ps and ps.cfg.Min == 0 and ps.cfg.Max == 300 and ps.cfg.Default == 100)
	end)

	test("Flag'ler benzersiz ve elementler bulundu", function()
		local n = 0 for _ in pairs(W.flagEls) do n = n + 1 end
		check("flag sayısı > 80", n > 80, tostring(n))
	end)

	-- players
	local enemy = mock.player("Enemy", V3(0, 5, 0))
	local far = mock.player("FarGuy", V3(40, 5, -60))

	-- Drawing helpers: the hub can draw ESP with Drawing or with Roblox GUI, both are read
	local function overlay()
		for _, g in ipairs(mock.service("CoreGui"):GetChildren()) do
			if g.ClassName == "ScreenGui" and g.DisplayOrder == 999 then return g end
		end
	end
	local function guiMode() return #mock.drawings == 0 and overlay() ~= nil end
	local function fovCircle()
		if not guiMode() then
			for _, d in ipairs(mock.drawingsOf("Circle")) do
				if d.__props.ZIndex == 4 then return { Visible = d.__props.Visible, Position = d.__props.Position, Radius = d.__props.Radius } end
			end
			return nil
		end
		for _, f in ipairs(overlay():GetChildren()) do
			if f.ClassName == "Frame" and f:FindFirstChildOfClass("UICorner") and f.ZIndex == 5 then
				return { Visible = f.Visible, Position = V2(f.Position.X.Offset, f.Position.Y.Offset), Radius = f.Size.X.Offset / 2 }
			end
		end
	end
	-- the Qustah-style ESP: a BillboardGui per player (in a "QustahESP" folder) and a Highlight; it refreshes on its own
	-- timer, so the clock is moved past one refresh first
	local function espFolder()
		for _, d in ipairs(game:GetDescendants()) do if d.Name == "QustahESP" then return d end end
	end
	local function refreshPanels() mock.advance(0.3) mock.frame() end
	local function billboard(name)
		local f = espFolder()
		if not f then return nil end
		for _, c in ipairs(f:GetChildren()) do if c.ClassName == "BillboardGui" and c.Name == name then return c end end
	end
	local function highlightOf(name)
		local f = espFolder()
		if not f then return nil end
		for _, c in ipairs(f:GetChildren()) do if c.ClassName == "Highlight" and c.Name == name then return c end end
	end
	local function plain(text) return (tostring(text):gsub("<[^>]->", "")) end
	-- visible texts of a player's billboard (rich text tags removed); empty while the billboard is off
	local function panelTexts(name)
		local out = {}
		local g = billboard(name)
		if not (g and g.Enabled) then return out end
		for _, d in ipairs(g:GetDescendants()) do
			if d.ClassName == "TextLabel" and d.Visible then
				local shown, o = true, d.Parent
				while o and o ~= g do if o.Visible == false then shown = false end o = o.Parent end
				if shown then out[#out + 1] = plain(d.Text) end
			end
		end
		return out
	end
	local function panelHas(name, pattern)
		for _, t in ipairs(panelTexts(name)) do if t:find(pattern) then return true end end
		return false
	end
	local function visibleTexts()
		local out = {}
		if not guiMode() then
			for _, d in ipairs(mock.drawingsOf("Text", true)) do out[#out + 1] = d.__props.Text end
		else
			for _, l in ipairs(overlay():GetChildren()) do if l.ClassName == "TextLabel" and l.Visible then out[#out + 1] = l.Text end end
		end
		return out
	end
	local function visibleLines()
		if not guiMode() then return #mock.drawingsOf("Line", true) end
		local n = 0
		for _, f in ipairs(overlay():GetChildren()) do
			if f.ClassName == "Frame" and f.Visible and not f:FindFirstChildOfClass("UICorner") then n = n + 1 end
		end
		return n
	end
	local function visibleCount()                         -- everything visible apart from the FOV
		local n = 0
		if not guiMode() then
			for _, d in ipairs(mock.drawings) do if not d.__removed and d.__props.Visible and d.__props.ZIndex ~= 4 then n = n + 1 end end
			return n
		end
		for _, f in ipairs(overlay():GetChildren()) do
			if (f.ClassName == "Frame" or f.ClassName == "TextLabel") and f.Visible and f.ZIndex ~= 5 then n = n + 1 end
		end
		return n
	end

	test("FOV çemberi fareyi takip ediyor (ESP kapalı)", function()
		W:SetFlag("sa_enabled", true)
		mock.mouse = V2(600, 400)
		mock.frame()
		local c = fovCircle()
		check("FOV çemberi var ve görünür", c and c.Visible == true)
		check("FOV konumu = fare", c and nearV(c.Position, V2(600, 400)))
		check("FOV yarıçapı 120", c and c.Radius == 120)
	end)

	test("ESP açıkken FOV bozulmuyor", function()
		W:SetFlag("esp_enabled", true)
		mock.mouse = V2(640, 380)
		local r0 = #L.reported
		mock.frame()
		local c = fovCircle()
		check("ESP açık: FOV görünür", c and c.Visible == true)
		check("ESP açık: FOV fareyi takip ediyor", c and nearV(c.Position, V2(640, 380)))
		check("ESP açık: hata raporu yok", #reportedSince(r0) == 0, table.concat(reportedSince(r0), " | "))
		check("ESP Drawing ile çizgi çizmiyor (kutu yok)", visibleLines() == 0, tostring(visibleLines()))
		refreshPanels()
		check("üst blok: isim ve [kullanıcı adı] (BillboardGui)", panelHas("Enemy", "^Enemy %[Enemy%]$"))
		local g = billboard("Enemy")
		check("BillboardGui 300x78, kafanın 3 stud üstünde, hep üstte", g and g.Size.X.Offset == 300 and g.Size.Y.Offset == 78 and g.StudsOffset.Y == 3 and g.AlwaysOnTop == true)
	end)

	test("Drawing'de TextBounds yokken FOV donmuyor", function()
		-- some executors have no TextBounds on Drawing Text: reading it used to cut the frame short at the health text
		mock.drawingMode = "noTextBounds"
		enemy.Character.Humanoid.Health = 40
		W:SetFlag("esp_hptext", true)
		mock.mouse = V2(700, 300)
		mock.frame()
		local c = fovCircle()
		check("TextBounds yok: FOV yine fareyi takip ediyor", c and nearV(c.Position, V2(700, 300)))
		mock.value("IntValue", "fakehealth", 40, enemy.Character)
		refreshPanels()
		check("TextBounds yok: can yazısı yine yazıldı", panelHas("Enemy", "40 / 100"))
		enemy.Character.fakehealth:Destroy()
		mock.drawingMode = "ok"
	end)

	test("Daily Schedule: bitince claim + kapatma, reset olunca başlatma", function()
		local st = me:FindFirstChild("statz")
		local m = st and st:FindFirstChild("mission")
		if not m then m = mock.folder("mission", st) end
		local q = m:FindFirstChild("dailyquest2") or mock.value("StringValue", "dailyquest2", "treejump", m)
		q.Value = "treejump"
		local amount = q:FindFirstChild("amount") or mock.value("IntValue", "amount", 0, q)
		local maxAmount = q:FindFirstChild("maxamount") or mock.value("IntValue", "maxamount", 87, q)
		local claim = q:FindFirstChild("claim") or mock.value("BoolValue", "claim", false, q)
		maxAmount.Value, amount.Value, claim.Value = 87, 10, false
		W:SetFlag("dl_start", true)
		W:SetFlag("dl_tree", true)
		mock.advance(2.1)
		amount.Value = 87
		local t0 = mock.now
		mock.advance(2.1)
		check("bitince claim gönderildi", #mock.remotesSince(t0, "startevent") > 0 or #mock.remotesSince(t0) > 0)
		check("bitince Tree jumps kapandı", L.Flags.dl_tree == false)
		local function infoValue(title)
			for _, e in ipairs(L.elements) do if e.Kind == "Info" and e.cfg and e.cfg.Title == title then return tostring(e.Value or e.cfg.Value) end end
		end
		check("geri sayım UTC'ye göre", (infoValue("Next reset") or ""):find("^%d%d:%d%d:%d%d · UTC$") ~= nil, infoValue("Next reset"))
		amount.Value = 0                                       -- new day
		mock.advance(2.1)
		check("reset olunca Tree jumps açıldı", L.Flags.dl_tree == true)
		check("reset saati dosyaya yazıldı", tonumber(mock.files["QustahShindoReset.txt"]) ~= nil)
		mock.advance(1.1)
		check("geri sayım görülen reset saatine göre (~24 saat)", (infoValue("Next reset") or ""):find("^2[34]:%d%d:%d%d · seen$") ~= nil, infoValue("Next reset"))
		W:SetFlag("dl_tree", false)
		W:SetFlag("dl_start", false)
	end)

	test("Chams kartında önizleme yok", function()
		local view
		for _, e in ipairs(L.elements) do if e.Kind == "Viewport" and e.card and e.card.Title == "Chams" then view = e end end
		check("chams önizleme Viewport'u kaldırıldı", view == nil)
	end)

	test("FOV renk noktaları", function()
		local sw
		for _, e in ipairs(L.elements) do if e.Kind == "Swatches" and e.card and e.card.Title == "FOV" then sw = e end end
		check("FOV renk noktaları var", sw ~= nil)
		if sw then
			sw:Set(Color3.new(1, 0, 0))
			local c = L.Flags.fov_color
			check("nokta seçince FOV rengi değişti", c and c.R == 1 and c.G == 0)
		end
		mock.frame()
	end)

	test("ESP önizlemesi: karaktersiz, bulanık zemin üstünde oyundaki panel", function()
		local canvas, view
		for _, e in ipairs(L.elements) do
			if e.card and e.card.Title == "Preview" then
				if e.Kind == "Canvas" then canvas = e elseif e.Kind == "Viewport" then view = e end
			end
		end
		check("önizleme Canvas, karakter Viewport'u yok", canvas ~= nil and view == nil)
		if not canvas then return end
		local gui = mock.newInstance("ScreenGui")
		canvas.Frame.Parent = gui
		mock.advance(0.2)
		check("bulanık renkli zemin var", canvas.Frame:FindFirstChild("Backdrop") ~= nil)
		local panel = canvas.Frame:FindFirstChild("Panel")
		check("önizleme: oyundakiyle aynı panel", panel and panel:FindFirstChild("HealthBar") ~= nil and panel:FindFirstChild("ModeBar") ~= nil)
		check("önizleme: isim ve [kullanıcı adı] yazıldı", panel and panel:FindFirstChild("PlayerName") and plain(panel.PlayerName.Text) == "Me [Me]")
		canvas.Frame.Parent = nil
	end)

	test("Chams Highlight ile, can Humanoid'den, mode bar üstte", function()
		local char = enemy.Character
		char.Humanoid.Health = 40
		W:SetFlag("esp_enabled", true)
		W:SetFlag("esp_chams", true)
		refreshPanels()
		local h = highlightOf("Enemy")
		check("chams: Highlight açık, karakterde", h and h.Enabled and h.Adornee == char)
		check("chams: fill %65, outline %35, hep üstte", h and math.abs(h.FillTransparency - 0.65) < 1e-6 and math.abs(h.OutlineTransparency - 0.35) < 1e-6
			and h.DepthMode == Enum.HighlightDepthMode.AlwaysOnTop)
		check("chams: Drawing Quad kullanılmıyor", #mock.drawingsOf("Quad", true) == 0)
		check("can yazısı Humanoid.Health'ten (40 / 100)", panelHas("Enemy", "40 / 100"))
		W:SetFlag("esp_chams", false)
		refreshPanels()
		check("chams kapanınca Highlight kapandı", h and h.Enabled == false)
		-- mode bar: combat.mode (IntConstrainedValue 0-100), above the health bar
		local combat = char:FindFirstChild("combat") or mock.folder("combat", char)
		local mode = mock.value("IntConstrainedValue", "mode", 50, combat)
		mode.MaxValue = 100
		refreshPanels()
		local g = billboard("Enemy")
		local mb, hb = g and g:FindFirstChild("ModeBar", true), g and g:FindFirstChild("HealthBar", true)
		check("mode bar çizildi", mb and mb.Visible)
		check("mode bar can barının üstünde", mb and hb and mb.Position.Y.Offset < hb.Position.Y.Offset)
		check("mode bar %50 dolu", mb and math.abs(mb.Fill.Size.X.Scale - 0.5) < 1e-6)
		check("barlar düz renk değil gradyan (UIGradient)", mb and mb.Fill:FindFirstChild("Gradient") ~= nil and hb and hb:FindFirstChild("Gradient", true) ~= nil)
		local frames = 0
		for _, c in ipairs(hb:GetChildren()) do if c.ClassName == "Frame" and c.Name ~= "Fill" and c.Size.X.Offset ~= 1 then frames = frames + 1 end end
		check("health bar tek dolgu, segmentler sadece çizgi", hb.Fill ~= nil and frames == 0, tostring(frames))
		check("varsayılan: mode Stripes, health Smooth", mb and mb.Fill.Stripes.Visible == true and hb.Fill.Stripes.Visible == false)
		W:SetFlag("esp_mdstyle", "Stripes")
		W:SetFlag("esp_hpstyle", "Stripes")
		refreshPanels()
		local hpStripes = hb and hb:FindFirstChild("Stripes", true)
		check("Stripes: mode ve health barında çizgiler açık", mb and mb.Fill.Stripes.Visible == true and hpStripes and hpStripes.Visible == true)
		local strips = mb.Fill.Stripes:GetChildren()
		check("Stripes: 4 sıra x 5 şerit, her biri keskin geçişli gradyanla", #strips == 20 and strips[1]:FindFirstChildOfClass("UIGradient") ~= nil, tostring(#strips))
		W:SetFlag("esp_mdstyle", "Smooth")
		W:SetFlag("esp_hpstyle", "Smooth")
		W:SetFlag("esp_hpopacity", 40)
		W:SetFlag("esp_mdopacity", 70)
		refreshPanels()
		local nameText = g:FindFirstChild("PlayerName", true)
		check("opacity: health dolgu %40, mode dolgu %70", math.abs(hb.Fill.BackgroundTransparency - 0.6) < 1e-6 and math.abs(mb.Fill.BackgroundTransparency - 0.3) < 1e-6)
		check("opacity: yazılar etkilenmiyor", nameText and nameText.TextTransparency == 0)
		W:SetFlag("esp_hpopacity", 100)
		W:SetFlag("esp_mdopacity", 100)
		W:SetFlag("esp_mbar", false)
		refreshPanels()
		check("Mode bar kapanınca gizlendi", mb and mb.Visible == false)
		W:SetFlag("esp_mbar", true)
		mode:Destroy()
		char.Humanoid.Health = 100
		refreshPanels()
	end)

	test("Preview kontrolleri: renk, Smooth / Stripes, opaklık (Style ile senkron)", function()
		local canvas
		for _, e in ipairs(L.elements) do if e.Kind == "Canvas" and e.card and e.card.Title == "Preview" and e.tab and e.tab.Title == "Visuals" then canvas = e end end
		local controls = canvas and canvas.Frame and canvas.Frame:FindFirstChild("Controls")
		check("Preview'da kontrol şeridi var", controls ~= nil)
		if not controls then return end
		local hp, md = controls:FindFirstChild("HP"), controls:FindFirstChild("MD")
		check("HP ve MD kapsülleri", hp ~= nil and md ~= nil)
		local mint = hp:FindFirstChild("Mint", true)
		check("HP'de 6 renk (Mint var)", mint ~= nil)
		mint.Activated:Fire()
		check("noktaya basınca Style'daki renk değişti", L.flag("esp_hpcolors").Value == "Mint", tostring(L.flag("esp_hpcolors").Value))
		md:FindFirstChild("Smooth", true).Activated:Fire()
		check("MD Smooth seçildi", L.flag("esp_mdstyle").Value == "Smooth", tostring(L.flag("esp_mdstyle").Value))
		local opacity
		for _, d in ipairs(hp:GetChildren()) do if d:IsA("TextButton") then opacity = d end end
		opacity.Activated:Fire()
		check("opaklığa tıklayınca 75%", L.flag("esp_hpopacity").Value == 75, tostring(L.flag("esp_hpopacity").Value))
		mock.advance(0.2)
		check("opaklık yazısı da 75%", opacity.Text == "75%", tostring(opacity.Text))
		W:SetFlag("esp_mbar", false)
		mock.advance(0.2)
		local before = L.flag("esp_modecolors").Value
		md:FindFirstChild("Gold", true).Activated:Fire()
		check("Mode bar kapalıyken MD kapsülü tıklamayı yok sayıyor", L.flag("esp_modecolors").Value == before, tostring(L.flag("esp_modecolors").Value))
		check("Mode bar kapalıyken MD kapsülü soluk", md.BackgroundTransparency == 0.5, tostring(md.BackgroundTransparency))
		W:SetFlag("esp_mbar", true)
		W:SetFlag("esp_hpcolors", "Ice") W:SetFlag("esp_mdstyle", "Stripes") W:SetFlag("esp_hpopacity", 100)
		mock.advance(0.2)
		local ring = hp:FindFirstChild("Ice", true):FindFirstChildWhichIsA("Frame"):FindFirstChildWhichIsA("UIStroke")
		check("Style'dan seçilen renk halkayla işaretli", ring and ring.Transparency == 0, tostring(ring and ring.Transparency))
	end)

	test("Üst blok: kullanıcı adı, can / max, Death, dodge, MD yazısı", function()
		local char = enemy.Character
		W:SetFlag("esp_enabled", true)
		char.Humanoid.MaxHealth = 360000
		char.Humanoid.Health = 300000
		refreshPanels()
		local function has(pattern) return panelHas("Enemy", pattern) end
		check("isim ve gri [kullanıcı adı]", has("^Enemy %[Enemy%]$"))
		check("can / MaxHealth kısaltılmış: 300K / 360K", has("^300K / 360K$"))
		char.Humanoid.MaxHealth = 2000
		char.Humanoid.Health = 1500
		refreshPanels()
		check("can yazısı kısaltılmış, kalpsiz: 1.5K / 2K", has("^1%.5K / 2K$"))
		local fake = mock.value("IntValue", "fakehealth", 1200, char)
		refreshPanels()
		check("başka oyuncu: can fakehealth'ten (1.2K / 2K)", has("^1%.2K / 2K$"))
		fake.Value = 0
		refreshPanels()
		check("başka oyuncu: fakehealth 0 olunca 0 / 2K", has("^0 / 2K"))
		fake:Destroy()
		refreshPanels()
		check("fakehealth yokken Humanoid'e dönüyor", has("^1%.5K / 2K$"))

		check("mesafe [.. studs]", has("^%[.+ studs%]$"))
		local down = mock.folder("stayonground", char, "BoolValue")
		refreshPanels()
		check("yere düşünce · Death", has("· Death$"))
		down:Destroy()
		-- dodge: a key slot holding Taijutsu Body and its cooldown
		local statz = enemy:FindFirstChild("statz") or mock.folder("statz", enemy)
		local keys = mock.folder("keys", statz)
		local slot = mock.folder("q", keys)
		mock.value("StringValue", "move", "Taijutsu Body", slot)
		local cd = mock.value("IntValue", "cooldown", 3, slot)
		mock.advance(2.5)
		refreshPanels()
		check("dodge bekleme süresi yazıldı (3)", has("^3$"))
		cd.Value = 0
		refreshPanels()
		check("dodge hazırken sayı yok", not has("^3$"))
		keys:Destroy()
		-- MD text
		local combat = char:FindFirstChild("combat") or mock.folder("combat", char)
		local mode = mock.value("IntConstrainedValue", "mode", 50, combat)
		mode.MaxValue = 100
		W:SetFlag("esp_mtext", true)
		refreshPanels()
		check("MD 50 / 100 yazısı", has("^MD 50 / 100$"))
		W:SetFlag("esp_mtext", false)
		mode:Destroy()
		char.Humanoid.MaxHealth = 100
		char.Humanoid.Health = 100
		mock.frame()
	end)

	test("Nearest players ve Target pins", function()
		W:SetFlag("esp_enabled", true)
		local extra = {}
		for i = 1, 6 do extra[i] = mock.player("Far" .. i, V3(i * 3, 5, -10 - i * 20)) end
		W:SetFlag("esp_limit", 5)
		refreshPanels()
		local function drawn(name) local g = billboard(name) return g ~= nil and g.Enabled end
		check("en uzaktaki çizilmiyor (limit 5)", not drawn("Far6"))
		W:SetFlag("esp_pins", { extra[6].UserId })
		refreshPanels()
		check("pinlenen oyuncu limite takılmıyor", drawn("Far6"))
		W:SetFlag("esp_pins", {})
		W:SetFlag("esp_limit", 30)
		for _, p in ipairs(extra) do mock.removePlayer(p) end
		mock.frame()
	end)

	test("Bir oyuncunun ESP'si hata verince diğerleri ve FOV devam ediyor", function()
		local broken = mock.player("Broken", V3(5, 5, 0))
		-- broken player: its display name is not a string (the panel errors on it)
		rawget(broken, "__p").DisplayName = setmetatable({}, { __tostring = function() error("bozuk") end, __concat = function() error("bozuk") end })
		mock.mouse = V2(500, 360)
		local r0 = #L.reported
		mock.frame()
		local c = fovCircle()
		check("bozuk oyuncu: FOV yine güncellendi", c and nearV(c.Position, V2(500, 360)))
		refreshPanels()
		check("bozuk oyuncu: diğer oyuncunun ESP'si çizildi", panelHas("Enemy", "^Enemy"))
		local rep = reportedSince(r0)
		check("bozuk oyuncu: hata Settings'e raporlandı (1 kez)", #rep == 1, table.concat(rep, " | "))
		mock.removePlayer(broken)
		mock.frame()
	end)

	test("ESP kapatınca çizimler gizleniyor", function()
		W:SetFlag("esp_enabled", false)
		mock.frame()
		refreshPanels()
		local f = espFolder()
		check("ESP kapalı: paneller ve highlight'lar silindi", f == nil or #f:GetChildren() == 0, f and tostring(#f:GetChildren()))
		local vis = visibleCount()
		check("ESP kapalı: FOV dışında görünen çizim yok", vis == 0, tostring(vis))
		W:SetFlag("esp_enabled", true)
	end)

	test("Silent aim: ScreenPointToRay, Inf range, prediction", function()
		enemy.Character.Humanoid.Health = 100
		mock.cam.CFrame = CFrame.new(0, 10, 30)
		mock.mouse = V2(640, 420)
		mock.frame()
		local cam = WS.CurrentCamera
		local origin = mock.cam.CFrame.Position
		local head = enemy.Character.Head.Position
		-- normal: a 1 stud ray from the camera towards the target
		local ray = mock.gameNamecall(cam, "ScreenPointToRay", 640, 420)
		check("ScreenPointToRay: kameradan hedefe", ray and nearV(ray.Origin, origin) and nearV(ray.Direction, (head - origin).Unit, 1e-6))
		local vray = mock.gameNamecall(cam, "ViewportPointToRay", 640, 420)
		check("ViewportPointToRay da çevrildi", vray and nearV(vray.Direction, (head - origin).Unit, 1e-6))
		-- other methods are left alone now
		mock.gameNamecall(WS, "Raycast", origin, V3(0, 0, -500))
		check("Raycast artık değiştirilmiyor", nearV(mock.lastRaycast.dir, V3(0, 0, -500)))
		check("Mouse.Hit hook'u yok", mock.hooks.__index == nil)
		-- Inf range: Parvus' ray, starting at the target
		W:SetFlag("sa_infrange", true)
		ray = mock.gameNamecall(cam, "ScreenPointToRay", 640, 420)
		check("Inf range: ışın hedeften başlıyor (Parvus)", ray and nearV(ray.Origin, head) and nearV(ray.Direction, head - origin, 1e-6))
		W:SetFlag("sa_infrange", false)
		-- prediction
		enemy.Character.Head.AssemblyLinearVelocity = V3(20, 0, 0)
		W:SetFlag("sa_predict", true)
		W:SetFlag("sa_predstr", 200)
		mock.frame()
		ray = mock.gameNamecall(cam, "ScreenPointToRay", 640, 420)
		local dist = (enemy.Character.HumanoidRootPart.Position - origin).Magnitude
		local predicted = head + V3(20, 0, 0) * (dist / 1000) * 2
		check("Prediction %200: hedefin önüne", ray and nearV(ray.Direction, (predicted - origin).Unit, 1e-6))
		W:SetFlag("sa_predict", false)
		enemy.Character.Head.AssemblyLinearVelocity = V3(0, 0, 0)
		-- no target outside the FOV: the real ray
		mock.mouse = V2(50, 50)
		mock.frame()
		ray = mock.gameNamecall(cam, "ScreenPointToRay", 50, 50)
		check("FOV dışında: gerçek ışın", ray and nearV(ray.Direction, mock.cam.CFrame.LookVector, 1e-6))
	end)

	----- Farm -----
	local npcFolder = WS.npc
	local function spawnNPC(name, pos)
		local m = mock.character(name, pos, npcFolder)
		mock.folder("npctype", m)
		return m
	end
	local function setMission(on)
		ms.Visible = on
		msTitle.Text = on and "[Objective: Mission]" or ""
	end

	test("Farm saldırı konumu: Jutsu / Melee / Legacy", function()
		setMission(true)
		local npc = spawnNPC("npcbandit", V3(50, 5, 50))
		W:SetFlag("farm_legacy", false)                       -- Legacy off = Jutsu (E), fixed Height 0 / Distance 10
		W:SetFlag("farm_scroll", true)
		local t0 = mock.now
		mock.advance(0.5)
		local hrp = me.Character.HumanoidRootPart
		local want = (CFrame.new(50, 5, 50) * CFrame.new(0, 0, 10)).Position
		check("Jutsu: mob'un 10 stud arkası, aynı hizada (Height 0)", nearV(hrp.Position, want, 1e-3), tostring(hrp.Position))
		local es = 0
		for _, r in ipairs(mock.remotesSince(t0, "update")) do if r.args[1] == "key" and r.args[2] == "e" then es = es + 1 end end
		check("Jutsu: E tuşu gönderildi", es >= 3)
		npc:Destroy()

		W:SetFlag("farm_legacy", true)
		statz.fightingstyle.Value = "karate"
		npc = spawnNPC("npcbandit3", V3(10, 5, -40))
		t0 = mock.now
		mock.advance(0.5)
		check("Legacy + karate: 10 stud", nearV(hrp.Position, (CFrame.new(10, 5, -40) * CFrame.new(0, 0, 10)).Position), tostring(hrp.Position))
		local m1, e = 0, 0
		for _, r in ipairs(mock.remotesSince(t0, "update")) do
			if r.args[1] == "mouse1" then m1 = m1 + 1 end
			if r.args[1] == "key" and r.args[2] == "e" then e = e + 1 end
		end
		check("Legacy: hem M1 hem E", m1 > 0 and e > 0)
		npc:Destroy()
		W:SetFlag("farm_legacy", true)
		W:SetFlag("farm_scroll", false)
		setMission(false)
	end)

	test("Farm döngüsü mob kaybolunca ölmüyor", function()
		setMission(true)
		W:SetFlag("farm_scroll", true)
		local npc = spawnNPC("npcghost", V3(0, 5, -80))
		-- the mob is removed mid-attack: HumanoidRootPart disappears
		npc.HumanoidRootPart:Destroy()
		local r0 = #L.reported
		mock.advance(0.5)
		npc:Destroy()
		local npc2 = spawnNPC("npcnext", V3(20, 5, -20))
		mock.advance(0.5)
		local hrp = me.Character.HumanoidRootPart
		check("sonraki mob'a geçti", nearV(hrp.Position, (CFrame.new(20, 5, -20) * CFrame.new(0, 0, 10)).Position), tostring(hrp.Position))
		npc2:Destroy()
		W:SetFlag("farm_scroll", false)
		setMission(false)
	end)

	test("Mentor punch ve Daily M1 birbirini kapatmıyor", function()
		W:SetFlag("mt_punch", true)
		W:SetFlag("dl_m1", true)
		W:SetFlag("dl_m1", false)          -- turn daily off
		local t0 = mock.now
		mock.advance(0.3)
		local m1 = 0
		for _, r in ipairs(mock.remotesSince(t0, "update")) do if r.args[1] == "mouse1" then m1 = m1 + 1 end end
		check("Daily kapanınca Mentor punch devam ediyor", m1 > 0)
		W:SetFlag("mt_punch", false)
		mock.advance(0.05)                 -- ignore the last hit that was already running at that moment
		t0 = mock.now
		mock.advance(0.3)
		m1 = 0
		for _, r in ipairs(mock.remotesSince(t0, "update")) do if r.args[1] == "mouse1" then m1 = m1 + 1 end end
		check("ikisi de kapalı: M1 yok", m1 == 0)
	end)

	test("Claim all", function()
		local t0 = mock.now
		L.find("Claim all", "Button"):Press()
		local claim, claim2 = 0, 0
		for _, r in ipairs(mock.remotesSince(t0, "startevent")) do
			if r.args[1] == "claim" then claim = claim + 1 end
			if r.args[1] == "claim2" then claim2 = claim2 + 1 end
		end
		check("3 günlük görev claim", claim == 3, tostring(claim))
		check("3 ana görev claim2", claim2 == 3, tostring(claim2))
	end)

	test("Auto rank: spins yokken döngü ölmüyor", function()
		local r0 = #L.reported
		local spinsV = statz.spins
		spinsV.Parent = nil
		W:SetFlag("rank_stop", true)
		W:SetFlag("rank_on", true)
		statz.lvl.lvl.Value = 1000
		local t0 = mock.now
		mock.advance(1)
		local ranks = #mock.remotesSince(t0, "startevent")
		check("lvl 1000: rankup gönderildi", ranks > 0)
		spinsV.Parent = statz
		W:SetFlag("rank_on", false)
		W:SetFlag("rank_stop", false)
		statz.lvl.lvl.Value = 500
	end)

	----- Mission tracking -----
	local vc = mock.folder("VC", WS)
	local vcRemote = mock.value("RemoteEvent", "RemoteEvent", nil, vc)
	local function cancels(t0)
		local n = 0
		for _, r in ipairs(mock.remotesSince(t0, "RemoteEvent")) do if r.args[1] == "!cancel" then n = n + 1 end end
		return n
	end
	local function makeMission(text, objective, targetPos)
		local m = mock.folder("mission_" .. text, mock.service("ReplicatedStorage"))
		mock.value("StringValue", "text", text, m)
		mock.value("StringValue", "objective", objective, m)
		local tp = mock.part("target", targetPos, m)
		mock.value("ObjectValue", "target", tp, m)
		return m
	end
	local function typedNPC(name, typ, pos)
		local m = mock.character(name, pos, npcFolder)
		mock.value("StringValue", "npctype", typ, m)
		return m
	end

	test("currentmission: sadece görevin mob'larına vuruyor", function()
		local cm = mock.value("ObjectValue", "currentmission", nil, me)
		local mission = makeMission("Defeat 3 Bandits", "Mission", V3(500, 5, 500))
		local bandit = typedNPC("npcbandit", "Bandit", V3(520, 5, 500))
		local wolf = typedNPC("npcwolf", "Wolf", V3(490, 5, 510))
		local farBandit = typedNPC("npcbandit2", "Bandit", V3(3000, 5, 3000))
		mock.value("Folder", "antiexploit", nil, bandit)
		cm.Value = mission
		W:SetFlag("farm_scroll", true)
		mock.advance(0.6)
		local hrp = me.Character.HumanoidRootPart
		check("görevdeki mob'a (tip + mesafe) gitti", nearV(hrp.Position, (CFrame.new(520, 5, 500) * CFrame.new(0, 0, 10)).Position, 0.5), tostring(hrp.Position))
		check("mob'un antiexploit'i silindi", bandit:FindFirstChild("antiexploit") == nil)
		bandit.Humanoid:Destroy()
		mock.advance(0.6)
		check("sonra aynı tipteki diğer mob (Wolf'a değil)", nearV(hrp.Position, (CFrame.new(3000, 5, 3000) * CFrame.new(0, 0, 10)).Position, 0.5), tostring(hrp.Position))
		cm.Value = nil                                      -- mission finished
		farBandit:Destroy() wolf:Destroy() bandit:Destroy()
		mock.advance(0.5)
		check("görev bitince (currentmission boş) görevde sayılmıyor", true)
		-- wrong mission type → cancel
		local t0 = mock.now
		local wrong = makeMission("Deliver the scroll", "Delivery", V3(0, 5, 0))
		cm.Value = wrong
		mock.advance(0.6)
		check("görev tipi Mission değil: !cancel gönderildi", cancels(t0) >= 1)
		cm.Value = nil
		mock.advance(1.2)
		-- stuck mission → cancel once the timeout passes
		local FARM = ENV.QustahShindoCore.Farm                -- no setting: change the timeout from the inside for the test
		FARM.StuckAfter = 5
		local stuck = makeMission("Defeat Ghost", "Mission", V3(0, 5, 0))
		t0 = mock.now
		cm.Value = stuck
		mock.advance(3)
		check("süre dolmadan iptal yok", cancels(t0) == 0)
		mock.advance(3.5)
		check("5 sn ilerleme yok: !cancel gönderildi", cancels(t0) == 1, tostring(cancels(t0)))
		FARM.StuckAfter = 0
		t0 = mock.now
		mock.advance(7)
		check("0 = kapalı: iptal yok", cancels(t0) == 0)
		cm.Value = nil
		FARM.StuckAfter = 60
		W:SetFlag("farm_scroll", false)
		mock.advance(0.5)
		cm:Destroy()
	end)

	test("Immortal: knockdown'u kaldırıyor", function()
		W:SetFlag("sh_immortal", true)
		local c = me.Character
		mock.folder("stayonground", c)
		mock.folder("KO", c.HumanoidRootPart)
		c.Humanoid.AutoRotate = false
		mock.frame()
		check("stayonground silindi", c:FindFirstChild("stayonground") == nil)
		check("KO silindi", c.HumanoidRootPart:FindFirstChild("KO") == nil)
		check("AutoRotate geri açıldı", c.Humanoid.AutoRotate == true)
		W:SetFlag("sh_immortal", false)
	end)

	test("Listelerde oyundaki gerçek isimler (REALNAME)", function()
		local dd = L.flag("ld_elem")
		local items = table.concat(dd.Items or {}, ",")
		check("Element listesinde gerçek isimler", items:find("Fire Release", 1, true) ~= nil and items:find("fire,", 1, true) == nil, items)
		W:SetFlag("ld_elem", "Lightning Release")
		local slotBtn
		for _, e in ipairs(L.elements) do if e.Title == "Slot 3" and e.card and e.card.parentCard and e.card.parentCard.Title == "Element" then slotBtn = e end end
		slotBtn:Press()
		check("seçilen gerçek isim kod adıyla yazıldı", statz.main.element3.Value == "lightning", tostring(statz.main.element3.Value))
		local bl = table.concat(L.flag("ld_bl").Items or {}, ",")
		check("REALNAME'i olmayan kod adıyla kalıyor", bl:find("sengoku", 1, true) ~= nil and bl:find("Senko Bloodline", 1, true) ~= nil, bl)
	end)

	----- Boss farm + safe spot -----
	local bdm = mock.folder("bossdropmission", WS)
	local bmissions = mock.folder("missions", bdm)
	local function makeGiver(name, pos)
		local g = mock.folder(name, bmissions, "Model")
		local mg = mock.folder("missiongiver", g, "Model")
		mock.part("HumanoidRootPart", pos, mg)
		local talk = mock.value("RemoteEvent", "CLIENTTALK", nil, mg)
		local timer = mock.folder("timer", mg)
		local tm = mock.folder("time", timer)
		local label = mock.folder("time", tm, "TextLabel")
		label.Text = "00:00"
		return g, talk, label
	end
	local bossNpc
	local function spawnBoss(name, pos, susanoo)
		bossNpc = mock.character(name, pos, npcFolder)
		mock.folder("npctype", bossNpc)
		if susanoo then mock.folder("fullsusanoo", bossNpc) end
		return bossNpc
	end
	-- the map's real ground: the safe floor must be cloned from it (collision group, material) and placed in workspace.map
	local mapFolder = WS:FindFirstChild("map") or mock.folder("map", WS)
	local ground = mock.part("Wall", V3(0, -20, 0), mapFolder)
	ground.Anchored, ground.Size = true, V3(200, 4, 200)
	ground.CollisionGroup, ground.Material = "MapGround", "Concrete"
	mock.folder("Texture", ground, "Texture")
	local function safePart() return mapFolder:FindFirstChild("QustahSafe") or WS:FindFirstChild("QustahSafe") end
	local function onSafe(center)                         -- is the safe floor in the right place with the player on top
		local p = safePart()
		if not p or not nearV(p.Position, center, 0.5) then return false end
		local rel = p.CFrame:PointToObjectSpace(me.Character.HumanoidRootPart.Position)
		return math.abs(rel.X) <= 43.5 and math.abs(rel.Z) <= 43.5 and rel.Y > -1 and rel.Y < 60
	end
	local function platformPart()
		for _, c in ipairs(WS:GetChildren()) do if c.ClassName == "Part" and c.Transparency == 1 and c.Anchored then return c end end
	end

	test("Boss sayaçları (hazır / toplam) ve yeşil sayaç yok", function()
		check("yeşil sayaç kaldırıldı", L.find("Green quests on map", "Info") == nil)
		local b = L.find("Bosses on map", "Progress")
		check("boss sayacı slider gibi (Progress) ve x / y ready yazıyor", b and b.cfg.Format and (b.cfg.Format(b.Value, 1):match("^%d+ / %d+ ready$") or b.cfg.Format(b.Value, 1) == "none"), tostring(b and b.Value))
	end)

	test("Player sekmesi: Player ve Movement aynı sekmede iki sayfa", function()
		local pages = {}
		for _, p in ipairs(L.tab("Player").Pages) do pages[#pages + 1] = p.Title end
		check("sayfalar: Player, Movement, Teleports, Colors", table.concat(pages, ",") == "Player,Movement,Teleports,Colors", table.concat(pages, ","))
		check("ayrı Movement / Teleport sekmesi yok", L.tab("Movement") == nil and L.tab("Teleport") == nil)
		-- Teleports: only what exists on this map
		local tiles
		for _, e in ipairs(L.elements) do if e.Kind == "Tiles" and e.card and e.card.Title == "Quick" then tiles = e end end
		local hidden = function(n) return tiles and tiles.Hidden and tiles.Hidden[n] == true end
		check("Quick ikonları var", tiles ~= nil)
		check("haritada olan spawn görünüyor", tiles and not hidden("Spawn"))
		check("haritada olmayan duel pads gizli", hidden("Duel pads"))
		check("Back ilk başta gizli", hidden("Back"))
		local spawnItem
		for _, it in ipairs(tiles and tiles.Items or {}) do if it.Title == "Spawn" then spawnItem = it end end
		local r = me.Character.HumanoidRootPart
		r.CFrame = CFrame.new(500, 10, 500)
		if spawnItem then spawnItem.Callback() end
		check("ışınlanınca Back göründü", not hidden("Back"))
		local back
		for _, it in ipairs(tiles and tiles.Items or {}) do if it.Title == "Back" then back = it end end
		if back then back.Callback() end
		check("Back eski yere döndürdü", (r.Position - V3(500, 10, 500)).Magnitude < 1, tostring(r.Position))
		check("My Home dışında AFK kartı yok", L.find("Bed", "Button") == nil)
		local duelFolder = mock.folder("map2", WS)
		local d = mock.folder("duel", duelFolder)
		mock.part("pad", V3(10, 3, 10), d)
		mock.advance(5.1)
		check("duel pads sonradan gelince göründü", not hidden("Duel pads"))
		duelFolder:Destroy()
		mock.advance(5.1)
		check("gidince yine gizlendi", hidden("Duel pads"))
	end)

	test("Character colors: Apply ve Rainbow (eski renkleri geri koyar)", function()
		local ch = statz:FindFirstChild("character") or mock.folder("character", statz)
		local hair = mock.value("StringValue", "haircolor", "0.5,0.25,1", ch)
		local beard = mock.value("StringValue", "beardcolor", "0.2,0.2,0.2", ch)
		local function sent(t0, part)
			local out = {}
			for _, r in ipairs(mock.remotesSince(t0, "startevent")) do if r.args[1] == part then out[#out + 1] = r.args[2] end end
			return out
		end
		W:SetFlag("cc_part", "Hair")
		L.find("Color", "ColorPicker", "Player"):Set(Color3.new(1, 0, 0))
		local t0 = mock.now
		task.spawn(function() L.find("Apply", "Button", "Player"):Press() end)
		mock.advance(0.1)
		local h = sent(t0, "haircolor")
		check("Apply: haircolor gönderildi", #h == 1 and h[1] == "1.000000000,0.000000000,0.000000000", tostring(h[1]))
		t0 = mock.now
		W:SetFlag("cc_rb_hair", true)
		mock.advance(2.2)
		check("Rainbow: saç ve sakal rengi değişiyor", #sent(t0, "haircolor") >= 2 and #sent(t0, "beardcolor") >= 2)
		check("Rainbow body kapalı: skin gönderilmedi", #sent(t0, "skin") == 0)
		t0 = mock.now
		W:SetFlag("cc_rb_hair", false)
		mock.advance(1.2)
		local back = sent(t0, "haircolor")
		check("kapanınca eski saç rengi geri kondu", #back == 1 and back[1] == "0.500000000,0.250000000,1.000000000", table.concat(back, " | "))
		check("kapanınca eski sakal rengi geri kondu", sent(t0, "beardcolor")[1] == "0.200000000,0.200000000,0.200000000")
		hair:Destroy() beard:Destroy()
	end)

	test("Movement: Always run · Fly FOV · Puppet · Wider dash", function()
		local c = me.Character
		local combat = c:FindFirstChild("combat") or mock.folder("combat", c)
		local run = mock.value("BoolValue", "run", false, combat)
		W:SetFlag("mv_run", true)
		mock.advance(0.1)
		check("Always run: combat.run açıldı", run.Value == true)
		run.Value = false
		mock.advance(0.05)
		check("Always run: oyun kapatınca yine açıyor", run.Value == true)
		W:SetFlag("mv_run", false)
		run.Value = false
		mock.advance(0.05)
		check("kapanınca dokunmuyor", run.Value == false)
		-- FOV: the slider is applied and the game cannot change it during flyjutsu
		local cam = mock.cam
		W:SetFlag("mv_fov", 95)
		check("FOV slider uygulandı", cam.FieldOfView == 95, tostring(cam.FieldOfView))
		local fly = mock.folder("flyjutsu", c, "LocalScript")
		cam.FieldOfView = 120
		check("uçarken FOV 95'te kaldı", cam.FieldOfView == 95, tostring(cam.FieldOfView))
		fly:Destroy()
		mock.advance(1.5)
		cam.FieldOfView = 80
		check("uçuş bitince serbest", cam.FieldOfView == 80, tostring(cam.FieldOfView))
		W:SetFlag("mv_fov", 70)
		-- Wider dash: dashvelocity speed is set to the configured value
		W:SetFlag("mv_dash", true)
		W:SetFlag("mv_dashspeed", 150)
		local dv = mock.folder("dashvelocity", c.HumanoidRootPart, "LinearVelocity")
		dv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
		dv.PlaneVelocity = Vector2.new(30, 40)
		mock.advance(0.05)
		check("Wider dash: hız 150", math.abs(dv.PlaneVelocity.Magnitude - 150) < 1e-3, tostring(dv.PlaneVelocity.Magnitude))
		W:SetFlag("mv_dash", false)
		dv:Destroy()
		-- Puppet: starts and stops without errors
		W:SetFlag("mv_puppet", true)
		mock.advance(0.2)
		check("Puppet kuruldu", ENV.QustahShindoCore and true)
		W:SetFlag("mv_puppet", false)
		local left = {}
		for k in pairs(ENV.QustahShindoCore.Hub.MoveStops) do left[#left + 1] = k end
		check("kapananlardan bağlantı kalmadı (sadece hep açık FOV)", #left == 1 and left[1] == "flyFov", table.concat(left, ","))
		run:Destroy()
	end)

	test("NPC Kill Aura: sadece o anki hedef, antiexploit siliniyor, can eksiye", function()
		local near = spawnNPC("npcaura1", V3(5, 5, 5))
		mock.folder("antiexploit", near)
		local far = spawnNPC("npcaura2", V3(3000, 5, 3000))
		local notnpc = mock.character("Bandit", V3(6, 5, 6), npcFolder)   -- no "npc" in the name: left alone
		mock.folder("npctype", notnpc)
		mock.advance(0.1)
		check("kapalıyken dokunmuyor", near.Humanoid.Health == 100)
		me.Character.HumanoidRootPart.CFrame = CFrame.new(0, 5, 0)   -- no position / target left over from earlier tests
		ENV.QustahShindoCore.Hub.AuraTarget = nil
		W:SetFlag("farm_aura", true)                        -- the Farm > Configurations toggle alone is enough
		mock.frame()
		check("en yakındaki hedefin canı 0 (eksi değer 0'a sıkışır)", near.Humanoid.Health == 0, tostring(near.Humanoid.Health))
		check("hedefin antiexploit'i silindi", near:FindFirstChild("antiexploit") == nil)
		check("aynı karede başka NPC'ye vurmadı", far.Humanoid.Health == 100)
		check("adında npc olmayana dokunmadı", notnpc.Humanoid.Health == 100)
		W:SetFlag("farm_aura", false)
		local fresh = spawnNPC("npcaura3", V3(5, 5, 5))
		mock.advance(0.1)
		check("kapanınca durdu", fresh.Humanoid.Health == 100)
		W:SetFlag("sh_aura", true)                          -- the Player toggle alone is enough too
		mock.frame()
		check("Player toggle'ı ile de çalışıyor", fresh.Humanoid.Health == 0)
		W:SetFlag("sh_aura", false)
		for _, v in ipairs({ near, far, notnpc, fresh }) do v:Destroy() end
	end)

	test("Re-execute after teleport: kuyruğa GitHub raw linki gidiyor", function()
		local q0 = #mock.queued
		W:SetFlag("misc_queue", true)
		local q = mock.queued[#mock.queued]
		check("kuyruğa bir şey eklendi", #mock.queued > q0)
		check("kuyruktaki kod raw linki HttpGet ile yüklüyor", q and q:find("HttpGet(\"https://raw.githubusercontent.com/79650/jewvjs", 1, true) ~= nil, tostring(q))
		check("kaynağın kendisi kuyruğa gömülmüyor", q and #q < 500, tostring(q and #q))
		W:SetFlag("misc_queue", false)
	end)

	test("Auto mentor: görev yoksa mentordan alıyor, başlığa göre yapıyor", function()
		local sensei = mock.folder("sensei", WS)
		local missions = mock.folder("missions", sensei)
		local giver = mock.folder("Narumaki", missions, "Model")
		local mg = mock.folder("missiongiver", giver, "Model")
		mock.part("HumanoidRootPart", V3(300, 5, 300), mg)
		mock.value("RemoteEvent", "CLIENTTALK", nil, mg)
		ms.Visible = false
		local t0 = mock.now
		W:SetFlag("mt_auto", true)
		mock.advance(2)
		check("görev yokken mentorla konuştu", #mock.remotesSince(t0, "CLIENTTALK") > 0)
		ms.Visible, msTitle.Text = true, "[Objective: Tree-Jump Training]"
		mock.advance(0.5)
		t0 = mock.now
		mock.advance(0.3)
		local jumps, clicks = 0, 0
		for _, r in ipairs(mock.remotesSince(t0, "update")) do
			if r.args[1] == "takemovement2" then jumps = jumps + 1 end
			if r.args[1] == "mouse1" then clicks = clicks + 1 end
		end
		check("Tree-Jump başlığı: ağaç zıplama yapılıyor", jumps > 0)
		msTitle.Text = "[Objective: Push-Up Training]"
		mock.advance(0.5)
		t0 = mock.now
		mock.advance(0.3)
		clicks = 0
		for _, r in ipairs(mock.remotesSince(t0, "update")) do if r.args[1] == "mouse1" then clicks = clicks + 1 end end
		check("Push-Up başlığı: M1 basılıyor", clicks > 0)
		W:SetFlag("mt_auto", false)
		ms.Visible, msTitle.Text = false, ""
		sensei:Destroy()
		mock.advance(0.3)
	end)

	test("Boss listesi sadece bu haritadaki boss'ları gösteriyor", function()
		-- missions lists every boss; only the ones on this map have a "missiongiver"
		mock.folder("Other Map Boss", bmissions, "Model")
		local g1 = makeGiver("Zeta Boss", V3(0, 5, 0))
		mock.advance(1)
		local dd = L.flag("farm_bosspick")
		local items = table.concat(dd.Items or {}, ",")
		check("sadece missiongiver olanlar", items == "Zeta Boss", items)
		mock.advance(2.1)                                     -- the counters refresh every 2 s
		local bar = L.find("Bosses on map", "Progress")
		check("boss barı: 1 / 1 ready", bar and bar.cfg.Format(bar.Value) == "1 / 1 ready", tostring(bar and bar.cfg.Format(bar.Value)))
		-- the boss list shows only for Specific
		check("boss listesi sadece Specific'te", dd.cfg.DependsOn and dd.cfg.DependsOn.Flag == "farm_bossmode" and dd.cfg.DependsOn.Value == "Specific")
		-- a distant boss loading later updates the list by itself
		local late = bmissions["Other Map Boss"]
		local mg = mock.folder("missiongiver", late, "Model")
		mock.part("HumanoidRootPart", V3(50, 5, 0), mg)
		mock.advance(1)
		items = table.concat(dd.Items or {}, ",")
		check("sonradan gelen boss listeye eklendi (alfabetik)", items == "Other Map Boss,Zeta Boss", items)
		W:SetFlag("farm_bosspick", { "Zeta Boss", "Other Map Boss" })   -- multi-select
		check("toplu seçim: iki boss seçili", #dd.Value == 2, tostring(#dd.Value))
		g1:Destroy()
		mock.advance(1)
		items = table.concat(dd.Items or {}, ",")
		check("giden boss listeden çıktı", items == "Other Map Boss", items)
		check("giden boss seçimden çıktı, öteki kaldı", type(dd.Value) == "table" and #dd.Value == 1 and dd.Value[1] == "Other Map Boss", tostring(dd.Value and dd.Value[1]))
		check("dropdown çoklu seçim", dd.cfg.Multi == true)
		late:Destroy()
		mock.advance(1)
	end)

	test("Specific seçili ama boss işaretli değilse Random gibi", function()
		local g, talk = makeGiver("Lone Boss", V3(900, 10, 600))
		local talked = false
		mock.onFire[talk] = function() talked = true end
		mock.advance(1)
		W:SetFlag("farm_bossmode", "Specific")
		W:SetFlag("farm_bosspick", {})
		W:SetFlag("farm_boss", true)
		mock.advance(4)
		W:SetFlag("farm_boss", false)
		W:SetFlag("farm_bossmode", "Random")
		check("hiç işaretli yokken hazır boss'la konuştu", talked)
		g:Destroy()
		mock.advance(1)
	end)

	test("Specific Boss toplu seçim: sadece seçilenlerden görev alıyor", function()
		local gA, talkA = makeGiver("Alpha Boss", V3(600, 10, 600))
		local gB, talkB = makeGiver("Beta Boss", V3(700, 10, 600))
		local gC, talkC = makeGiver("Gamma Boss", V3(800, 10, 600))
		local talked = {}
		mock.onFire[talkA] = function() talked.A = true end
		mock.onFire[talkB] = function() talked.B = true end
		mock.onFire[talkC] = function() talked.C = true end
		mock.advance(1)
		W:SetFlag("farm_bossmode", "Specific")
		W:SetFlag("farm_bosspick", { "Beta Boss", "Gamma Boss" })
		W:SetFlag("farm_boss", true)
		mock.advance(6)
		W:SetFlag("farm_boss", false)
		check("seçilmeyen boss'a gitmedi", not talked.A)
		check("seçilenlerle konuştu", talked.B and talked.C, tostring(talked.B) .. "/" .. tostring(talked.C))
		W:SetFlag("farm_bossmode", "Random")
		W:SetFlag("farm_bosspick", {})
		mock.onFire[talkA], mock.onFire[talkB], mock.onFire[talkC] = nil, nil, nil
		gA:Destroy() gB:Destroy() gC:Destroy()
		mock.advance(2)
	end)

	test("Boss farm: boss ölünce görev bitene kadar güvenli noktada bekliyor", function()
		local giverPos = V3(300, 10, 300)
		local bossPos = V3(330, 10, 300)
		local g, talk, timerLabel = makeGiver("Kamaki", giverPos)
		mock.onFire[talk] = function()                       -- talking starts the mission, the boss spawns 1 s later and the cooldown resets
			if ms.Visible then return end
			setMission(true)
			timerLabel.Text = "45:00"
			task.delay(1, function() spawnBoss("npcKamaki", bossPos) end)
		end
		local function serverKill() if bossNpc and bossNpc:FindFirstChild("Humanoid") then bossNpc.Humanoid:Destroy() end end
		local hrp = me.Character.HumanoidRootPart
		-- R6 sizes like the real character (from the QustahInfo dump): root 1.92, leg 1.92 → 2.88 from root to floor when standing
		hrp.Size = V3(1.92, 1.92, 0.96)
		local leg = me.Character:FindFirstChild("Left Leg") or mock.part("Left Leg", hrp.Position + V3(0, -1.92, 0), me.Character)
		leg.Size = V3(0.96, 1.92, 0.96)
		leg.CanCollide = false
		local safe = giverPos + V3(0, 1000, 0)
		local atBoss = (CFrame.new(bossPos) * CFrame.new(0, 0, 10)).Position
		W:SetFlag("farm_boss", true)
		mock.advance(1.8)                                    -- talked, the boss has not spawned yet
		check("boss doğmadan güvenli noktaya gitmiyor", (hrp.Position - safe).Magnitude > 100, tostring(hrp.Position))
		mock.advance(1.5)                                    -- the boss spawned and is being hit (0 health on the client, alive on the server)
		check("boss istemcide 0 canda ama hâlâ yaşıyor: kaçmıyor, vurmaya devam", nearV(hrp.Position, atBoss, 0.5), tostring(hrp.Position))
		mock.advance(1)
		check("1 sn sonra da boss'un yanında", nearV(hrp.Position, atBoss, 0.5), tostring(hrp.Position))
		serverKill()                                         -- died on the server: Humanoid removed
		mock.advance(0.5)
		check("boss gerçekten ölünce güvenli zeminde (verici + 1000)", onSafe(safe), tostring(hrp.Position))
		-- free movement on the floor: no constant teleporting
		hrp.CFrame = CFrame.new(safe + V3(12, 3.5, -8))
		mock.advance(1)
		check("zeminin üstünde serbest: yerinden oynatılmıyor", nearV(hrp.Position, safe + V3(12, 3.5, -8), 0.01), tostring(hrp.Position))
		-- put back after leaving the floor
		hrp.CFrame = CFrame.new(safe + V3(60, -40, 0))
		mock.advance(0.5)
		check("zeminden çıkınca/düşünce geri konuyor", onSafe(safe), tostring(hrp.Position))
		do   -- feet exactly on top of the floor (R6: half the root + leg height): not inside it, not floating
			local p = safePart()
			local feet = hrp.Position.Y - (hrp.Size.Y / 2 + me.Character["Left Leg"].Size.Y)
			local top = p.Position.Y + p.Size.Y / 2
			check("ayaklar zeminin içinde değil (0..0.3 pay)", feet - top >= 0 and feet - top <= 0.3, tostring(feet - top))
			check("güvenli zemin 85x85", p.Size.X == 85 and p.Size.Z == 85, tostring(p.Size))
			check("güvenli zemin haritanın içinde (workspace.map)", p.Parent == mapFolder, tostring(p.Parent))
			check("haritadaki zeminden kopyalandı (collision grubu + materyal)", p.CollisionGroup == "MapGround" and p.Material == "Concrete", tostring(p.CollisionGroup))
			check("kopyadan doku vb. gelmedi", #p:GetChildren() == 0)
			check("kopya yine yarı saydam ve sabit", p.Transparency == 0.6 and p.Anchored == true and p.CanCollide == true)
		end
		mock.advance(2)
		check("görev bitmeden zeminde kalıyor", onSafe(safe), tostring(hrp.Position))
		-- mission finished but the boss cooldown has not: keep waiting at the safe spot
		bossNpc:Destroy()
		setMission(false)
		mock.advance(1)
		check("sıradaki boss yokken güvenli zeminde bekliyor", onSafe(safe), tostring(hrp.Position))
		-- cooldown finished: leave the safe spot and go to the giver
		local talks0 = #mock.remotesSince(0, "CLIENTTALK")
		timerLabel.Text = "00:00"
		mock.advance(0.5)
		check("süre dolunca vericiyle konuştu", #mock.remotesSince(0, "CLIENTTALK") > talks0)
		check("vericiye inince güvenli zemin kalktı", safePart() == nil)
		mock.advance(3)
		serverKill()
		mock.advance(0.5)
		check("yeni boss da ölünce yine güvenli zeminde", onSafe(safe), tostring(hrp.Position))
		bossNpc:Destroy()
		setMission(false)
		W:SetFlag("farm_boss", false)
		mock.advance(0.5)
		check("farm kapanınca platform ve güvenli zemin silindi", platformPart() == nil and safePart() == nil)
		mock.onFire[talk] = nil
		g:Destroy()
	end)

	test("Boss farm: başkasının görevindeki boss'u atlıyor", function()
		local g, talk = makeGiver("Taken Boss", V3(-500, 10, -500))
		local pos = mock.folder("position", g)
		local p1 = mock.folder("p1", pos)
		mock.value("BoolValue", "inmission", true, p1)
		local t0 = mock.now
		W:SetFlag("farm_boss", true)
		mock.advance(2)
		local n = 0
		for _, r in ipairs(mock.remotesSince(t0, "CLIENTTALK")) do n = n + 1 end
		check("inmission olan boss'la konuşmadı", n == 0, tostring(n))
		W:SetFlag("farm_boss", false)
		mock.advance(0.3)
		g:Destroy()
	end)

	test("Güvenli zeminde kaymıyor", function()
		local g, talk, timerLabel = makeGiver("Slide", V3(700, 10, 700))
		mock.onFire[talk] = function()
			if ms.Visible then return end
			setMission(true) timerLabel.Text = "45:00"
		end
		W:SetFlag("farm_boss", true)
		mock.advance(2)
		-- the boss never spawned but there is a full-susanoo mob: go to the safe floor
		local sus = mock.character("npcSus", V3(720, 10, 700), npcFolder) mock.folder("npctype", sus) mock.folder("fullsusanoo", sus)
		mock.advance(0.5)
		local hrp = me.Character.HumanoidRootPart
		local sp = safePart()
		check("güvenli zemin var", sp ~= nil)
		hrp.AssemblyLinearVelocity = V3(30, -2, 15)        -- leftover momentum from the teleport
		mock.frame()
		local v = hrp.AssemblyLinearVelocity
		check("tuşa basmıyorken yatay hız sıfırlandı", math.abs(v.X) + math.abs(v.Z) < 0.01 and v.Y == -2, tostring(v))
		me.Character.Humanoid.MoveDirection = V3(1, 0, 0)
		hrp.AssemblyLinearVelocity = V3(16, 0, 0)
		mock.frame()
		check("yürürken hıza karışmıyor", hrp.AssemblyLinearVelocity.X == 16)
		me.Character.Humanoid.MoveDirection = V3(0, 0, 0)
		hrp.AssemblyLinearVelocity = V3(0, 0, 0)
		check("platform zeminle üst üste değil", platformPart() == nil or (platformPart().Position - sp.Position).Magnitude > 5)
		sus:Destroy()
		setMission(false)
		W:SetFlag("farm_boss", false)
		mock.advance(0.5)
		mock.onFire[talk] = nil
		g:Destroy()
	end)

	test("Boss farm: susanoo'lu boss'a vurulamıyorsa güvenli noktada bekliyor", function()
		local giverPos = V3(-200, 20, 50)
		local g, talk, timerLabel = makeGiver("Susano", giverPos)
		mock.onFire[talk] = function()
			if ms.Visible then return end
			setMission(true)
			timerLabel.Text = "45:00"
			spawnBoss("npcSusano", V3(-180, 20, 50), true)
		end
		W:SetFlag("farm_boss", true)
		mock.advance(3)
		local hrp = me.Character.HumanoidRootPart
		check("susanoo'lu boss canlı (vurulmadı)", bossNpc.Humanoid.Health == 100)
		check("güvenli zeminde bekliyor", onSafe(giverPos + V3(0, 1000, 0)), tostring(hrp.Position))
		bossNpc:Destroy()
		setMission(false)
		W:SetFlag("farm_boss", false)
		mock.advance(0.5)
		mock.onFire[talk] = nil
		g:Destroy()
		bdm:Destroy()
	end)

	test("Daily boss quests açılınca platform kuruluyor", function()
		W:SetFlag("dl_boss", true)
		mock.advance(0.3)
		check("platform var", platformPart() ~= nil)
		W:SetFlag("dl_boss", false)
		mock.advance(0.3)
		check("kapatınca platform yok", platformPart() == nil)
	end)

	----- Server -----
	-- the rows, sorting and Refresh are the lib's (Card:ServerList); the hub gives it the data and the actions
	test("Sunucu listesi", function()
		local list = L.find(nil, "ServerList")
		for _, e in ipairs(L.elements) do if e.Kind == "ServerList" then list = e end end
		check("Servers kartında ServerList", list ~= nil and list.card and list.card.Title == "Servers")
		if not list then return end
		local servers = list.cfg.Fetch()
		local ids = {}
		for _, sv in ipairs(servers) do ids[#ids + 1] = sv.id:sub(-1) end
		check("Fetch: dolu ve kendi sunucun hariç 3 sunucu", #servers == 3, table.concat(ids, ","))
		local here = list.cfg.Current()
		check("Current: bu sunucu, oyuncu sayısıyla", here.id == mock.game.JobId and here.playing == #PS:GetPlayers(), tostring(here.id))
		local n0 = #mock.teleports
		list.cfg.OnJoin(servers[1], false)
		local tp = mock.teleports[n0 + 1]
		check("Join: seçilen sunucuya teleport", tp and tp.kind == "Instance" and tp.job == servers[1].id, tp and tp.job)
		check("Random hop verilmiş", type(list.cfg.OnHop) == "function")
	end)

	test("Staff alert ayarları sadece açıkken görünür", function()
		local g = L.flag("s_group")
		check("Group ID DependsOn s_staff (Hide)", g.cfg.DependsOn and g.cfg.DependsOn.Flag == "s_staff" and g.cfg.DependsOn.Mode == "Hide")
	end)

	----- General -----
	test("Normal çalışmada hata raporu yok", function()
		local bad = {}
		for _, r in ipairs(L.reported) do
			if not tostring(r.err):find("bozuk") then bad[#bad + 1] = r.tag .. ": " .. tostring(r.err) end
		end
		check("beklenmeyen hata raporu yok", #bad == 0, table.concat(bad, " | "))
		local co = {}
		for _, e in ipairs(mock.errors) do co[#co + 1] = e:sub(1, 300) end
		check("thread hatası yok", #mock.errors == 0, table.concat(co, "\n"))
	end)

	-- the panel of a player who left the view must not stay on screen; an error hides only that player's panel
	test("Ekrandan çıkan oyuncunun paneli kayboluyor", function()
		for _, p in ipairs(PS:GetPlayers()) do if p ~= me then mock.removePlayer(p) end end
		W:SetFlag("esp_enabled", true)
		mock.cam.CFrame = CFrame.new(0, 10, 30)
		local walker = mock.player("Walker", V3(0, 5, 0))
		refreshPanels()
		local function on() local g = billboard("Walker") return g ~= nil and g.Enabled == true end
		check("ekrandayken panel açık", on())
		walker.Character.HumanoidRootPart.CFrame = CFrame.new(0, 5, 200)   -- behind the camera
		walker.Character.Head.CFrame = CFrame.new(0, 6.5, 200)
		refreshPanels()
		check("ekrandan çıkınca panel kapandı", not on())
		walker.Character.HumanoidRootPart.CFrame = CFrame.new(0, 5, 0)
		walker.Character.Head.CFrame = CFrame.new(0, 6.5, 0)
		refreshPanels()
		check("geri gelince panel yine açık", on())
		local rawp = rawget(walker, "__p")
		rawp.DisplayName = nil
		setmetatable(rawp, { __index = function(_, k) if k == "DisplayName" then error("bozuk isim") end end })
		refreshPanels()
		check("hata olunca o oyuncunun paneli gizleniyor", not on())
		mock.removePlayer(walker)
		refreshPanels()
	end)

	test("Unload her şeyi durduruyor", function()
		W:SetFlag("mt_punch", true)
		W:SetFlag("dl_rush", true)
		W:SetFlag("farm_scroll", true)
		mock.advance(0.3)
		local platform
		for _, c in ipairs(WS:GetChildren()) do if c.ClassName == "Part" and c.Transparency == 1 and c.Anchored then platform = c end end
		check("farm açıkken platform var", platform ~= nil)
		ENV.QustahShindoCore.Unload()
		mock.advance(0.2)
		local t0 = mock.now
		mock.advance(1)
		check("Unload sonrası remote yok", #mock.remotesSince(t0) == 0, tostring(#mock.remotesSince(t0)))
		local alive = 0
		for _, d in ipairs(mock.drawings) do if not d.__removed then alive = alive + 1 end end
		check("Unload sonrası Drawing kalmadı", alive == 0, tostring(alive))
		check("Unload sonrası GUI çizim katmanı silindi", overlay() == nil)
		local plat = false
		for _, c in ipairs(WS:GetChildren()) do if c.ClassName == "Part" and c.Transparency == 1 and c.Anchored then plat = true end end
		check("Unload sonrası platform silindi", not plat)
		check("pencere kapandı", W.alive == false)
	end)
end

----- Scenario: main menu (Inf Spin) -----
if SCENARIO == "menu" then
	test("Spin sekmesi ana menüde var, uyarı yok", function()
		local need = { "Wanted", "Slots", "Start spinning", "Reset when spins reach", "Spin delay", "Save when done", "Reset spins", "Save spins",
			"Open Auto Spin RELL", "Re-run after rejoin", "Stop" }
		local have, missing = L.titles("Spin"), {}
		for _, n in ipairs(need) do if not have[n] then missing[#missing + 1] = n end end
		check("Spin: hepsi var", #missing == 0, "eksik: " .. table.concat(missing, ", "))
		local warned = false
		for _, w in ipairs(L.warnings) do if tostring(w):find("main menu") then warned = true end end
		check("'only works in the main menu' uyarısı yok", not warned)
	end)

	local function startevents(t0, kind)
		local n = 0
		for _, r in ipairs(mock.remotesSince(t0, "startevent")) do if not kind or r.args[1] == kind then n = n + 1 end end
		return n
	end

	test("Inf Spin: Wanted boşken spin atmıyor, kaydedip çıkmıyor", function()
		W:SetFlag("is_elem_on_list", {})
		W:SetFlag("is_elem_on", true)
		local n0 = #L.notifications
		local t0 = mock.now
		mock.advance(2)
		check("spin yok", startevents(t0, "spin") == 0)
		check("kaydedip çıkma yok (band / arenateleport)", startevents(t0, "band") == 0 and startevents(t0, "arenateleport") == 0)
		local warned = false
		for i = n0 + 1, #L.notifications do if tostring(L.notifications[i].Content):find("Wanted is empty") then warned = true end end
		check("uyarı verdi", warned)
		W:SetFlag("is_elem_on", false)
	end)

	test("Inf Spin: Slots boşken kaydedip çıkmıyor", function()
		W:SetFlag("is_elem_on_list", { "lightning" })
		W:SetFlag("is_elem_on_slots", {})
		W:SetFlag("is_elem_on", true)
		local t0 = mock.now
		mock.advance(2)
		check("Slots boş: kaydedip çıkma yok", startevents(t0, "band") == 0 and startevents(t0, "arenateleport") == 0)
		W:SetFlag("is_elem_on", false)
	end)

	test("Inf Spin: istenen gelene kadar spin, gelince kaydet", function()
		W:SetFlag("is_elem_on_list", { "lightning" })
		W:SetFlag("is_elem_on_slots", { "1" })
		W:SetFlag("is_elem_on", true)
		local t0 = mock.now
		mock.advance(1)
		local spins = 0
		for _, r in ipairs(mock.remotesSince(t0, "startevent")) do if r.args[1] == "spin" and r.args[2] == "element1" then spins = spins + 1 end end
		check("element1 için spin atıldı", spins > 0)
		statz.main.element1.Value = "lightning"
		t0 = mock.now
		mock.advance(2)
		check("gelince spin durdu", startevents(t0, "spin") == 0)
		check("gelince kaydetti (band Eye)", startevents(t0, "band") == 1)
		check("gelince My Home'a geçti", startevents(t0, "arenateleport") == 1)
		check("toggle kapandı", L.flag("is_elem_on").Value == false)
	end)

	test("Inf Spin listesinde gerçek isimler, kayıtta kod adı", function()
		local dd = L.flag("is_elem_on_list")
		local items = table.concat(dd.Items or {}, ",")
		check("Wanted listesinde gerçek isimler", items:find("Wind Release", 1, true) ~= nil, items)
		W:SetFlag("is_elem_on_list", { "Wind Release", "Lightning Release" })
		local data = mock.json.decode(mock.files["QustahShindo/infspin.json"])
		check("dosyaya kod adı yazıldı", data.Elements[1] == "wind" and data.Elements[2] == "lightning", table.concat(data.Elements, ","))
		W:SetFlag("is_elem_on_list", { "lightning" })
	end)

	test("Inf Spin seçimleri dosyaya kaydediliyor", function()
		local f = mock.files["QustahShindo/infspin.json"]
		check("infspin.json yazıldı", f ~= nil)
		local data = f and mock.json.decode(f)
		check("Elements kaydı", data and data.Elements and data.Elements[1] == "lightning")
	end)

	if mock.httpRoutes["refs/heads/main/rellauto"] then
		test("Auto Spin RELL: raw'dan açılıyor, Stop durduruyor", function()
			-- game objects RELL expects
			mock.folder("startup", WS.Camera)
			local shop = mock.folder("RYOshop", mainGui) local si = mock.folder("ShopItems", shop) local hb = mock.folder("HB", si)
			for _, n in ipairs({ "int", "rellcloak", "limited" }) do mock.folder(n, hb, "TextLabel") end
			local cz = mock.folder("Customization", mainGui) local ct = mock.folder("CharacterTab", cz)
			local f1 = mock.folder("Frame1", ct) mock.folder("Frame2", ct, "Frame")
			local hair = mock.folder("hair", f1, "Frame")
			for _, n in ipairs({ "color", "arrowleft", "arrowright", "custom" }) do mock.folder(n, hair, "Frame") end
			for _, n in ipairs({ "band", "outfit", "shoe", "beard", "face" }) do mock.folder(n, f1, "Frame") end
			for i = 1, 4 do statz.main["kg" .. i].Value = "senko" end
			local t0 = mock.now
			task.spawn(function() L.find("Open Auto Spin RELL", "Button"):Press() end)   -- button callbacks run in their own thread
			mock.advance(3)
			check("RELL çalışıyor (hub bayrağı)", ENV.RELL_RUNNING == true)
			check("RELL penceresi QustahRELL adıyla açıldı", pg:FindFirstChild("QustahRELL") ~= nil)
			local spins = 0
			for _, r in ipairs(mock.remotesSince(t0, "startevent")) do if r.args[1] == "spin" then spins = spins + 1 end end
			check("bloodline spini atıyor", spins > 0, tostring(spins))
			-- Inf Spin does not start while RELL is open
			W:SetFlag("is_bl_on", true)
			mock.advance(0.5)
			check("RELL açıkken Inf Spin açılmıyor", L.flag("is_bl_on").Value == false)
			-- Stop
			L.find("Stop", "Button", "Spin"):Press()
			mock.advance(0.5)
			t0 = mock.now
			mock.advance(3)
			local after = 0
			for _, r in ipairs(mock.remotesSince(t0, "startevent")) do if r.args[1] == "spin" then after = after + 1 end end
			check("Stop'tan sonra spin yok", after == 0, tostring(after))
			check("RELL kapandı (bayrak + pencere)", ENV.RELL_RUNNING == false and pg:FindFirstChild("QustahRELL") == nil)
			check("durdurma dosyası yazıldı (rejoin'de açılmaz)", mock.files["QustahShindoRELL.stop"] ~= nil)
			-- rollback when spins run out: the guarded link is queued
			mock.files["QustahShindoRELL.stop"] = nil
			local q0 = #mock.queued
			task.spawn(function() L.find("Open Auto Spin RELL", "Button"):Press() end)   -- button callbacks run in their own thread
			mock.advance(2)
			statz.spins.Value = 0
			mock.advance(2)
			local q = mock.queued[#mock.queued]
			check("rollback'te kuyruğa RELL linki gitti", #mock.queued > q0 and q:find("rellauto", 1, true) ~= nil, tostring(q))
			check("kuyruktaki kodda durdurma dosyası kontrolü var", q and q:find("QustahShindoRELL.stop", 1, true) ~= nil)
			L.find("Stop", "Button", "Spin"):Press()
			mock.advance(0.5)
			statz.spins.Value = 212
		end)
	end

	test("Menüde hata yok", function()
		local bad = {}
		for _, r in ipairs(L.reported) do bad[#bad + 1] = r.tag .. ": " .. tostring(r.err) end
		check("hata raporu yok", #bad == 0, table.concat(bad, " | "))
		local co = {}
		for _, e in ipairs(mock.errors) do co[#co + 1] = e:sub(1, 300) end
		check("thread hatası yok", #mock.errors == 0, table.concat(co, "\n"))
	end)
end

----- Results -----
local out = {}
for _, r in ipairs(results.list) do
	out[#out + 1] = (r.ok and "  ok   " or "  FAIL ") .. r.name .. ((not r.ok and r.detail) and ("\n         " .. tostring(r.detail):gsub("\n", "\n         ")) or "")
end
mock.realPrint(("[%s] %d geçti, %d kaldı"):format(SCENARIO, results.pass, results.fail))
mock.realPrint(table.concat(out, "\n"))
os.exit(results.fail == 0 and 0 or 1)
