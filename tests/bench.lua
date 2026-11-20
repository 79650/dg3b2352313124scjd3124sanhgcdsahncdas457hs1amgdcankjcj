-- ESP benchmark in the mock: 29 other players with fakehealth + combat.mode, ESP on, 60 frames/s virtual for 10 s
local W, L, mock = ...
local V3 = Vector3.new
for _, p in ipairs(mock.PS:GetPlayers()) do if p ~= mock.PS.LocalPlayer then mock.removePlayer(p) end end
local list = {}
for i = 1, 29 do
	local p = mock.player("P" .. i, V3((i % 6) * 8 - 20, 5, -20 - math.floor(i / 6) * 15))
	mock.value("IntValue", "fakehealth", 1000 + i * 37, p.Character)
	p.Character.Humanoid.MaxHealth = 3000
	local c = mock.folder("combat", p.Character)
	local m = mock.value("IntConstrainedValue", "mode", 40, c) m.MaxValue = 100
	list[#list + 1] = p
end
mock.cam.CFrame = CFrame.new(0, 10, 30)
local function count()
	local n = 0
	for _, d in ipairs(game:GetDescendants()) do
		local o = d while o and o.Name ~= "QustahESP" do o = o.Parent end
		if o then n = n + 1 end
	end
	return n
end
local function run(label, seconds)
	collectgarbage() collectgarbage()
	local t0 = os.gettimeofday()
	local steps = 0
	local target = mock.now + seconds
	while mock.now < target - 1e-9 do
		-- values change every frame like in a fight
		for i, p in ipairs(list) do
			local f = p.Character:FindFirstChild("fakehealth")
			if f then f.Value = 1000 + (steps * 7 + i * 13) % 2000 end
		end
		mock.frame(1 / 60) steps = steps + 1
	end
	local cpu = os.gettimeofday() - t0
	io.stdout:write(string.format("BENCH %-34s cpu %.3f s for %d frames  ->  %.3f ms/frame   instances %d\n", label, cpu, steps, cpu * 1000 / steps, count()))
end
W:SetFlag("esp_enabled", true)
W:SetFlag("esp_mdstyle", "Smooth") W:SetFlag("esp_hpstyle", "Smooth")
run("ESP on, Smooth bars", 10)
W:SetFlag("esp_mdstyle", "Stripes") W:SetFlag("esp_hpstyle", "Stripes")
run("ESP on, Stripes both bars", 10)
W:SetFlag("esp_chams", false)
run("ESP on, Stripes, chams off", 10)
W:SetFlag("esp_enabled", false)
run("ESP off", 10)
os.exit(0)
