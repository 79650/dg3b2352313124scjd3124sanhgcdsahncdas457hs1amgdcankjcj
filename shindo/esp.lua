-- Qustāh ESP · Shindo Life
-- The overhead ESP of QustahShindo, kept out of the UI library: the bar colour presets, the per-player panels
-- (BillboardGui + chams Highlight, 25 updates a second) and the menu preview with its colour / style / opacity
-- capsules. Game data (health, mode, dodge) comes from the hub through callbacks.
-- Usage: local Esp = loadstring(game:HttpGet(<raw link of shindo/esp.lua>))()(Lib)
--        Esp.Create({ State = esp, Settings = settings, ... })      -- starts the panels
--        Esp.Preview(card, { Settings = settings, Renderer = esp, Read = fn, Controls = rows })
return function(Lib)
local Util = Lib.Util
local Esp = { Version = "1.1.0" }

-- The stripes as one tiled picture: a 6 x 8 PNG with the same white "/" steps the frame stripes draw (four 2 px rows,
-- every 6 px), written once to the executor's folder and loaded with getcustomasset. Two objects a bar instead of
-- about forty. Without getcustomasset / writefile (or if it fails) the stripes are built from frames as before.
Esp.StripeTile = "iVBORw0KGgoAAAANSUhEUgAAAAYAAAAICAYAAADaxo44AAAAIElEQVR42mP4//8/AxKGAwZiJFDECUpgmIJXAqudOCUAhtOnWekJ08YAAAAASUVORK5CYII="
local function fromBase64(text)
    local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    local out, bits, count = {}, 0, 0
    for i = 1, #text do
        local index = alphabet:find(text:sub(i, i), 1, true)
        if index then
            bits, count = bits * 64 + index - 1, count + 6
            if count >= 8 then
                count = count - 8
                out[#out + 1] = string.char(math.floor(bits / 2 ^ count) % 256)
                bits = bits % 2 ^ count
            end
        end
    end
    return table.concat(out)
end
function Esp.StripeImage()
    if Esp.stripeImage ~= nil then return Esp.stripeImage or nil end
    Esp.stripeImage = false
    if type(getcustomasset) ~= "function" or type(writefile) ~= "function" then return nil end
    local ok, asset = pcall(function()
        if type(makefolder) == "function" and type(isfolder) == "function" and not isfolder("QustahShindo") then makefolder("QustahShindo") end
        local path = "QustahShindo/esp_stripes.png"
        writefile(path, fromBase64(Esp.StripeTile))
        return getcustomasset(path)
    end)
    if ok and type(asset) == "string" and asset ~= "" then Esp.stripeImage = asset end
    return Esp.stripeImage or nil
end

Esp.Palettes = (function()
    local function hex(h) return Color3.fromRGB(tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16)) end
    local modePresets = {
        { "Ocean", hex("1d3fa8"), hex("3b82f6"), hex("67e8f9") },
        { "Aurora", hex("7c3aed"), hex("22d3ee"), hex("34d399") },
        { "Sunset", hex("9d2c8f"), hex("f43f5e"), hex("fdba74") },
        { "Toxic", hex("166534"), hex("22c55e"), hex("d9f99d") },
        { "Violet", hex("4c1d95"), hex("a855f7"), hex("f5b8ff") },
        { "Gold", hex("92400e"), hex("f59e0b"), hex("fde68a") },
    }
    local healthPresets = {
        { "Classic", hex("e5484d"), hex("f5a524"), hex("3dd68c") },
        { "Ice", hex("4f5bd5"), hex("3fa9f5"), hex("9ff3ff") },
        { "Mint", hex("0f766e"), hex("2dd4bf"), hex("d1fae5") },
        { "Ember", hex("7f1d1d"), hex("f05a28"), hex("ffd166") },
        { "Candy", hex("ff4d8d"), hex("c06cff"), hex("7cc8ff") },
        { "Mono", hex("3a3d45"), hex("8a8f9a"), hex("f4f5f7") },
    }
    for _, list in ipairs({ modePresets, healthPresets }) do
        for _, preset in ipairs(list) do list[preset[1]] = preset end
    end
    -- colour of a preset at p: along its stops (entries 2..n)
    local function presetAt(preset, p)
        p = math.clamp(p or 1, 0, 1)
        local count = #preset - 1
        local scaled = p * (count - 1)
        local index = math.min(math.floor(scaled), count - 2)
        return preset[2 + index]:Lerp(preset[3 + index], scaled - index)
    end
    return { Mode = modePresets, Health = healthPresets, ColorAt = presetAt }
end)()

