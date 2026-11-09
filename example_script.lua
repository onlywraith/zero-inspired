-- example_esp.lua - a configurable ESP built with ZeroUI (main.lua) for Matcha.
--
--   * player ESP: box, name, distance, tracer
--   * "extra targets": type part of any model/part name and it gets an ESP too
--   * every option lives in the menu and is saved to esp_example.json
--
-- Run it, then press RSHIFT (the menu key) to open / close the menu.

----------------------------------------------------------------------
-- 1. load the UI library from GitHub (it publishes itself as _G.main)
----------------------------------------------------------------------
local LIB_URL = "https://raw.githubusercontent.com/onlywraith/zero-inspired/refs/heads/main/main.lua"

local function usable(t) return type(t) == "table" and not t._dead and type(t.CreateWindow) == "function" end

local Library = rawget(_G, "main")
if not usable(Library) then
    _G.main = nil   -- drop a stale / half-loaded copy
    local src, err
    for _ = 1, 3 do
        local ok, res = pcall(function() return game:HttpGet(LIB_URL) end)
        if ok and type(res) == "string" and #res > 1000 then src = res break end
        err = ok and "empty response" or res
    end
    if not src then warn("could not download the UI library: " .. tostring(err)) return end
    local ok, lerr = pcall(function() local f = loadstring(src); f() end)   -- Matcha drops loadstring's return
    if not ok then warn("UI library failed to load: " .. tostring(lerr)) end
    Library = rawget(_G, "main")
    if not usable(Library) then warn("UI library not available") return end
end

----------------------------------------------------------------------
-- 2. services + clean-up of a previous run
----------------------------------------------------------------------
local Players    = game:GetService("Players") or game.Players
local RunService = game:GetService("RunService") or game.RunService
local lp         = Players.LocalPlayer

if _G.EspExample then
    pcall(function() _G.EspExample.stop() end)
end
local ESP = { conn = nil, pool = {}, extra = {}, nextScan = 0 }
_G.EspExample = ESP

----------------------------------------------------------------------
-- 3. the menu - every control returns a handle; :Get() reads its value
----------------------------------------------------------------------
local win = Library:CreateWindow({
    id = "esp_example", title = "esp example", subtitle = "zero ui",
    size = { 700, 560 }, columns = 2, toggleKey = "RSHIFT",
    config = "esp_example.json",        -- every setting is saved after each change
    folder = "UI/esp_example",          -- named configs (settings tab)
})

local tab  = win:AddTab("esp", "visuals")
local main = tab:AddGroup("general", 1)
local look = tab:AddGroup("look", 2)
local extraG = tab:AddGroup("extra targets", 1)

local C = {}   -- all handles, read every frame

C.enabled = main:AddToggle({ text = "enable esp", flag = "esp_on", default = true })
C.enabled:AddKeybind({ flag = "esp_key", default = "F4", mode = "toggle", notify = true })   -- optional hotkey
C.players  = main:AddToggle({ text = "players", flag = "esp_players", default = true })
C.box      = main:AddToggle({ text = "boxes", flag = "esp_box", default = true })
C.names    = main:AddToggle({ text = "names", flag = "esp_names", default = true })
C.dist     = main:AddToggle({ text = "distance", flag = "esp_dist", default = true })
C.tracers  = main:AddToggle({ text = "tracers", flag = "esp_tracers", default = false })
C.maxdist  = main:AddSlider({ text = "max distance", flag = "esp_max", min = 100, max = 5000, step = 50,
    default = 1500, suffix = " studs" })

C.playerCol = look:AddColor({ text = "player color", flag = "esp_pcol", default = { 255, 255, 255 } })
C.objCol    = look:AddColor({ text = "object color", flag = "esp_ocol", default = { 255, 170, 60 } })
C.textSize  = look:AddSlider({ text = "text size", flag = "esp_tsize", min = 10, max = 24, step = 1, default = 14 })
C.thick     = look:AddSlider({ text = "line thickness", flag = "esp_thick", min = 1, max = 4, step = 1, default = 1 })
C.tracerFrom = look:AddDropdown({ text = "tracer starts at", flag = "esp_from",
    values = { "bottom", "center", "top" }, default = "bottom" })

