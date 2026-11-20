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

test("lib hata kaydı boş", function()
	local errors = W:GetErrors()
	local text = {}
	for _, e in ipairs(errors) do text[#text + 1] = tostring(e.source) .. ": " .. tostring(e.message) end
	check("hata yok", #errors == 0, table.concat(text, " | "))
	local co = {}
	for _, e in ipairs(mock.errors) do co[#co + 1] = e:sub(1, 300) end
	check("thread hatası yok", #mock.errors == 0, table.concat(co, "\n"))
end)

io.write(("[lib] %d geçti, %d kaldı\n"):format(results.pass, results.fail))
for _, r in ipairs(results.list) do
	if not r.ok then io.write("  FAIL ", r.name, "\n         ", tostring(r.detail), "\n") end
end
os.exit(results.fail == 0 and 0 or 1)
