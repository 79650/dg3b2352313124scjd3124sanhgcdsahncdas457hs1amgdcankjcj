-- Real UI lib in the mock Roblox: builds a window with the components the hub uses and checks what they draw.
-- Usage: texlua lib_run.lua <qustah-ui-lib.lua converted to Lua 5.3> [esp module converted to Lua 5.3]
local HERE = arg[0]:match("(.*/)") or "./"
package.path = HERE .. "?.lua;" .. package.path
local LIB, ESP = arg[1], arg[2]

local mock = dofile(HERE .. "mock.lua")
local V3 = Vector3.new

----- Minimal test framework -----
local results = { pass = 0, fail = 0, list = {} }
local function check(name, ok, detail)
	if ok then results.pass = results.pass + 1 else results.fail = results.fail + 1 end
	results.list[#results.list + 1] = { name = name, ok = ok, detail = detail }
end
local function test(name, fn)
	local ok, err = pcall(fn)
	if not ok then check(name .. " (hata)", false, tostring(err)) end
end
local function find(root, pred)
	for _, d in ipairs(root:GetDescendants()) do if pred(d) then return d end end
end
local function count(root, pred)
	local n = 0
	for _, d in ipairs(root:GetDescendants()) do if pred(d) then n = n + 1 end end
	return n
end
local function rgb(c) return c and math.floor(c.R * 255 + 0.5) .. "," .. math.floor(c.G * 255 + 0.5) .. "," .. math.floor(c.B * 255 + 0.5) end

----- World -----
local me = mock.player("Me", V3(0, 5, 20), { silent = true })
mock.PS.__p.LocalPlayer = me

local Lib
test("lib yükleniyor", function()
	Lib = assert(loadfile(LIB))()
	check("lib yüklendi", type(Lib) == "table" and Lib.Version ~= nil, Lib and Lib.Version)
end)
if not Lib then
	io.write(("[lib] %d geçti, %d kaldı\n"):format(results.pass, results.fail))
	for _, r in ipairs(results.list) do if not r.ok then io.write("  FAIL ", r.name, "\n         ", tostring(r.detail), "\n") end end
	os.exit(1)
end

local W = Lib:CreateWindow({ Title = "Test", Folder = "QustahLibTest" })
local Tab = W:Tab({ Title = "Main", Icon = "home" })
local Page = Tab:Page("One")
mock.advance(0.5)

test("Window:Value: menüde satırı yok, flag gibi kaydediliyor", function()
	local seen
	local value = W:Value({ Flag = "t_style", Default = "Smooth", Callback = function(v) seen = v end })
	mock.advance(0.1)
	check("Value: varsayılan Lib.Flags'te", Lib.Flags.t_style == "Smooth", tostring(Lib.Flags.t_style))
	check("Value: oluşurken Callback çalışmıyor", seen == nil)
	W:SetFlag("t_style", "Stripes")
	check("SetFlag → Callback", seen == "Stripes", tostring(seen))
	check("SetFlag → Value / Lib.Flags", value.Value == "Stripes" and Lib.Flags.t_style == "Stripes")
	check("config varsayılanı kaydedildi", W.Config.Defaults.t_style == "Smooth", tostring(W.Config.Defaults.t_style))
	local snapshot = {}
	for k, v in pairs(W.Flags) do snapshot[k] = v end
	check("profil anlık görüntüsünde var", snapshot.t_style == "Stripes")
	W:SetFlag("t_style", "Smooth")
end)

test("ColorChoice: noktalar ve seçici aynı rengi tutuyor", function()
	local card = Page:Card({ Title = "Colors", Icon = "palette" })
	local got
	local red, white = Color3.fromRGB(224, 70, 70), Color3.fromRGB(255, 255, 255)
	local choice = card:ColorChoice({
		Swatches = { Title = "Color", Style = "Dots", Default = "White", Items = { { "White", white }, { "Red", red } } },
		Picker = { Title = "Custom color", Flag = "t_color", Default = white },
		Callback = function(c) got = c end,
	})
	mock.advance(0.1)
	choice.Swatches:Set("Red")
	check("noktadan Red → seçici kırmızı", rgb(choice.Picker:Get()) == rgb(red), rgb(choice.Picker:Get()))
	check("Callback kırmızıyla çağrıldı", got and rgb(got) == rgb(red), rgb(got))
	W:SetFlag("t_color", white)
	check("seçiciden beyaz → nokta White", choice.Swatches.Value == "White", tostring(choice.Swatches.Value))
end)

test("Swatches Dots: çok renkli öğe geçişle dolu", function()
	local card = Page:Card({ Title = "Dots", Icon = "palette" })
	local sw = card:Swatches({ Title = "Bars", Style = "Dots", Default = "Ice", Items = {
		{ "Ice", Color3.fromRGB(79, 91, 213), Color3.fromRGB(63, 169, 245), Color3.fromRGB(159, 243, 255) },
		{ "Plain", Color3.fromRGB(200, 0, 0) } } })
	mock.advance(0.1)
	local ice = find(sw.Row, function(d) return d.Name == "Ice" and d.ClassName == "TextButton" end)
	local plain = find(sw.Row, function(d) return d.Name == "Plain" and d.ClassName == "TextButton" end)
	check("Ice noktasında UIGradient", ice and find(ice, function(d) return d.ClassName == "UIGradient" end) ~= nil)
	check("tek renkli noktada gradyan yok", plain and find(plain, function(d) return d.ClassName == "UIGradient" end) == nil)
end)

test("ServerList: satırlar, kendi sunucun, Join", function()
	local card = Page:Card({ Title = "Servers", Icon = "server" })
	local joined
	local list = card:ServerList({
		Fetch = function() return {
			{ id = "aaaaaaaa-1", playing = 3, maxPlayers = 20, ping = 120 },
			{ id = "aaaaaaaa-2", playing = 11, maxPlayers = 20, ping = 30 },
		} end,
		Current = function() return { id = "cccccccc-0", playing = 5, maxPlayers = 20, ping = 60 } end,
		OnJoin = function(server, current) joined = { server = server, current = current } end,
		OnHop = function() end,
	})
	mock.advance(1.5)
	local frame = list.Frame
	check("kaydırılan liste", frame and frame.ClassName == "ScrollingFrame", frame and frame.ClassName)
	local rows = frame and count(frame, function(d) return d.Name == "Server" end) or 0
	check("kendi satırın + 2 sunucu", rows == 3, tostring(rows))
	local join = frame and find(frame, function(d) return d.ClassName == "TextButton" and d.Text == "Join" end)
	if join then join.Activated:Fire() end
	check("Join → OnJoin(sunucu)", joined and joined.server and joined.current == false, joined and tostring(joined.current))
end)

test("SkyPreview ve LocationList çiziliyor", function()
	local card = Page:Card({ Title = "Sky", Icon = "sun" })
	local sky = card:SkyPreview({ Height = 74, Read = function() return { Hour = 13, Ambient = Color3.new(0.5, 0.5, 0.5), FromGame = true } end })
	sky:Update()
	mock.advance(0.1)
	local label = find(card.body, function(d) return d.ClassName == "TextLabel" and tostring(d.Text):find("13:00") end)
	check("gökyüzü saati yazıyor (13:00)", label ~= nil)
	local places = Page:Card({ Title = "Locations", Icon = "map-pin" })
	local went
	places:LocationList({ Items = { { Title = "Kage Office", Position = V3(10, 0, 0) }, { Title = "Shop", Position = V3(0, 0, 3000) } },
		Origin = function() return V3(0, 0, 0) end, Callback = function(item) went = item.Title end })
	mock.advance(2.5)
	local far = find(places.body, function(d) return d.ClassName == "TextLabel" and tostring(d.Text):find("3.0k studs") end)
	check("uzak yerin mesafesi (3.0k studs)", far ~= nil)
	local go = find(places.body, function(d) return d.ClassName == "TextButton" and d.Text == "Go" end)
	if go then go.Activated:Fire() end
	check("Go → Callback", went ~= nil, tostring(went))
end)

test("WhileVisible ve dependencyIcons", function()
	local card = Page:Card({ Title = "Loop", Icon = "clock" })
	local runs = 0
	local stop = card:WhileVisible(0.5, function() runs = runs + 1 end)
	check("WhileVisible durdurma fonksiyonu döndürüyor", type(stop) == "function")
	mock.advance(1.2)
	stop()
	local after = runs
	mock.advance(1.2)
	check("durdurunca çalışmıyor", runs == after, runs .. " / " .. after)
	local cleanup = Lib.Util.dependencyIcons(W)
	check("dependencyIcons temizleme fonksiyonu", type(cleanup) == "function")
end)

----- The ESP module with the real lib -----
if ESP then
	test("ESP modülü: önizleme kapsülleri kendi renklerinde", function()
		local EspKit = assert(loadfile(ESP))()(Lib)
		local settings = { HealthSegments = 5, ModeSegments = 1, TextSize = 14, Name = true, User = true, Distance = true,
			HealthBar = true, HealthText = true, ModeBar = true, ModeText = false, HealthPreset = "Ice", ModePreset = "Aurora",
			HealthBarStyle = "Smooth", ModeBarStyle = "Stripes", HealthBarOpacity = 1, ModeBarOpacity = 1 }
		local esp = EspKit.Create({ State = {}, Settings = settings, HealthColor = function(p) return EspKit.Palettes.ColorAt(EspKit.Palettes.Health.Ice, p) end,
			ModeColor = function(p) return EspKit.Palettes.ColorAt(EspKit.Palettes.Mode.Aurora, p) end })
		local keys = { colors = "t_hp", style = "t_hpstyle", opacity = "t_hpop", presetSetting = "HealthPreset", styleSetting = "HealthBarStyle",
			opacitySetting = "HealthBarOpacity", barSetting = "HealthBar" }
		W:Value({ Flag = "t_hp", Default = "Ice", Callback = function(v) settings.HealthPreset = v end })
		W:Value({ Flag = "t_hpstyle", Default = "Smooth", Callback = function(v) settings.HealthBarStyle = v end })
		W:Value({ Flag = "t_hpop", Default = 100, Callback = function(v) settings.HealthBarOpacity = v / 100 end })
		local card = Page:Card({ Title = "Preview", Icon = "scan-eye" })
		EspKit.Preview(card, { Settings = settings, Renderer = esp, Read = function()
			return { display = "Me", user = "Me", health = 1500, maxHealth = 2000, mode = 60, modeCap = 100, distance = 42 }
		end, Controls = { { Label = "HP", Presets = EspKit.Palettes.Health, Keys = keys } } })
		mock.advance(0.5)
		local hp = find(card.body, function(d) return d.Name == "HP" and d.ClassName == "Frame" end)
		check("HP kapsülü var", hp ~= nil)
		if not hp then return end
		local smooth = find(hp, function(d) return d.Name == "Smooth" and d.ClassName == "TextButton" end)
		local icon = smooth and smooth:FindFirstChildWhichIsA("Frame")
		check("Smooth ikonu açık gri (temaya bağlanmamış)", icon and rgb(icon.BackgroundColor3) == "207,211,220", icon and rgb(icon.BackgroundColor3))
		check("seçili düğme koyu gri (42,44,52)", rgb(smooth.BackgroundColor3) == "42,44,52", rgb(smooth.BackgroundColor3))
		local ice = find(hp, function(d) return d.Name == "Ice" and d.ClassName == "TextButton" end)
		local ring = ice and find(ice, function(d) return d.ClassName == "UIStroke" end)
		check("seçili renk halkası beyaz ve görünür", ring and rgb(ring.Color) == "238,240,244" and ring.Transparency == 0, ring and (rgb(ring.Color) .. " / " .. ring.Transparency))
		local mint = find(hp, function(d) return d.Name == "Mint" and d.ClassName == "TextButton" end)
		mint.Activated:Fire()
		check("noktaya basınca flag değişti", Lib.Flags.t_hp == "Mint", tostring(Lib.Flags.t_hp))
		local panel = find(card.body, function(d) return d.Name == "Panel" end)
		check("önizlemede panel çizildi", panel and panel:FindFirstChild("HealthBar") ~= nil)
		esp:Destroy()
	end)
end

if ESP then
	-- Stripes: one tiled picture when the executor has getcustomasset, frames otherwise (same look, ~40 objects less a bar)
	test("ESP modülü: Stripes tek resim (getcustomasset) ya da frame", function()
		local written = {}
		local oldWrite, oldAsset = writefile, getcustomasset
		local function panelWith(kit)
			local settings = { HealthSegments = 5, ModeSegments = 1, TextSize = 14, Name = true, User = true, Distance = true,
				HealthBar = true, HealthText = true, ModeBar = true, ModeText = false, HealthPreset = "Ice", ModePreset = "Aurora",
				HealthBarStyle = "Stripes", ModeBarStyle = "Stripes", HealthBarOpacity = 0.5, ModeBarOpacity = 1 }
			local plain = function() return Color3.new(1, 1, 1) end
			local renderer = kit.PanelRenderer(settings, { HealthColor = plain, ModeColor = plain, Colors = { back = Color3.new(), split = Color3.new() },
				Format = function(n) return tostring(n) end })
			local holder = Instance.new("Frame")
			local panel = renderer.BuildPanel(holder)
			renderer.UpdatePanel(panel, { display = "A", user = "a", health = 50, maxHealth = 100, mode = 60, modeCap = 100, distance = 10 })
			return holder, panel
		end
		writefile = function(path, data) written[path] = data end
		getcustomasset = function(path) return "rbxasset://custom/" .. path end
		local kit = assert(loadfile(ESP))()(Lib)
		local holder, panel = panelWith(kit)
		local tile = panel.healthFill.Stripes:FindFirstChild("Tile")
		check("resim yolu: Tile ImageLabel", tile ~= nil and tile.ClassName == "ImageLabel")
		check("resim: getcustomasset adresi", tile and tile.Image == "rbxasset://custom/QustahShindo/esp_stripes.png", tile and tile.Image)
		local png = written["QustahShindo/esp_stripes.png"]
		check("yazılan dosya PNG (89 bayt)", png and png:sub(2, 4) == "PNG" and #png == 89, png and #png)
		check("opaklık resme uygulandı (%50 → 0.85)", tile and math.abs(tile.ImageTransparency - 0.85) < 1e-6, tile and tile.ImageTransparency)
		local withImage = #holder:GetDescendants()
		writefile, getcustomasset = oldWrite, nil
		local kit2 = assert(loadfile(ESP))()(Lib)
		local holder2, panel2 = panelWith(kit2)
		check("getcustomasset yoksa frame çizgiler", panel2.healthFill.Stripes:FindFirstChild("Tile") == nil and #panel2.healthFill.Stripes:GetChildren() == 20,
			#panel2.healthFill.Stripes:GetChildren())
		local withFrames = #holder2:GetDescendants()
		check("resimle nesne sayısı çok daha az", withImage + 70 <= withFrames, withImage .. " / " .. withFrames)
		getcustomasset = oldAsset
	end)
end

test("Settings: tema kutuları, Text / Behaviour / Window, oyun başına profil yok", function()
	local tab = W:SettingsTab({ Compact = true })
	mock.advance(0.5)
	local root = W.main or W.gui
	local function titled(text) return root and find(root, function(d) return d.ClassName == "TextLabel" and d.Text == text end) end
	check("Theme / Text / Behaviour / Window kartları", titled("Theme") ~= nil and titled("Text") ~= nil and titled("Behaviour") ~= nil and titled("Window") ~= nil)
	check("eski kartlar yok (Appearance, Layout, Theme editor)", titled("Appearance") == nil and titled("Layout") == nil and titled("Theme editor") == nil)
	local gallery = root and find(root, function(d) return d.Name == "ThemeGallery" end)
	check("tema galerisi var", gallery ~= nil)
	if gallery then
		local names = {}
		for _, c in ipairs(gallery:GetChildren()) do if c.ClassName == "TextButton" then names[#names + 1] = c.Name end end
		check("9 hazır tema + New (Ash ilk, varsayılan)", table.concat(names, ",") == "Ash,Charcoal,Onyx,Charcoal Rose,Ice,Forest,Wine,Peach,Rust,New", table.concat(names, ","))
		check("varsayılan theme Ash", Lib.Theme.defaultPack == "Ash")
		local forest = gallery:FindFirstChild("Forest")
		forest.Activated:Fire()
		mock.advance(0.1)
		check("Forest kutusuna basınca tema Forest", Lib.Flags.__ui_theme == "Forest" and Lib.Theme.pack == "Forest", tostring(Lib.Flags.__ui_theme))
		local shot = forest:FindFirstChild("Shot")
		check("kutu temanın kendi rengiyle çizili (Forest koyu yeşil)", shot and rgb(shot.BackgroundColor3) == "34,40,37", shot and rgb(shot.BackgroundColor3))
		W:SetFlag("__ui_theme", "Charcoal")
	end
	local mouse = titled("Free mouse")
	check("Free mouse satırında ikon yok", mouse and mouse.Parent and mouse.Parent:FindFirstChildWhichIsA("ImageLabel") == nil)
	check("oyun başına profil seçeneği yok", titled("Separate profiles per game") == nil and W.Config.SetPerGame == nil)
end)

test("Profiles: tablo, sağ tık menüsü, yeniden adlandırma, auto, silme", function()
	local root = W.gui
	local tableFrame = find(root, function(d) return d.Name == "ProfileTable" end)
	check("profil tablosu var", tableFrame ~= nil)
	if not tableFrame then return end
	local head = tableFrame:FindFirstChild("Head")
	local cols = {}
	for _, c in ipairs(head:GetChildren()) do if c.ClassName == "TextButton" or c.ClassName == "TextLabel" then cols[#cols + 1] = { c.Position.X.Scale * 100 + c.Position.X.Offset / 1000, c.Name } end end
	table.sort(cols, function(a, b) return a[1] < b[1] end)
	local names = {}
	for _, c in ipairs(cols) do names[#names + 1] = c[2] end
	check("sütunlar Name, Note, Saved, Settings, Differs, Auto", table.concat(names, ",") == "Name,Note,Saved,Settings,Differs,Auto", table.concat(names, ","))
	local rows = tableFrame:FindFirstChild("Rows")
	local function row(name) return rows:FindFirstChild("Profile_" .. name) end
	local function tags(r)
		local out = {}
		local t = r and find(r, function(d) return d.Name == "Tags" end)
		for _, chip in ipairs(t and t:GetChildren() or {}) do
			local text = chip:FindFirstChild("Text")
			if text then out[#out + 1] = text.Text end
		end
		return table.concat(out, ",")
	end
	check("Default satırı ACTIVE + LOCKED", tags(row("Default")) == "ACTIVE,LOCKED", tags(row("Default")))
	check("eski kartlar yok (Saved, New profile)", find(root, function(d) return d.Name == "ProfileList" end) == nil)

	-- Create
	local holder = find(root, function(d) return d.Name == "CreateProfile" end)
	local box = holder and find(holder, function(d) return d.ClassName == "TextBox" end)
	local action = holder and find(holder, function(d) return d.Name == "Action" end)
	check("Create kutusu tablonun altında, Import yanında", holder and holder.Parent and holder.Parent.Name == "Bottom" and holder.Parent:FindFirstChild("ImportProfile") ~= nil)
	box.Text = "Farm"
	action.Activated:Fire()
	mock.advance(0.2)
	check("Farm oluştu ve satırı var", W.Config:Exists("Farm") and row("Farm") ~= nil)
	local settingsCell = row("Farm") and row("Farm"):FindFirstChild("Settings")
	check("Settings sütununda ayar sayısı", settingsCell and tonumber(settingsCell.Text) and tonumber(settingsCell.Text) > 0, settingsCell and settingsCell.Text)

	-- right click menu
	local function menuItems()
		local menu = find(W.gui, function(d) return d.Name == "ContextMenu" end)
		local list = {}
		for _, c in ipairs(menu and menu:GetChildren() or {}) do if c.ClassName == "TextButton" then list[#list + 1] = c end end
		table.sort(list, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
		local out = {}
		for _, c in ipairs(list) do out[#out + 1] = c.Name end
		return table.concat(out, ","), menu
	end
	row("Default").MouseButton2Click:Fire()
	mock.advance(0.05)
	check("Default menüsü: Duplicate, Share code", (menuItems()) == "Duplicate,Share code", (menuItems()))
	row("Farm").MouseButton2Click:Fire()
	mock.advance(0.05)
	local items, menu = menuItems()
	check("tek menü açık", count(W.gui, function(d) return d.Name == "ContextMenu" end) == 1)
	check("Farm menüsü: Overwrite, Rename, Edit note, Duplicate, Share code, Delete", items == "Overwrite,Rename,Edit note,Duplicate,Share code,Delete", items)
	menu:FindFirstChild("Rename").Activated:Fire()
	mock.advance(0.05)
	check("menü kapandı", find(W.gui, function(d) return d.Name == "ContextMenu" end) == nil)
	local dialog = find(W.main, function(d) return d.Name == "Dialog" end)
	local input = dialog and find(dialog, function(d) return d.Name == "Input" end)
	check("Rename penceresinde isim kutusu (dolu)", input and input.Text == "Farm", input and input.Text)
	input.Text = "PvP"
	find(dialog, function(d) return d.ClassName == "TextButton" and d.Name == "Rename" end).Activated:Fire()
	mock.advance(0.1)
	check("Farm → PvP", W.Config:Exists("PvP") and not W.Config:Exists("Farm") and row("PvP") ~= nil and row("Farm") == nil)

	-- sort
	head:FindFirstChild("Name").Activated:Fire()
	mock.advance(0.05)
	local nameHead = head:FindFirstChild("Name")
	check("sıralama oku yok", nameHead:FindFirstChild("Arrow") == nil)
	check("Name'e basınca başlığı accent renginde", nameHead:FindFirstChild("Text").TextColor3 == Lib.Theme.get("accent"))

	-- auto
	local switch = find(row("PvP"), function(d) return d.Name == "Auto" end)
	switch.Activated:Fire()
	mock.advance(0.05)
	check("Auto anahtarı: PvP başlangıçta yüklenir", W.Config:GetAutoLoad() == "PvP", tostring(W.Config:GetAutoLoad()))
	check("Default'ta silme ikonu yok", find(row("Default"), function(d) return d.Name == "Delete" end) == nil)

	-- delete icon
	find(row("PvP"), function(d) return d.Name == "Delete" end).Activated:Fire()
	mock.advance(0.05)
	dialog = find(W.main, function(d) return d.Name == "Dialog" end)
	find(dialog, function(d) return d.ClassName == "TextButton" and d.Name == "Delete" end).Activated:Fire()
	mock.advance(0.1)
	check("PvP silindi, autoload temizlendi", not W.Config:Exists("PvP") and row("PvP") == nil and W.Config:GetAutoLoad() == nil)
end)

test("Info: Status yok; Errors kartında kodun başlığında copy + çöp kutusu", function()
	local root = W.gui
	local function titled(text) return find(root, function(d) return d.ClassName == "TextLabel" and d.Text == text end) end
	check("Status, About, Disconnects kartları yok", titled("Status") == nil and titled("About") == nil and titled("Disconnects") == nil
		and find(root, function(d) return d.Name == "Banner" end) == nil)
	local card = titled("Errors")
	while card and not card:FindFirstChild("Clear", true) do card = card.Parent end
	check("Errors kartında Clear (çöp kutusu)", card ~= nil)
	if not card then return end
	check("eski Copy debug info butonu yok", card:FindFirstChild("Copy debug info", true) == nil)
	local clear = card:FindFirstChild("Clear", true)
	local head = clear.Parent
	local copy = head:FindFirstChild("Copy")
	check("çöp kutusu copy iconunun yanında (aynı başlıkta, solunda)", copy ~= nil and copy.ClassName == "ImageButton" and clear.Position.X.Offset < copy.Position.X.Offset,
		tostring(copy and copy.Position) .. " / " .. tostring(clear.Position))
	-- (the debug info reads these; the mock's game has none)
	local gameProps = rawget(game, "__p")
	gameProps.GameId, gameProps.PlaceId, gameProps.JobId = gameProps.GameId or 1234, gameProps.PlaceId or 5678, gameProps.JobId or ""
	mock.clipboard = nil
	W:ReportError("Test", "boom")
	mock.advance(0.1)
	copy.Activated:Fire()
	local copied = mock.clipboard
	check("copy iconu debug bilgisini kopyalıyor (hatalar dahil)", copied ~= nil and copied:find("executor", 1, true) ~= nil and copied:find("boom", 1, true) ~= nil, tostring(copied))
	clear.Activated:Fire()
	mock.advance(0.1)
	check("çöp kutusu hataları temizliyor", #W:GetErrors() == 0)
	check("hata yokken No errors yazıyor", titled("No errors in this session") ~= nil)
end)

test("Fontlar ve ikonlar: repodan indirilip getcustomasset ile", function()
	local root = os.getenv("LIB_ROOT")
	check("LIB_ROOT var", root ~= nil)
	if not root then return end
	local function serve(prefix, dir)
		mock.httpRoutes[prefix] = function(url)
			local f = assert(io.open(dir .. url:match("([^/]+)$"), "rb"))
			local body = f:read("a") f:close()
			return body
		end
	end
	serve("refs/heads/main/qustah/icons/", root .. "/qustah/icons/")
	local oldAsset = getcustomasset
	getcustomasset = function(path) return "rbxasset://custom/" .. path end

	-- fonts
	local Fonts = Lib.Fonts
	check("font listesi: Ubuntu, Jura, Roboto, Michroma, Josefin Sans", table.concat(Fonts.available(), ",") == "Ubuntu,Jura,Roboto,Michroma,Josefin Sans", table.concat(Fonts.available(), ","))
	check("varsayılan font Ubuntu", Fonts.current == "Ubuntu" and W.Lib.Flags.__ui_font == "Ubuntu", tostring(Fonts.current))
	mock.advance(0.5)
	local written = false
	for path in pairs(mock.files) do if path:find("QustahUI/fonts", 1, true) then written = true end end
	check("font indirilmiyor (Roblox'un kendi aileleri)", not written)
	check("Jura: Roblox'un kendi ailesi", Fonts.family("Jura") == "rbxasset://fonts/families/Jura.json", tostring(Fonts.family("Jura")))
	Fonts.set("Ubuntu")
	mock.advance(0.1)
	local text = find(W.gui, function(d) return d.ClassName == "TextLabel" and not d:GetAttribute("QCode") and not d:GetAttribute("QFixedFont") end)
	local family = text and text.FontFace and text.FontFace.args and text.FontFace.args[1]
	check("yazılar Ubuntu'da", family ~= nil and family == Fonts.family("Ubuntu"), tostring(family))
	check("Code font seçeneği yok", find(W.gui, function(d) return d.ClassName == "TextLabel" and d.Text == "Code font" end) == nil)

	-- icons: the lib's own sheet (qustah/icons, filled, 14 - 30 px) for its icons, asset ids for the rest
	local Icons = Lib.Icons
	check("ikon boyutlari 14,16,20,24,28,30", table.concat(Icons.Sizes, ",") == "14,16,20,24,28,30")
	check("fitSize: 10->14, 12->14, 15->16, 18->20, 22->24, 40->30", Icons.fitSize(10) == 14 and Icons.fitSize(12) == 14 and Icons.fitSize(15) == 16
		and Icons.fitSize(18) == 20 and Icons.fitSize(22) == 24 and Icons.fitSize(40) == 30)
	Icons._resetSheets()
	-- (the mock's boxes are 100 x 20 on screen: these say how big they are)
	local house = Icons.Image("house", { Size = UDim2.fromOffset(16, 16) })
	house.AbsoluteSize = Vector2.new(16, 16)
	house.Parent = W.gui
	mock.advance(0.5)
	Icons.Apply(house, "house")
	local page = mock.files["QustahUI/icons/qustah-v29-qustah-v29-1.png"]
	check("qustah sayfasi indirildi (v29)", page ~= nil)
	check("house: qustah sayfasindan", tostring(house.Image):find("qustah%-v29") ~= nil, house.Image)
	check("house 16 px hucre", house.ImageRectSize == Vector2.new(16, 16), tostring(house.ImageRectSize))
	check("sayfa ikonu Pixelated", house.ResampleMode == Enum.ResamplerMode.Pixelated, tostring(house.ResampleMode))
	local crown = Instance.new("ImageLabel")
	crown.Size = UDim2.fromOffset(16, 16)
	crown.AbsoluteSize = Vector2.new(16, 16)
	crown.Parent = W.gui
	Icons.Apply(crown, "crown")
	mock.advance(0.2)
	check("sadece sayfada olan ikon (frog) bulunuyor", Icons.Get("frog") ~= nil and Icons.Get("record") ~= nil)
	check("hub ikonu crown da sayfada", tostring(crown.Image):find("qustah%-v29") ~= nil, crown.Image)
	local anchor = Instance.new("ImageLabel")
	anchor.Size = UDim2.fromOffset(16, 16)
	anchor.AbsoluteSize = Vector2.new(16, 16)
	anchor.Parent = W.gui
	Icons.Apply(anchor, "anchor")
	mock.advance(0.2)
	check("sayfada olmayan ikon: lucide asset id (indirme yok)", tostring(anchor.Image):find("^rbxassetid://") ~= nil, anchor.Image)
	local fetched = false
	for path in pairs(mock.files) do if path:find("lucide", 1, true) then fetched = true end end
	check("lucide sayfası indirilmiyor", not fetched)
	local own = Instance.new("ImageLabel")
	own.Parent = W.gui
	Icons.Apply(own, "rbxassetid://1234567")
	check("rbxassetid ile kendi ikonu", own.Image == "rbxassetid://1234567", own.Image)
	-- a size asked for goes to the nearest allowed one, centre kept
	local holder = Instance.new("Frame")
	holder.Parent = W.gui
	local small = Icons.themed(holder, "x", 12, "muted", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0) })
	check("12 px istenen ikon 14 px, ortasi ayni", small.Size == UDim2.fromOffset(14, 14) and small.Position == UDim2.new(0, 9, 0.5, 0), small.Size.X.Offset .. " " .. small.Position.X.Offset)
	-- UI scale 125 %: a 14 px icon would be 17.5 px on screen -> 16 px (16 / 1.25 = 12.8 in the menu)
	local scaled = Icons.Image("house", { Size = UDim2.fromOffset(14, 14) })
	rawset(scaled, "__uiScale", 1.25)
	scaled.Parent = holder
	Icons.Apply(scaled, "house")
	mock.advance(0.1)
	check("%125 olcekte 14 px ikon ekranda 16 px", math.abs(scaled.Size.X.Offset - 12.8) < 0.01, scaled.Size.X.Offset)
	holder:Destroy() crown:Destroy() anchor:Destroy()
	getcustomasset = oldAsset
	house:Destroy()
end)

test("Dock: sağ / alt / kenar çubuğu (Side)", function()
	local tab = W.Tabs[1]
	local width = W.width
	W:SetDockSide("Side")
	mock.advance(0.1)
	check("Side: dock pencerenin içinde", W.dock.Parent == W.main, tostring(W.dock.Parent))
	check("Side: pencere kenar çubuğu kadar genişledi", W.main.Size.X.Offset == width + 132, W.main.Size.X.Offset)
	check("Side: sayfalar kenar çubuğunun sağında", W.body.Position.X.Offset == 132 and W.body.Size.X.Offset == -132, tostring(W.body.Position))
	check("Side: sekme adı görünüyor", tab.nameLabel.Visible == true)
	check("Side: sekme satırı tam genişlik", tab.button.Size.X.Offset == 116, tab.button.Size.X.Offset)
	check("Side: tutamaç gizli", W.dockGrip.Visible == false)
	local plain = W:Tab({ Title = "Plain" })
	mock.advance(0.1)
	check("Side: ikonsuz sekmede harf yok, ad solda", plain.icon.Visible == false and plain.nameLabel.Position.X.Offset == 12, plain.nameLabel.Position.X.Offset)
	W:SetDockSide("Right")
	mock.advance(0.1)
	check("Right: ikonsuz sekmede harf geri geldi", plain.icon.Visible == true and plain.icon.Text == "P")
	plain:SetHidden(true)
	W:SetDockSide("Side")
	mock.advance(0.1)
	local card = W._profileCard
	check("Side: profil kartı altta, yuvarlak avatar gizli", card and card.Visible and card.AnchorPoint.Y == 1 and not W._profile.Visible and not W._profileLine.Visible)
	check("Side: kartta oyuncunun adı", card and card.Name and card:FindFirstChild("Name").Text == me.DisplayName, card and card:FindFirstChild("Name").Text)
	mock.advance(1.2)
	check("Side: oturum süresi yazıyor", card and card:FindFirstChild("Session").Text:match("^%d%d:%d%d:%d%d$") ~= nil, card and card:FindFirstChild("Session").Text)
	W:SetAnonymous(true)
	check("Side: anonimken \"Anonymous\", avatar boş", card:FindFirstChild("Name").Text == "Anonymous" and card:FindFirstChild("Avatar").Image == "")
	W:SetAnonymous(false)
	check("Side: anonim kapanınca ad geri", card:FindFirstChild("Name").Text == me.DisplayName)
	W:SetDockSide("Bottom")
	mock.advance(0.1)
	check("Bottom: dock dışarıda", W.dock.Parent == W.dockParent)
	check("Bottom: sekme adı gizli, yuvarlak buton", tab.nameLabel.Visible == false and tab.button.Size.X.Offset == 30)
	check("Bottom: profil kartı gizli, yuvarlak avatar görünüyor", not W._profileCard.Visible and W._profile.Visible)
	W:SetDockSide("Right")
	mock.advance(0.1)
	check("Right: pencere eski genişlikte, sayfalar solda", W.main.Size.X.Offset == width and W.body.Position.X.Offset == 0)
	check("Right: tutamaç görünüyor", W.dockGrip.Visible == true)
end)

test("Yazı genişliği fontun kendi harf ölçüleriyle", function()
	local Fonts, Util = Lib.Fonts, Lib.Util
	Fonts.set("Ubuntu")
	mock.advance(0.5)
	local measured = Fonts.textWidth("Saved", 9, Enum.Font.GothamMedium)
	check("Ubuntu harfleri ölçüldü", measured ~= nil)
	-- drawn at 10 px (9 -> 10): S = 0.68, a v e d = 0.55 each, per px
	local want = (0.68 + 4 * 0.55) * 10
	check("Saved: gerçek font genişliği (büyük harf daha geniş)", measured and math.abs(measured - want) < 0.01, tostring(measured) .. " / " .. want)
	check("Util.textWidth onu kullanıyor", math.abs(Util.textWidth("Saved", 9, Enum.Font.GothamMedium) - (measured or 0)) < 0.01)
	check("boşluk da sayılıyor", Fonts.textWidth("a a", 12, Enum.Font.Gotham) > Fonts.textWidth("aa", 12, Enum.Font.Gotham))
end)

test("Transparency bütün pencereye uygulanıyor (en fazla %25)", function()
	local Theme = Lib.Theme
	local card, stroke_
	for object, entry in pairs(Theme._bound()) do
		if object.Parent and entry.BackgroundColor3 == "card" and object.BackgroundTransparency == 0 and object:IsDescendantOf(W.main) then card = card or object end
		if object.Parent and object.ClassName == "UIStroke" and entry.Color == "edge" and object:IsDescendantOf(W.main) and object.Transparency == 0 then stroke_ = stroke_ or object end
	end
	check("kart ve çerçeve bulundu", card ~= nil and stroke_ ~= nil)
	W:SetBackgroundTransparency(0.25)
	check("pencere %25", math.abs(W.main.BackgroundTransparency - 0.25) < 0.001, W.main.BackgroundTransparency)
	-- (a card lies on the window's back: its fill fades further, so the game shows through it about as much)
	check("kart pencerenin üstünde daha da şeffaf (çift katman koyu durmasın)", card and math.abs(card.BackgroundTransparency - (1 - 0.75 ^ 6)) < 0.001, card and card.BackgroundTransparency)
	check("çerçeve de %25", stroke_ and math.abs(stroke_.Transparency - 0.25) < 0.001, stroke_ and stroke_.Transparency)
	W:SetBackgroundTransparency(0)
	check("0'da hepsi eski haline", card and card.BackgroundTransparency == 0 and W.main.BackgroundTransparency == 0 and stroke_.Transparency == 0)
	W:SetFlag("__ui_transparency", 60)
	mock.advance(0.1)
	check("slider en fazla 25", (W:GetFlag("__ui_transparency") or 0) <= 25, tostring(W:GetFlag("__ui_transparency")))
	W:SetFlag("__ui_transparency", 0)
	mock.advance(0.1)
end)

test("Yazı genişliği seçili fonta göre ölçülüyor", function()
	local Util = Lib.Util
	local base = Util.textWidth("Hello world", 12, Enum.Font.Gotham)
	check("eski Gotham oran kodu yok", Util._fontFactor == nil and Lib.Fonts.widthFactor == nil and Lib.Fonts.Width == nil and Lib.Fonts.measure == nil)
	local laid = 0
	local frame = Instance.new("Frame")
	frame.Parent = W.gui
	Util.onTextMetrics(frame, function() laid = laid + 1 end)
	W:SetFlag("__ui_font", "Michroma")
	mock.advance(0.2)
	local wide = Util.textWidth("Hello world", 12, Enum.Font.Gotham)
	-- (the mock's fonts all measure alike: what changes is Michroma's smaller drawn size, its wide-font fit)
	check("Michroma: kendi ölçüsüyle", math.abs(wide - base) > 1, base .. " -> " .. wide)
	check("font değişince düzen yenilendi", laid > 0, laid)
	-- each font picks its text size; one changed by hand stays until the next font
	W:SetFlag("__ui_font", "Jura")
	mock.advance(0.1)
	check("Jura seçince yazı boyutu Large", W.Lib.Flags.__ui_textsize == "Large", tostring(W.Lib.Flags.__ui_textsize))
	W:SetFlag("__ui_textsize", "Small")
	mock.advance(0.1)
	check("elle değiştirilen boyut kalıyor", W.Lib.Flags.__ui_textsize == "Small")
	W:SetFlag("__ui_font", "Josefin Sans")
	mock.advance(0.1)
	check("Josefin Sans seçince Small", W.Lib.Flags.__ui_textsize == "Small")
	-- a profile that loads a font keeps its own text size
	W.Config:Apply({ __ui_font = "Jura", __ui_textsize = "Normal" })
	W.Config:Apply({ __ui_textsize = "Normal", __ui_font = "Roboto" })
	mock.advance(0.1)
	check("profil yüklenirken boyut ezilmiyor", W.Lib.Flags.__ui_textsize == "Normal" and Lib.Fonts.current == "Roboto", tostring(W.Lib.Flags.__ui_textsize))
	W:SetFlag("__ui_font", "Ubuntu")
	W:SetFlag("__ui_textsize", "Normal")
	mock.advance(0.2)
	frame:Destroy()
end)

test("CreateWindow Defaults ve okunaklı profil dosyası", function()
	local D = Lib:CreateWindow({ Title = "DefTest", Folder = "QustahDefTest", Defaults = { d_on = true, d_mode = "B" } })
	local tab = D:Tab({ Title = "T", Icon = "home" })
	local card = tab:Page("P"):Card({ Title = "C" })
	local toggle = card:Toggle({ Title = "On", Flag = "d_on", Default = false })
	local seg = card:Segment({ Title = "Mode", Flag = "d_mode", Items = { "A", "B" }, Default = "A" })
	mock.advance(0.2)
	check("Defaults: toggle açık başladı", toggle.Value == true, tostring(toggle.Value))
	check("Defaults: segment B başladı", seg.Value == "B", tostring(seg.Value))
	check("Defaults: reset varsayılanı da bu", D.Config.Defaults.d_on == true and D.Config.Defaults.d_mode == "B")
	local text = Lib.Util.prettyJSON({ version = 1, flags = { b = 2, a = { "x", "y" } } })
	check("prettyJSON: sıralı ve girintili", text:find('"a": %["x", "y"%]') ~= nil and text:find("\n  \"flags\"") ~= nil and text:find('"a"') < text:find('"b"'), text)
	D:Destroy()
	-- profile files name settings in words; they load back into the same flags
	W:SetFlag("t_style", "Stripes")
	local saved = W.Config:Save("words")
	local file
	for path, body in pairs(mock.files) do if path:find("words.json", 1, true) then file = body end end
	check("profil kaydedildi", saved == true and file ~= nil)
	check("dosyada 't style' (alt çizgisiz)", file and file:find('"t style"', 1, true) ~= nil and not file:find('"t_style"', 1, true), file and file:sub(1, 200))
	W:SetFlag("t_style", "Smooth")
	W.Config:Load("words")
	check("yükleyince aynı flag", W.Flags.t_style == "Stripes", tostring(W.Flags.t_style))
	W:SetFlag("t_style", "Smooth")
	check("eski ad da okunuyor", W.Config.flagKey("t_style") == "t_style" and W.Config.flagKey("ui accent") == "__ui_accent")
	-- only what differs from the defaults is written; loading puts everything else back to its default
	W:SetFlag("t_style", "Smooth")
	W.Config:Save("plain")
	local plain
	for path, body in pairs(mock.files) do if path:find("plain.json", 1, true) then plain = body end end
	check("varsayılanda olan ayar dosyaya yazılmıyor", plain and not plain:find('"t style"', 1, true), plain and plain:sub(1, 200))
	W:SetFlag("t_style", "Stripes")
	W.Config:Load("plain")
	check("yazılmayan ayar yüklenince varsayılana dönüyor", W.Flags.t_style == "Smooth", tostring(W.Flags.t_style))
end)

test("Küçük yazılar okunaklı boyutta çiziliyor", function()
	local small = Instance.new("TextLabel")
	small.TextSize = 9
	small.Parent = W.gui
	local body = Instance.new("TextLabel")
	body.TextSize = 11
	body.Parent = W.gui
	mock.advance(0.2)
	check("9 px -> 10 px", small.TextSize == 10, small.TextSize)
	check("11 px -> 12 px", body.TextSize == 12, body.TextSize)
	check("genişlik hesabı çizilen boyutla (9 -> 10)", math.abs(Lib.Fonts.drawnScale(9) / Lib.Fonts.drawnScale(10) - (10 / 9) / (11 / 10)) < 0.01)
	small:Destroy() body:Destroy()
end)

test("lib hata kaydı boş", function()
	local errors = W:GetErrors()
	local text = {}
	for _, e in ipairs(errors) do text[#text + 1] = tostring(e.source) .. ": " .. tostring(e.message) end
	check("hata yok", #errors == 0, table.concat(text, " | "))
	local co = {}
	for _, e in ipairs(mock.errors) do co[#co + 1] = e:sub(1, 300) end
	check("thread hatası yok", #mock.errors == 0, table.concat(co, "\n"))
end)

test("menü tuşu: oyun tuşu işlemiş olsa da (Shift Lock) menüyü açıp kapatıyor", function()
	local UIS = game:GetService("UserInputService")
	local before = W.visible
	UIS.InputBegan:Fire({ KeyCode = Enum.KeyCode.RightShift, UserInputType = Enum.UserInputType.Keyboard }, true)
	mock.advance(0.5)
	check("processed RightShift → Toggle", W.visible ~= before, tostring(W.visible))
	UIS.InputBegan:Fire({ KeyCode = Enum.KeyCode.RightShift, UserInputType = Enum.UserInputType.Keyboard }, false)
	mock.advance(0.5)
	check("ikinci basış geri açıyor", W.visible == before, tostring(W.visible))
end)

test("Sayfa adları başlığın ortasında; kenar çubuğunda Settings sayfaları da başlıkta", function()
	local settings = W.settingsTab
	W:SetPageTabs("Header")
	W:SetDockSide("Side")
	W:SelectTab(settings)
	mock.advance(0.3)
	check("Side: başlıkta Dashboard / Settings düğmesi yok", W.headerTabs.Visible == false)
	check("Side: Settings sayfaları başlıkta", W.pagesInHeader == true and W.stripHolder.Parent == W.main)
	check("ortaya hizalı (AnchorPoint 0.5)", W.stripHolder.AnchorPoint.X == 0.5, tostring(W.stripHolder.AnchorPoint.X))
	W:SetDockSide("Right")
	mock.advance(0.3)
	check("Right: Settings sayfaları yine satırda", W.pagesInHeader == false)
	W:SelectTab(W.Tabs[1])
	mock.advance(0.1)
end)

test("SetActive: kenar çubuğunda nokta satırın sağ ucunda, dock'ta butonun köşesinde", function()
	local tab = W.Tabs[1]
	W:SetDockSide("Side")
	tab:SetActive(true)
	mock.advance(0.2)
	local dot = tab._activeDot
	check("Side: nokta sağ uçta, ortalı", dot and dot.Visible and dot.AnchorPoint.Y == 0.5 and dot.Position.X.Offset == -12)
	W:SetDockSide("Right")
	mock.advance(0.2)
	check("Right: nokta köşede", dot.AnchorPoint.Y == 1 and dot.Position.X.Offset == -1)
	tab:SetActive(false)
	check("SetActive(false) gizliyor", dot.Visible == false)
end)

io.write(("[lib] %d geçti, %d kaldı\n"):format(results.pass, results.fail))
for _, r in ipairs(results.list) do
	if not r.ok then io.write("  FAIL ", r.name, "\n         ", tostring(r.detail), "\n") end
end
os.exit(results.fail == 0 and 0 or 1)