C.extraOn = extraG:AddToggle({ text = "track extra targets", flag = "esp_extra_on", default = false })
C.filter  = extraG:AddTextbox({ text = "name contains", flag = "esp_filter", placeholder = "e.g. chest",
    default = "", maxLength = 40 })
C.extraMax = extraG:AddSlider({ text = "max targets", flag = "esp_extra_max", min = 1, max = 40, step = 1, default = 10 })
extraG:AddLabel({ text = "finds models / parts under workspace whose name contains the text above.", dim = true })

win:AddSettingsTab()   -- themes, configs, menu key, watermark ...

----------------------------------------------------------------------
-- 4. helpers
----------------------------------------------------------------------
local function colorOf(handle)   -- color handles hold a Color3
    return handle:Get()
end

local function isPart(object)
    local ok, cls = pcall(function() return object.ClassName end)
    return ok and (cls == "Part" or cls == "MeshPart" or cls == "UnionOperation")
end

local function partOf(object)
    if isPart(object) then return object end
    local ok, primary = pcall(function() return object.PrimaryPart end)
    if ok and primary and isPart(primary) then return primary end
    local okc, kids = pcall(function() return object:GetChildren() end)
    if okc then for _, k in ipairs(kids) do if isPart(k) then return k end end end
    return nil
end

-- In Matcha a player's .Character can be nil even when the avatar is in the world,
-- so fall back to the model named after the player in workspace.
local function rootPosition(player)
    local ok, pos = pcall(function()
        local char = player.Character or workspace:FindFirstChild(player.Name)
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        return hrp and hrp.Position
    end)
    return ok and pos or nil
end

local function myPosition() return rootPosition(lp) end

-- instance objects are not always equal to each other in Matcha, so compare by name
local function isMe(player)
    local ok, same = pcall(function() return player.Name == lp.Name end)
    return ok and same
end

local function project(pos)
    local ok, screen, onScreen = pcall(WorldToScreen, pos)
    if ok and screen and onScreen then return screen end
    return nil
end