function Esp.Create(cfg)
    local esp = cfg.State or {}
    local Players = cfg.Players or game:GetService("Players")
    local LocalPlayer = cfg.LocalPlayer or Players.LocalPlayer
    local Workspace = cfg.Workspace or workspace
    local settings, clamp = cfg.Settings, math.clamp
    local healthValue = cfg.Health or function(h) return h.Health end
    local healthMax = cfg.MaxHealth or function(h, value) return math.max(h.MaxHealth, value or 0, 1) end
    local report = cfg.Error or function() end
    local alive, links = true, {}
    esp.Panels = {}
    esp.Colors = { back = Color3.fromRGB(18,18,18), split = Color3.fromRGB(8,8,8), red = Color3.fromRGB(195,85,85), green = Color3.fromRGB(115,185,130) }
    esp.DodgeImage = cfg.DodgeImage or ""
    esp.ModeInfo = cfg.Mode or esp.ModeInfo or function() end
    esp.DodgeCooldown = cfg.Dodge or esp.DodgeCooldown or function() end
    function esp.Compact(number)
        number = math.max(tonumber(number) or 0, 0)
        local divisor, suffix = 1, ""
        if number >= 1e9 then divisor, suffix = 1e9, "B"
        elseif number >= 1e6 then divisor, suffix = 1e6, "M"
        elseif number >= 1e3 then divisor, suffix = 1e3, "K"
        else return tostring(math.floor(number + 0.5)) end
        local value = number / divisor
        if value >= 999.5 and divisor < 1e9 then
            divisor, suffix = divisor * 1e3, divisor == 1e3 and "M" or "B"
            value = number / divisor
        end
        local decimals = value < 10 and 2 or value < 100 and 1 or 0
        local text = string.format("%." .. decimals .. "f", value)
        if decimals > 0 then text = text:gsub("%.?0+$", "") end
        return text .. suffix
    end
    -- where the billboards and highlights live: gethui() (hidden from the game) > CoreGui > PlayerGui
    function esp.Root()
        if esp.Folder and esp.Folder.Parent then return esp.Folder end
        local parent
        local ok, hidden = pcall(function() return gethui and gethui() end)
        if ok and typeof(hidden) == "Instance" then parent = hidden end
        if not parent then
            local okCore = pcall(function()
                local test = Instance.new("Folder")
                test.Parent = game:GetService("CoreGui")
                test:Destroy()
            end)
            if okCore then parent = game:GetService("CoreGui") end
        end
        parent = parent or LocalPlayer:FindFirstChildOfClass("PlayerGui")
        local folder = Instance.new("Folder")
        folder.Name = cfg.Name or "ESP"
        folder.Parent = parent
        esp.Folder = folder
        return folder
    end

    function esp.New(class, parent, props)
        local object = Instance.new(class)
        for property, value in pairs(props) do object[property] = value end
        object.Parent = parent
        return object
    end
    -- The 300 x 78 block, built inside `parent` (the BillboardGui in game, a plain frame in the menu preview).
    -- Returns the panel: its parts and the segment counts it was built with.
    local panelRenderer = Esp.PanelRenderer(settings, {
        HealthColor = cfg.HealthColor, ModeColor = cfg.ModeColor, Colors = esp.Colors,
        DodgeImage = esp.DodgeImage, Format = esp.Compact,
    })
    function esp.BuildPanel(parent)
        return panelRenderer.BuildPanel(parent)
    end
    function esp.UpdatePanel(panel, info)
        panelRenderer.UpdatePanel(panel, info)
    end
    esp.SetIf = panelRenderer.SetIf

    -- one entry per player: the billboard on the head and the highlight on the character (rebuilt when the character,
    -- its head or the segment counts change)
    function esp.DropPanel(plr)
        local item = esp.Panels[plr]
        if not item then return end
        pcall(function() item.gui:Destroy() end)
        if item.highlight then item.highlight:Destroy() end
        esp.Panels[plr] = nil
    end
    function esp.PanelFor(plr, char, head)
        local item = esp.Panels[plr]
        if item and (item.char ~= char or item.head ~= head or not item.gui.Parent) then
            esp.DropPanel(plr)
            item = nil
        end
        if item then return item end
        local root = esp.Root()
        local gui = esp.New("BillboardGui", root, { Name = plr.Name, Adornee = head, Size = UDim2.fromOffset(300, 78), StudsOffset = Vector3.new(0, 3, 0),
            AlwaysOnTop = true, MaxDistance = settings.ESP_MaxDist, Enabled = false, ResetOnSpawn = false })
        item = { char = char, head = head, gui = gui, lastRefresh = 0 }
        esp.Panels[plr] = item
        return item
    end
    function esp.HidePanel(item)
        if item.gui.Parent then esp.SetIf(item.gui, "Enabled", false) end
        if item.highlight and item.highlight.Parent then esp.SetIf(item.highlight, "Enabled", false) end
    end
    -- ESP off (or no camera): the panels and highlights are removed, not kept hidden (Stripes alone are ~70 objects a
    -- panel); they are built again as players come into view
    function esp.DropAll()
        esp.Selection = nil
        for plr in pairs(esp.Panels) do esp.DropPanel(plr) end
    end
    esp.StyleKeys = { "Name", "User", "TextSize", "Distance", "HealthText", "HealthBar", "ModeBar", "ModeText",
        "HealthPreset", "ModePreset", "HealthBarStyle", "ModeBarStyle", "HealthBarOpacity", "ModeBarOpacity" }
    function esp.SelectPlayers(camera, now, limit)
        local camPos = camera.CFrame.Position
        local candidates = {}
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LocalPlayer then
                local char = plr.Character
                local head = char and char:FindFirstChild("Head")
                local root = char and char:FindFirstChild("HumanoidRootPart")
                local hum = char and char:FindFirstChildOfClass("Humanoid")
                if head and head:IsA("BasePart") and root and root:IsA("BasePart") and hum then
                    local dist = (camPos - root.Position).Magnitude
                    local pinned = settings.Pins[plr.UserId] == true
                    if pinned or dist <= settings.ESP_MaxDist then
                        candidates[#candidates + 1] = { plr = plr, char = char, head = head, root = root, hum = hum, dist = dist, pinned = pinned }
                    end
                end
            end
        end
        table.sort(candidates, function(a, b)
            if a.dist == b.dist then return a.plr.UserId < b.plr.UserId end
            return a.dist < b.dist
        end)
        local entries = {}
        local normal = 0
        for _, c in ipairs(candidates) do
            if c.pinned then
                entries[#entries + 1] = c
            elseif normal < limit then
                normal += 1
                entries[#entries + 1] = c
            end
        end
        return { entries = entries, refreshAt = now + 0.25, camera = camera,
            pins = settings.Pins, range = settings.ESP_MaxDist, limit = limit }
    end
    function esp.UpdatePanels()
        local camera = Workspace.CurrentCamera
        if not settings.ESP_Enabled or not camera then
            if esp.Selection or next(esp.Panels) then esp.DropAll() end
            return
        end
        local now = os.clock()
        local limit = clamp(math.floor(settings.PlayerLimit or 30), 5, 30)
        local selection = esp.Selection
        if not selection or now >= selection.refreshAt or selection.camera ~= camera
            or selection.limit ~= limit or selection.range ~= settings.ESP_MaxDist or selection.pins ~= settings.Pins then
            selection = esp.SelectPlayers(camera, now, limit)
            esp.Selection = selection
        end
        local selected, camPos = {}, camera.CFrame.Position
        esp.Style = esp.Style or {}
        for _, key in ipairs(esp.StyleKeys) do
            if esp.Style[key] ~= settings[key] then
                esp.Style[key] = settings[key]
                esp.StyleRevision = (esp.StyleRevision or 0) + 1
            end
        end
        for _, c in ipairs(selection.entries) do
            if c.plr.Parent and c.plr.Character == c.char and c.head.Parent == c.char
                and c.root.Parent == c.char and c.hum.Parent == c.char then
                c.dist = (camPos - c.root.Position).Magnitude
                if c.pinned or c.dist <= settings.ESP_MaxDist then
                    selected[c.plr] = true
                    local ok, err = pcall(esp.RefreshPanel, c, now, camera)
                    if not ok then
                        local item = esp.Panels[c.plr]
                        if item then esp.HidePanel(item) end
                        report("ESP", err)
                    end
                end
            end
        end
        for plr, item in pairs(esp.Panels) do
            if plr.Parent == nil or plr.Character ~= item.char or not item.head.Parent
                or (not selected[plr] and now - (item.lastSelected or 0) > 2) then
                esp.DropPanel(plr)
            elseif not selected[plr] then
                esp.HidePanel(item)
            end
        end
    end
    function esp.RefreshPanel(c, now, camera)
        -- Test the same camera-relative offset used by BillboardGui. Only the panel's data is throttled.
        local point, onScreen = camera:WorldToViewportPoint(c.head.Position + camera.CFrame.UpVector * 3)
        local visible = onScreen and point.Z > 0
        local chams = settings.Chams and (visible or not settings.OffscreenSleep)
        if not visible and not chams then
            local existing = esp.Panels[c.plr]
            if existing then esp.HidePanel(existing) end
            return
        end
        local item = esp.PanelFor(c.plr, c.char, c.head)
        item.lastSelected = now
        local wasVisible = item.gui.Enabled
        esp.SetIf(item.gui, "MaxDistance", c.pinned and 1e9 or settings.ESP_MaxDist)
        esp.SetIf(item.gui, "Enabled", visible)
        if chams and (not item.highlight or not item.highlight.Parent) then
            item.highlight = esp.New("Highlight", esp.Root(), { Name = c.plr.Name, Adornee = c.char,
                DepthMode = Enum.HighlightDepthMode.AlwaysOnTop, Enabled = false })
        end
        local h = item.highlight
        if h and h.Parent then
            esp.SetIf(h, "Enabled", chams)
            if chams then
                esp.SetIf(h, "FillColor", settings.ChamsColor)
                esp.SetIf(h, "OutlineColor", settings.ChamsOutline)
                esp.SetIf(h, "FillTransparency", settings.ChamsFill)
                esp.SetIf(h, "OutlineTransparency", settings.ChamsOutlineAlpha)
            end
        end
        if not visible then return end
        local panel = item.panel
        if not panel or panel.segments ~= clamp(math.floor(settings.HealthSegments + 0.5), 1, 10)
            or panel.modeSegments ~= clamp(math.floor(settings.ModeSegments + 0.5), 1, 10) then
            if item.content then item.content:Destroy() end
            item.content = esp.New("Frame", item.gui, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 })
            item.panel = esp.BuildPanel(item.content)
            wasVisible = false
        end
        if wasVisible and settings.DistanceThrottle and not c.pinned and c.dist > settings.ESP_MaxDist * 0.55
            and now - item.lastRefresh < 0.45 and item.styleRevision == esp.StyleRevision then return end
        item.lastRefresh, item.styleRevision = now, esp.StyleRevision
        local mode, modeCap
        if settings.ModeBar then mode, modeCap = esp.ModeInfo(c.char) end
        esp.UpdatePanel(item.panel, {
            display = c.plr.DisplayName, user = c.plr.Name,
            health = (settings.HealthBar or settings.HealthText) and healthValue(c.hum) or nil, maxHealth = healthMax(c.hum, healthValue(c.hum)),
            downed = cfg.Downed and cfg.Downed(c.char) or false,
            mode = mode, modeCap = modeCap, distance = c.dist, dodge = esp.DodgeCooldown(c.plr),
        })
    end

    function esp.DestroyPanels()
        for plr in pairs(esp.Panels) do esp.DropPanel(plr) end
        if esp.Folder then pcall(function() esp.Folder:Destroy() end) esp.Folder = nil end
    end

    local period, nextRefresh = 1 / 25, 0
    local run = cfg.RunService or game:GetService("RunService")
    links[#links + 1] = run.Heartbeat:Connect(function()
        if not alive then return end
        local now = os.clock()
        if now < nextRefresh then return end
        if nextRefresh == 0 then nextRefresh = now end
        nextRefresh += (math.floor((now - nextRefresh) / period) + 1) * period
        local ok, err = pcall(esp.UpdatePanels)
        if not ok then report("ESP", err) end
    end)
    links[#links + 1] = Players.PlayerRemoving:Connect(function(player) esp.DropPanel(player) end)
    function esp:Destroy()
        if not alive then return end
        alive = false
        for _, connection in ipairs(links) do connection:Disconnect() end
        table.clear(links)
        esp.DestroyPanels()
        esp.Selection = nil
    end
    return esp
end

function Esp.PanelRenderer(settings, cfg)
    local clamp = math.clamp
    local healthColor, modeColorFor = cfg.HealthColor, cfg.ModeColor
    local esp = { Colors = cfg.Colors, DodgeImage = cfg.DodgeImage, Compact = cfg.Format }
    function esp.New(class, parent, props)
        local object = Util.create(class, props)
        object.Parent = parent
        return object
    end
    function esp.BuildPanel(parent)
        local segments = clamp(math.floor(settings.HealthSegments + 0.5), 1, 10)
        local modeSegments = clamp(math.floor(settings.ModeSegments + 0.5), 1, 10)
        local panel = { segments = segments, modeSegments = modeSegments, peak = 1 }
        local bar = esp.New("Frame", parent, { Name = "HealthBar", Size = UDim2.fromOffset(110, 8), Position = UDim2.new(0.5, -55, 0, 14),
            BackgroundColor3 = esp.Colors.back, BackgroundTransparency = 0.05, BorderSizePixel = 0, ClipsDescendants = true })
        bar:SetAttribute("Base", 0.05)
        esp.New("UICorner", bar, { CornerRadius = UDim.new(0, 3) })
        esp.New("UIStroke", bar, { Color = Color3.new(), Thickness = 1.25, Transparency = 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, LineJoinMode = Enum.LineJoinMode.Round })
        -- one fill with one gradient over the whole bar; the segments are only the dark divider lines on top
        panel.healthFill = esp.New("Frame", bar, { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0, ClipsDescendants = true })
        esp.New("UICorner", panel.healthFill, { CornerRadius = UDim.new(0, 2) })
        panel.healthGradient = esp.New("UIGradient", panel.healthFill, { Name = "Gradient" })
        esp.Stripes(panel.healthFill, 110)
        for index = 1, segments - 1 do
            esp.New("Frame", bar, { Size = UDim2.fromOffset(1, 8), Position = UDim2.new(index / segments, 0, 0, 0), BackgroundColor3 = esp.Colors.split, BorderSizePixel = 0, ZIndex = 3 })
        end
        panel.bar = bar
        panel.name = esp.New("TextLabel", parent, { Name = "PlayerName", Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 25), BackgroundTransparency = 1,
            RichText = true, TextColor3 = Color3.fromRGB(240, 240, 240), TextStrokeColor3 = Color3.new(), TextStrokeTransparency = 0.2,
            Font = Enum.Font.GothamBold, TextSize = 14, Text = "" })
        panel.health = esp.New("TextLabel", parent, { Name = "HealthText", Size = UDim2.fromOffset(127, 17), Position = UDim2.new(0.5, -127, 0, 47), BackgroundTransparency = 1,
            RichText = true, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = Color3.fromRGB(235, 235, 235), TextStrokeColor3 = Color3.new(),
            TextStrokeTransparency = 0.25, Font = Enum.Font.GothamBold, TextSize = 11, Text = "" })
        panel.distance = esp.New("TextLabel", parent, { Name = "Distance", Size = UDim2.fromOffset(127, 17), Position = UDim2.new(0.5, 3, 0, 47), BackgroundTransparency = 1,
            TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(190, 190, 190), TextStrokeColor3 = Color3.new(),
            TextStrokeTransparency = 0.25, Font = Enum.Font.GothamBold, TextSize = 11, Text = "[0 studs]" })
        local modeBar = esp.New("Frame", parent, { Name = "ModeBar", Size = UDim2.fromOffset(110, 8), Position = UDim2.new(0.5, -55, 0, 2),
            BackgroundColor3 = esp.Colors.back, BackgroundTransparency = 0.05, BorderSizePixel = 0, ClipsDescendants = true })
        esp.New("UICorner", modeBar, { CornerRadius = UDim.new(0, 3) })
        esp.New("UIStroke", modeBar, { Color = Color3.new(), Thickness = 1.25, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
        panel.modeFill = esp.New("Frame", modeBar, { Name = "Fill", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 })
        esp.New("UICorner", panel.modeFill, { CornerRadius = UDim.new(0, 2) })
        panel.modeGradient = esp.New("UIGradient", panel.modeFill, { Name = "Gradient" })
        panel.modeFill.ClipsDescendants = true
        esp.Stripes(panel.modeFill, 110)
        for index = 1, modeSegments - 1 do
            esp.New("Frame", modeBar, { Size = UDim2.new(0, 1, 1, 0), Position = UDim2.fromScale(index / modeSegments, 0), BackgroundColor3 = esp.Colors.split, BorderSizePixel = 0, ZIndex = 3 })
        end
        panel.modeBar = modeBar
        panel.modeLabel = esp.New("TextLabel", parent, { Name = "ModeAmount", Size = UDim2.fromOffset(100, 14), Position = UDim2.new(0.5, 61, 0, -1),
            TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4, BackgroundTransparency = 1, TextColor3 = Color3.fromRGB(190, 150, 230),
            TextStrokeColor3 = Color3.new(), TextStrokeTransparency = 0.25, Font = Enum.Font.GothamBold, TextSize = 10, Text = "", Visible = false })
        panel.dodgeIcon = esp.New("ImageLabel", parent, { Name = "Dodge", Size = UDim2.fromOffset(14, 14), Position = UDim2.fromOffset(270, 29),
            BackgroundTransparency = 1, Image = esp.DodgeImage, Visible = false })
        panel.dodgeLabel = esp.New("TextLabel", panel.dodgeIcon, { Size = UDim2.fromScale(1, 1), ZIndex = panel.dodgeIcon.ZIndex + 1, BackgroundTransparency = 1,
            TextColor3 = Color3.fromRGB(235, 235, 235), TextStrokeTransparency = 0, Font = Enum.Font.GothamBold, TextSize = 15, Text = "", Visible = false })
        return panel
    end
    function esp.Escape(text) return (tostring(text):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;")) end
    -- The bars show the preset as a real gradient over their whole width (like its swatch): a fill that ends at
    -- `to` shows the colours from `from` to `to` of the preset.
    -- Bar styles (the capsules on the ESP preview): Smooth eases the gradient (the end colours stay longer, the middle passes quicker);
    -- Stripes is the same with light diagonal stripes on top. Sampled 9 times so the eased curve comes out right.
    function esp.Gradient(colorAt, from, to)
        local points = {}
        for i = 0, 8 do
            local p = from + (to - from) * i / 8
            points[#points + 1] = ColorSequenceKeypoint.new(i / 8, colorAt(p * p * (3 - 2 * p)))
        end
        return ColorSequence.new(points)
    end
    -- the stripes: a white frame over a fill (as wide as the full slot, so the stripes keep their spacing while the
    -- fill shrinks; the fill clips it) whose transparency alternates every ~6 px, tilted by the gradient rotation
    -- bar opacity (the capsules on the ESP preview): the bar's back, outline, fill, dividers and stripes together; texts are not touched.
    -- A frame's own see-through amount at 100% is kept in its "Base" attribute (0 when unset: fill, dividers; the back
    -- 0.05, the stripes 0.7, their holder 1), so one value scales them all.
    function esp.Fade(frame, opacity)
        frame.BackgroundTransparency = 1 - opacity * (1 - (frame:GetAttribute("Base") or 0))
    end
    function esp.FadeImage(image, opacity)
        image.ImageTransparency = 1 - opacity * (1 - (image:GetAttribute("Base") or 0))
    end
    function esp.BarOpacity(bar, opacity)
        if bar:GetAttribute("Opacity") == opacity then return end
        bar:SetAttribute("Opacity", opacity)
        bar.BackgroundTransparency = 1 - opacity * 0.95
        for _, d in ipairs(bar:GetDescendants()) do
            if d:IsA("UIStroke") then d.Transparency = 1 - opacity
            elseif d:IsA("Frame") then esp.Fade(d, opacity)
            elseif d:IsA("ImageLabel") then esp.FadeImage(d, opacity) end
        end
    end
    -- Stripes: diagonal "/" lines every 6 px over the fill, each made of four 2 px steps (a rotated frame would not be
    -- clipped by the fill, and a rotated gradient barely tilts on an 8 px tall bar). The holder is as wide as the bar, so
    -- the stripes keep their place while the fill shrinks; it is filled the first time Stripes is chosen: with the tiled
    -- picture (Esp.StripeImage) when the executor can load it, otherwise with 2 px gradient frames.
    function esp.Stripes(fill, width)
        local holder = esp.New("Frame", fill, { Name = "Stripes", Size = UDim2.new(0, width, 1, 0), BackgroundTransparency = 1, ClipsDescendants = true,
            BorderSizePixel = 0, ZIndex = 2, Visible = false })
        holder:SetAttribute("Base", 1)
        holder:SetAttribute("Width", width)
        return holder
    end
    function esp.StripeSequence(step)
        esp.StripeSequences = esp.StripeSequences or {}
        if esp.StripeSequences[step] then return esp.StripeSequences[step] end
        local phase = 3 - step
        local function marked(x) return (x - phase) % 6 < 3 end
        local function point(x, on) return NumberSequenceKeypoint.new(x / 24, on and 0 or 1) end
        local points = { point(0, marked(0)) }
        for x = 1, 24 do
            if marked(x - 1) ~= marked(x) then
                points[#points + 1] = point(x - 0.02, marked(x - 1))
                points[#points + 1] = point(x, marked(x))
            end
        end
        if points[#points].Time < 1 then points[#points + 1] = point(24, marked(24)) end
        local sequence = NumberSequence.new(points)
        esp.StripeSequences[step] = sequence
        return sequence
    end
    function esp.ShowStripes(holder, on, opacity)
        local image = on and not holder:GetAttribute("Built") and Esp.StripeImage()
        if image then
            local tile = esp.New("ImageLabel", holder, { Name = "Tile", Image = image, ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(6, 8),
                ResampleMode = Enum.ResamplerMode.Pixelated, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2 })
            tile:SetAttribute("Base", 0.7)
            esp.FadeImage(tile, opacity)
            holder:SetAttribute("Built", true)
        elseif on and not holder:GetAttribute("Built") then
            for step = 0, 3 do
                local sequence = esp.StripeSequence(step)
                for x = 0, holder:GetAttribute("Width") - 1, 24 do
                    local line = esp.New("Frame", holder, { Position = UDim2.fromOffset(x, step * 2), Size = UDim2.fromOffset(24, 2),
                        BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 2 })
                    line:SetAttribute("Base", 0.7)
                    esp.New("UIGradient", line, { Transparency = sequence })
                    esp.Fade(line, opacity)
                end
            end
            holder:SetAttribute("Built", true)
        end
        esp.SetIf(holder, "Visible", on)
    end
    function esp.SetIf(object, property, value) if object[property] ~= value then object[property] = value end end
    -- Fills the panel. info = { display, user, health (nil: unavailable or hidden), maxHealth, downed, mode, modeCap, distance, dodge }
    function esp.UpdatePanel(panel, info)
        -- name: display name, [username] in grey
        esp.SetIf(panel.name, "Visible", settings.Name or settings.User)
        local nameText = settings.Name and esp.Escape(info.display) or ""
        if settings.User then nameText = nameText .. (settings.Name and " " or "") .. '<font color="#AFAFAF">[' .. esp.Escape(info.user) .. "]</font>" end
        esp.SetIf(panel.name, "Text", nameText)
        esp.SetIf(panel.name, "TextSize", settings.TextSize)
        esp.SetIf(panel.bar, "Visible", settings.HealthBar)
        esp.SetIf(panel.health, "Visible", settings.HealthText)
        if settings.HealthBar or settings.HealthText then
            local health = info.health and math.max(info.health, 0)
            local maximum = math.max(info.maxHealth or 1, 1)
            if settings.HealthBar then
                esp.ShowStripes(panel.healthFill.Stripes, settings.HealthBarStyle == "Stripes", settings.HealthBarOpacity)
                esp.BarOpacity(panel.bar, settings.HealthBarOpacity)
                local ratio = clamp((health or 0) / maximum, 0, 1)
                esp.SetIf(panel.healthFill, "Size", UDim2.fromScale(ratio, 1))
                local key = settings.HealthPreset .. "|" .. math.floor(ratio * 100 + 0.5)
                if ratio > 0 and panel.healthKey ~= key then
                    panel.healthKey = key
                    panel.healthGradient.Color = esp.Gradient(healthColor, 0, ratio)
                end
            end
            if settings.HealthText then
                local healthText = health and (esp.Compact(health) .. " / " .. esp.Compact(maximum)) or "--"
                esp.SetIf(panel.health, "Text", healthText .. (info.downed and " · Death" or ""))
            end
        end
        -- mode: the bar (relative to the highest value seen when the game gives no maximum) and "MD 50 / 100"
        local hasMode = settings.ModeBar and info.mode ~= nil
        esp.SetIf(panel.modeBar, "Visible", hasMode)
        esp.SetIf(panel.modeLabel, "Visible", hasMode and settings.ModeText)
        if hasMode then
            esp.ShowStripes(panel.modeFill.Stripes, settings.ModeBarStyle == "Stripes", settings.ModeBarOpacity)
            esp.BarOpacity(panel.modeBar, settings.ModeBarOpacity)
            local mode = info.mode
            panel.peak = math.max(panel.peak, mode)
            local ratio = clamp(mode / (info.modeCap or panel.peak), 0, 1)
            esp.SetIf(panel.modeFill, "Size", UDim2.fromScale(ratio, 1))
            -- the preset's gradient from empty up to the current amount (redone only when it changes)
            local key = settings.ModePreset .. "|" .. math.floor(ratio * 100 + 0.5)
            if panel.modeKey ~= key then
                panel.modeKey = key
                panel.modeGradient.Color = esp.Gradient(modeColorFor, 0, math.max(ratio, 0.001))
            end
            if settings.ModeText then
                esp.SetIf(panel.modeLabel, "TextColor3", modeColorFor(ratio))
                esp.SetIf(panel.modeLabel, "Text", "MD " .. esp.Compact(mode) .. (info.modeCap and (" / " .. esp.Compact(info.modeCap)) or " · relative"))
            end
        end
        -- dodge icon right after the name: the cooldown in red while it counts down
        local textWidth = tonumber(panel.name.TextBounds and panel.name.TextBounds.X) or 0
        local iconSize = settings.TextSize
        esp.SetIf(panel.dodgeIcon, "Size", UDim2.fromOffset(iconSize, iconSize))
        esp.SetIf(panel.dodgeIcon, "Position", UDim2.new(0.5, math.ceil(textWidth / 2) + 3, 0, 25 + (22 - iconSize) / 2))
        esp.SetIf(panel.dodgeLabel, "TextSize", math.max(8, math.floor(iconSize * 0.7 + 0.5)))
        local cooldown = info.dodge
        esp.SetIf(panel.dodgeIcon, "Visible", cooldown ~= nil and (settings.Name or settings.User))
        esp.SetIf(panel.dodgeLabel, "Visible", cooldown ~= nil and cooldown > 0)
        if cooldown then
            esp.SetIf(panel.dodgeLabel, "Text", cooldown > 0 and tostring(math.ceil(cooldown)) or "")
            esp.SetIf(panel.dodgeIcon, "ImageTransparency", cooldown > 0 and 0.25 or 0)
            esp.SetIf(panel.dodgeLabel, "TextColor3", cooldown > 0 and esp.Colors.red or esp.Colors.green)
        end
        -- health text and distance centred together under the name
        esp.SetIf(panel.distance, "Visible", settings.Distance)
        esp.SetIf(panel.distance, "Text", "[" .. esp.Compact(info.distance or 0) .. " studs]")
        local hpWidth = settings.HealthText and (tonumber(panel.health.TextBounds and panel.health.TextBounds.X) or 0) or 0
        local distanceWidth = settings.Distance and (tonumber(panel.distance.TextBounds and panel.distance.TextBounds.X) or 0) or 0
        local gap = (hpWidth > 0 and distanceWidth > 0) and 8 or 0
        local total = hpWidth + distanceWidth + gap
        esp.SetIf(panel.health, "Size", UDim2.fromOffset(math.max(hpWidth, 1), 17))
        esp.SetIf(panel.distance, "Size", UDim2.fromOffset(math.max(distanceWidth, 1), 17))
        esp.SetIf(panel.health, "Position", UDim2.new(0.5, -total / 2, 0, 47))
        esp.SetIf(panel.distance, "Position", UDim2.new(0.5, -total / 2 + hpWidth + gap, 0, 47))
    end

    return esp
end

function Esp.PreviewControls(self, cfg)
    local holder, settings, Window = cfg.Parent or self.body, cfg.Settings, self.window
    local cleanups, clamp = {}, math.clamp
    local controls = Instance.new("Frame")
    controls.Name, controls.BackgroundTransparency, controls.ZIndex = "Controls", 1, 8
    controls.AnchorPoint, controls.Position, controls.Size = Vector2.new(0.5, 1), UDim2.new(0.5, 0, 1, -7), UDim2.fromOffset(240, 48)
    controls.Parent = holder
    local list = Instance.new("UIListLayout")
    list.Padding, list.HorizontalAlignment, list.SortOrder = UDim.new(0, 4), Enum.HorizontalAlignment.Center, Enum.SortOrder.LayoutOrder
    list.Parent = controls
    local function make(class, parent, props)
        local object = Instance.new(class)
        for key, value in pairs(props) do object[key] = value end
        object.Parent = parent
        return object
    end
    local function round(object, radius) make("UICorner", object, { CornerRadius = UDim.new(0, radius) }) end
    local function tip(button, text)
        button.MouseEnter:Connect(function() if Window._tip then pcall(Window._tip, Window, text) end end)
        button.MouseLeave:Connect(function() if Window._hideTip then pcall(Window._hideTip, Window) end end)
    end
    local function capsule(order, label, presets, keys)
        local dimmable = {}                                  -- { object, property, normal } faded while the bar is off
        local frame = make("Frame", controls, { Name = label, LayoutOrder = order, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 22),
            BackgroundColor3 = Color3.fromRGB(11, 12, 16), BackgroundTransparency = 0.22, BorderSizePixel = 0, ZIndex = 8 })
        round(frame, 11)
        make("UIStroke", frame, { Color = Color3.new(1, 1, 1), Transparency = 0.92, Thickness = 1 })
        make("UIPadding", frame, { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 7) })
        make("UIListLayout", frame, { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder })
        local title = make("TextLabel", frame, { LayoutOrder = 1, Size = UDim2.fromOffset(16, 14), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 9,
            TextColor3 = Color3.fromRGB(154, 158, 168), Text = label, ZIndex = 9 })
        dimmable[#dimmable + 1] = { title, "TextTransparency", 0 }
        local function usable() return settings[keys.barSetting] ~= false end
        -- colours
        local rings = {}
        local dots = make("Frame", frame, { LayoutOrder = 2, AutomaticSize = Enum.AutomaticSize.X, Size = UDim2.fromOffset(0, 16), BackgroundTransparency = 1 })
        make("UIListLayout", dots, { FillDirection = Enum.FillDirection.Horizontal, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 2) })
        for index, preset in ipairs(presets) do
            local name = preset[1]
            local button = make("TextButton", dots, { Name = name, LayoutOrder = index, Size = UDim2.fromOffset(15, 15), BackgroundTransparency = 1, Text = "",
                AutoButtonColor = false, ZIndex = 9 })
            local ring = make("Frame", button, { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 9 })
            round(ring, 8)
            rings[name] = make("UIStroke", ring, { Color = Color3.fromRGB(238, 240, 244), Thickness = 1.5, Transparency = 1 })
            local dot = make("Frame", button, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(9, 9),
                BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 10 })
            round(dot, 5)
            dimmable[#dimmable + 1] = { dot, "BackgroundTransparency", 0 }
            button.MouseEnter:Connect(function() if usable() then dot.Size = UDim2.fromOffset(11, 11) end end)
            button.MouseLeave:Connect(function() dot.Size = UDim2.fromOffset(9, 9) end)
            tip(button, name)
            local points = {}
            for i = 2, #preset do points[#points + 1] = ColorSequenceKeypoint.new((i - 2) / (#preset - 2), preset[i]) end
            make("UIGradient", dot, { Color = ColorSequence.new(points), Rotation = 35 })
            button.Activated:Connect(function() if usable() then Window:SetFlag(keys.colors, name) end end)
        end
        -- Smooth / Stripes: a plain bar and a striped bar
        local switch = make("Frame", frame, { LayoutOrder = 3, Size = UDim2.fromOffset(43, 17), BackgroundColor3 = Color3.fromRGB(11, 12, 16), BorderSizePixel = 0, ZIndex = 9 })
        round(switch, 8)
        local options = {}
        for index, style in ipairs({ "Smooth", "Stripes" }) do
            local button = make("TextButton", switch, { Name = style, Position = UDim2.fromOffset(1 + (index - 1) * 21, 1), Size = UDim2.fromOffset(20, 15),
                BackgroundColor3 = Color3.fromRGB(42, 44, 52), BackgroundTransparency = 1, BorderSizePixel = 0, Text = "", AutoButtonColor = false, ZIndex = 9 })
            round(button, 7)
            local icon = make("Frame", button, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(11, 5),
                BackgroundColor3 = Color3.fromRGB(207, 211, 220), BorderSizePixel = 0, ClipsDescendants = true, ZIndex = 10 })
            round(icon, 2)
            if style == "Stripes" then
                icon.BackgroundColor3 = Color3.fromRGB(92, 97, 108)
                for i = 0, 3 do
                    make("Frame", icon, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(i * 4, 2.5), Size = UDim2.fromOffset(2, 10), Rotation = 35,
                        BackgroundColor3 = Color3.fromRGB(207, 211, 220), BorderSizePixel = 0, ZIndex = 11 })
                end
            end
            options[style] = { button = button, icon = icon }
            tip(button, style)
            button.Activated:Connect(function() if usable() then Window:SetFlag(keys.style, style) end end)
        end
        -- opacity: scroll to change by 5 %, click for the next of 100 / 75 / 50 / 25 %
        local opacity = make("TextButton", frame, { LayoutOrder = 4, Size = UDim2.fromOffset(28, 14), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
            TextSize = 9, TextColor3 = Color3.fromRGB(154, 158, 168), Text = "100%", AutoButtonColor = false, ZIndex = 9 })
        dimmable[#dimmable + 1] = { opacity, "TextTransparency", 0 }
        tip(opacity, "Opacity · scroll or click")
        local function setOpacity(value)
            if usable() then Window:SetFlag(keys.opacity, clamp(math.floor(value + 0.5), 10, 100)) end
        end
        -- while the mouse is on the number the wheel changes it, not the page
        local capture = Util.captureScroll(opacity, usable)
        local function releaseScroll() capture.Sync() end
        cleanups[#cleanups + 1] = capture.Destroy
        opacity.Activated:Connect(function()
            local now = math.floor((settings[keys.opacitySetting] or 1) * 100 + 0.5)
            local steps = { 100, 75, 50, 25 }
            local nextValue = steps[1]
            for i, step in ipairs(steps) do if now >= step - 2 then nextValue = steps[i + 1] or steps[1] break end end
            setOpacity(nextValue)
        end)
        opacity.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseWheel then
                setOpacity((settings[keys.opacitySetting] or 1) * 100 + (input.Position.Z > 0 and 5 or -5))
            end
        end)
        return function()
            local preset, style = settings[keys.presetSetting], settings[keys.styleSetting]
            for name, ring in pairs(rings) do ring.Transparency = name == preset and 0 or 1 end
            for name, option in pairs(options) do
                local on = name == style
                option.button.BackgroundTransparency = on and 0 or 1
                option.icon.BackgroundTransparency = on and 0 or 0.55
                for _, stripe in ipairs(option.icon:GetChildren()) do
                    if stripe:IsA("Frame") then stripe.BackgroundTransparency = on and 0 or 0.55 end
                end
            end
            opacity.Text = math.floor((settings[keys.opacitySetting] or 1) * 100 + 0.5) .. "%"
            local off = not usable()
            if off then releaseScroll() end
            for _, item in ipairs(dimmable) do item[1][item[2]] = off and 0.65 or item[3] end
            frame.BackgroundTransparency = off and 0.5 or 0.22
        end
    end

    local refreshers = {}
    for index, row in ipairs(cfg.Rows) do refreshers[index] = capsule(index, row.Label, row.Presets, row.Keys) end
    controls.Size = UDim2.fromOffset(240, #cfg.Rows * 26 - 4)
    local alive = true
    local control = { Frame = controls }
    local lastKey
    function control:Update()
        if not alive then return end
        local values = {}
        for _, row in ipairs(cfg.Rows) do
            for _, field in ipairs({ "presetSetting", "styleSetting", "opacitySetting", "barSetting" }) do
                values[#values + 1] = tostring(settings[row.Keys[field]])
            end
        end
        local key = table.concat(values, "|")
        if lastKey == key then return end
        lastKey = key
        for _, refresh in ipairs(refreshers) do refresh() end
    end
    function control:Destroy()
        if not alive then return end
        alive = false
        for _, cleanup in ipairs(cleanups) do cleanup() end
        controls:Destroy()
    end
    controls.Destroying:Connect(function()
        if not alive then return end
        alive = false
        for _, cleanup in ipairs(cleanups) do cleanup() end
    end)
    self.window.maid:give(function() control:Destroy() end)
    control:Update()
    return control
end
function Esp.Preview(self, cfg)
    local canvas = self:Canvas({ Height = cfg.Height or 170 })
    local settings, renderer, clamp = cfg.Settings, cfg.Renderer, math.clamp
    local holder = canvas.Frame
    if holder then
        holder.ClipsDescendants = true
        -- background: a dark gradient with a few large, very soft colour blobs (a blurred look)
        local back = Instance.new("Frame")
        back.Name, back.Size, back.BorderSizePixel, back.BackgroundColor3 = "Backdrop", UDim2.fromScale(1, 1), 0, Color3.new(1, 1, 1)
        local tint = Instance.new("UIGradient")
        tint.Color = ColorSequence.new(Color3.fromRGB(28, 30, 52), Color3.fromRGB(18, 38, 44))
        tint.Rotation = 20
        tint.Parent = back
        back.Parent = holder
        for _, blob in ipairs({
            { 0.18, 0.30, 170, Color3.fromRGB(96, 70, 190) }, { 0.80, 0.25, 150, Color3.fromRGB(40, 140, 170) },
            { 0.55, 0.95, 190, Color3.fromRGB(190, 70, 120) }, { 0.05, 1.00, 120, Color3.fromRGB(40, 120, 90) },
        }) do
            local glow = Instance.new("Frame")
            glow.AnchorPoint, glow.Position = Vector2.new(0.5, 0.5), UDim2.fromScale(blob[1], blob[2])
            glow.Size, glow.BorderSizePixel, glow.BackgroundColor3 = UDim2.fromOffset(blob[3], blob[3]), 0, blob[4]
            local round = Instance.new("UICorner")
            round.CornerRadius = UDim.new(1, 0)
            round.Parent = glow
            local fade = Instance.new("UIGradient")                     -- bright centre fading out to nothing: the blur
            fade.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.5, 0.8), NumberSequenceKeypoint.new(1, 1) })
            fade.Parent = glow
            glow.Parent = back
        end
    end

    local mini
    if cfg.Controls then mini = Esp.PreviewControls(self, { Parent = holder, Settings = settings, Rows = cfg.Controls }) end
    local box, panel
    local function draw()
        if canvas.Destroyed then return end
        if panel and (panel.segments ~= clamp(math.floor(settings.HealthSegments + 0.5), 1, 10)
            or panel.modeSegments ~= clamp(math.floor(settings.ModeSegments + 0.5), 1, 10)) then
            box:Destroy() box, panel = nil, nil
        end
        if not box then
            box = Util.create("Frame", { Name = "Panel", BackgroundTransparency = 1, Size = UDim2.fromOffset(300,78), ZIndex = 5,
                AnchorPoint = Vector2.new(0.5,0), Position = UDim2.new(0.5,0,0,12), Parent = holder })
            panel = renderer.BuildPanel(box)
        end
        renderer.UpdatePanel(panel, cfg.Read())
        if mini then mini:Update() end
    end
    local elapsed = 0
    local stop = Util.animateInView(holder, Util.Services.RunService.Heartbeat, function(dt)
        elapsed += dt
        if elapsed >= 1 / 15 then elapsed = elapsed % (1 / 15) self.window:_safe("Stat preview", draw) end
    end)
    local show = Util.watchInView(holder, function(on)
        if on then elapsed = 0 self.window:_safe("Stat preview", draw) end
    end)
    canvas.Maid:give(stop)
    canvas.Maid:give(show)
    if mini then canvas.Maid:give(function() mini:Destroy() end) end
    function canvas:Update() if Util.inView(holder) then self._draw() end end
    canvas._draw = draw
    return canvas
end

return Esp
end