-- scan workspace for the "extra targets" (bounded, runs about once a second)
local function scanExtra()
    local needle = string.lower(C.filter:Get() or "")
    local found = {}
    if needle ~= "" then
        local limit = C.extraMax:Get()
        local queue, i, visited = { workspace }, 1, 0
        while i <= #queue and visited < 1500 and #found < limit do
            local node = queue[i]; i = i + 1; visited = visited + 1
            local ok, kids = pcall(function() return node:GetChildren() end)
            if ok then
                for _, child in ipairs(kids) do
                    local okn, name = pcall(function() return child.Name end)
                    if okn and type(name) == "string" and string.find(string.lower(name), needle, 1, true) then
                        local okc, cls = pcall(function() return child.ClassName end)
                        if okc and (cls == "Model" or isPart(child)) then
                            local part = partOf(child)
                            if part then found[#found + 1] = { name = name, part = part } end
                        end
                    end
                    if #found >= limit then break end
                    if #queue < 4000 then queue[#queue + 1] = child end
                end
            end
        end
    end
    ESP.extra = found
end

-- Drawing property names differ between Matcha builds (a Text's size is `Size` on some,
-- `FontSize` on others), and writing an unsupported one can throw. Set everything through pcall.
local function set(object, key, value)
    return pcall(function() object[key] = value end)
end
local function setTextSize(text, size)
    if ESP.sizeKey then return set(text, ESP.sizeKey, size) end
    if set(text, "Size", size) then ESP.sizeKey = "Size" return true end
    if set(text, "FontSize", size) then ESP.sizeKey = "FontSize" return true end
    return false
end

-- drawing objects are built once per slot and re-used every frame
local function slot(i)
    local s = ESP.pool[i]
    if s then return s end
    local box = Drawing.new("Square"); set(box, "Filled", false); box.Visible = false
    local label = Drawing.new("Text"); set(label, "Center", true); set(label, "Outline", true); label.Visible = false
    local line = Drawing.new("Line"); line.Visible = false
    s = { box = box, label = label, line = line }
    ESP.pool[i] = s
    return s
end

local function hideFrom(n)
    for i = n, #ESP.pool do
        local s = ESP.pool[i]
        s.box.Visible, s.label.Visible, s.line.Visible = false, false, false
    end
end

----------------------------------------------------------------------
-- 5. the per-frame draw
----------------------------------------------------------------------
local function drawTarget(target, color, mine, slotIndex, viewport)
    local pos = target.pos
    local dist = mine and math.floor((pos - mine).Magnitude) or nil
    if dist and dist > C.maxdist:Get() then return false end

    local head = project(pos + Vector3.new(0, 3, 0))
    local feet = project(pos - Vector3.new(0, 3.5, 0))
    if not head or not feet then return false end

    local s = slot(slotIndex)
    local height = math.max(feet.Y - head.Y, 6)
    local width = height * 0.55
    local cx = (head.X + feet.X) / 2
    local thick = C.thick:Get()

    set(s.box, "Color", color); set(s.box, "Thickness", thick)
    set(s.box, "Position", Vector2.new(cx - width / 2, head.Y))
    set(s.box, "Size", Vector2.new(width, height))
    s.box.Visible = C.box:Get()

    local text = ""
    if C.names:Get() then text = target.name end
    if C.dist:Get() and dist then text = text .. (text ~= "" and " " or "") .. "[" .. dist .. "m]" end
    set(s.label, "Text", text); set(s.label, "Color", color)
    setTextSize(s.label, C.textSize:Get())
    set(s.label, "Position", Vector2.new(cx, head.Y - C.textSize:Get() - 3))
    s.label.Visible = text ~= ""

    if C.tracers:Get() then
        local from = C.tracerFrom:Get()
        local y = (from == "top" and 0) or (from == "center" and viewport.Y / 2) or viewport.Y
        set(s.line, "Color", color); set(s.line, "Thickness", thick)
        set(s.line, "From", Vector2.new(viewport.X / 2, y))
        set(s.line, "To", Vector2.new(cx, feet.Y))
        s.line.Visible = true
    else
        s.line.Visible = false
    end
    return true
end

local function draw(target, color, mine, slotIndex, viewport)
    local ok, result = pcall(drawTarget, target, color, mine, slotIndex, viewport)
    if not ok then
        if not ESP.warned then ESP.warned = true; warn("esp error: " .. tostring(result)) end
        return false
    end
    return result
end

local function step()
    if not C.enabled:Get() then hideFrom(1) return end

    local mine = myPosition()
    local viewport = Vector2.new(1920, 1080)
    pcall(function() local vw, vh = Library:_viewport(); viewport = Vector2.new(vw, vh) end)

    local used = 0

    if C.players:Get() then
        local color = colorOf(C.playerCol)
        local ok, list = pcall(function() return Players:GetPlayers() end)
        if ok then
            for _, p in ipairs(list) do
                if not isMe(p) then
                    local pos = rootPosition(p)
                    if pos then
                        if draw({ name = p.Name, pos = pos }, color, mine, used + 1, viewport) then used = used + 1 end
                    end
                end
            end
        end
    end

    if C.extraOn:Get() then
        local now = os.clock()
        if now >= ESP.nextScan then ESP.nextScan = now + 1; scanExtra() end
        local color = colorOf(C.objCol)
        for _, t in ipairs(ESP.extra) do
            local okp, pos = pcall(function() return t.part.Position end)
            if okp and pos then
                if draw({ name = t.name, pos = pos }, color, mine, used + 1, viewport) then used = used + 1 end
            end
        end
    end

    hideFrom(used + 1)
end

----------------------------------------------------------------------
-- 6. start / stop
----------------------------------------------------------------------
function ESP.stop()
    if ESP.conn then pcall(function() ESP.conn:Disconnect() end); ESP.conn = nil end
    for _, s in ipairs(ESP.pool) do
        pcall(function() s.box:Remove() end)
        pcall(function() s.label:Remove() end)
        pcall(function() s.line:Remove() end)
    end
    ESP.pool = {}
end

ESP.conn = RunService.Heartbeat:Connect(function()
    local ok, err = pcall(step)
    if not ok and not ESP.warned then ESP.warned = true; warn("esp error: " .. tostring(err)) end
end)

Library:OnUnload(ESP.stop)   -- unloading the menu also removes every drawing
Library:Notify({ title = "esp example", text = "loaded - press RSHIFT for the menu", duration = 4 })
