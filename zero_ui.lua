-- ZeroUI 1.0.10 - the Zero Hub look as a reusable Drawing UI library for Matcha.
-- Sidebar sections + tabs, collapsible cards, hub-wide search, themes, configs and a
-- settings tab. No dependencies; publishes itself as _G.ZeroUI (Matcha drops the
-- return value of loadstring chunks).
--
-- 1.0.2: named custom themes (save / apply / delete) in the settings tab.
-- 1.0.10: removed setrobloxinput game-input blocking entirely (suspected menu freeze). TAB_ICONS flag near buildTabIcon.
-- 1.0.9: drawing objects are only repositioned when they actually moved (cuts per-frame property writes; menu stayed laggy while the macro ran).
-- 1.0.8: only blocks game input while typing / binding / a list is open (no pointer-over-menu blocking, no repeated re-sends).
-- 1.0.7: input blocking honours window captureInput / inputGuard (fixes the menu fighting a running macro).
-- 1.0.6: cursor removed; rounded corners removed again (not supported by Matcha drawings).
-- 1.0.5: tab icons (AddTab(name, section, icon)).
-- 1.0.4: rounded boxes / cards / sliders, [!] badge sits closer to its label.
-- 1.0.3: typing in dropdown search / textboxes / slider values / key listening no longer reaches the game.
--
--   local Library = _G.ZeroUI
--   local win  = Library:CreateWindow({ title = "zero hub", subtitle = "v1", size = {822, 640} })
--   local tab  = win:AddTab("auto shoot", "Offense")      -- tab name, sidebar section
--   local card = tab:AddGroup("auto shoot", 1)            -- card title, column
--   card:AddToggle({ text = "auto shoot", flag = "auto", default = false })
--   win:AddSettingsTab()
--
-- Full reference: see hub_template.lua

local VERSION = "1.0.10"

do -- reuse a live copy of the same version, replace an older one
    local old = rawget(_G, "ZeroUI")
    if type(old) == "table" and not old._dead then
        if old.Version == VERSION and not rawget(_G, "ZEROUI_RELOAD") then return old end
        pcall(function() old:Unload() end)
    end
end

local floor, max, min = math.floor, math.max, math.min
local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function now() return tick() end

local Library = {
    Version = VERSION, Windows = {}, Flags = {},
    CustomThemes = {},
    Settings = { cursorOffset = { 0, 0 } },
    Opacity = 1, TextOutline = false, TextSize = 13, SizeDelta = 0, FontName = "UI",
    PresetName = "zero pink",
    _sv = 1, _objs = {}, _conns = {}, _toasts = {}, _unloadFns = {}, _wheel = 0, _dead = false,
}
_G.ZeroUI = Library

----------------------------------------------------------------------
-- services
----------------------------------------------------------------------
local function svc(name)
    for _ = 1, 40 do
        local ok, s = pcall(function() return game:GetService(name) or game[name] end)
        if ok and s then return s end
        wait(0.1)
    end
end
local RunService  = svc("RunService")
local Players     = svc("Players")
local HttpService = svc("HttpService")
local lp = Players and Players.LocalPlayer

----------------------------------------------------------------------
-- colours
----------------------------------------------------------------------
local function C3(c) return Color3.fromRGB(floor(c[1] + .5), floor(c[2] + .5), floor(c[3] + .5)) end
local function mix(a, b, t) return { a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t } end
local function hex2rgb(h)
    h = string.gsub(tostring(h or ""), "#", "")
    if #h == 6 then
        local r, g, b = tonumber(string.sub(h, 1, 2), 16), tonumber(string.sub(h, 3, 4), 16), tonumber(string.sub(h, 5, 6), 16)
        if r and g and b then return { r, g, b } end
    end
end
local function rgb2hex(c) return string.format("#%02X%02X%02X", floor(c[1] + .5), floor(c[2] + .5), floor(c[3] + .5)) end
local function hsv2rgb(h, s, v)
    h = (h % 1) * 6
    local i = floor(h)
    local f = h - i
    local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
    local r, g, b
    if i == 0 then r, g, b = v, t, p elseif i == 1 then r, g, b = q, v, p elseif i == 2 then r, g, b = p, v, t
    elseif i == 3 then r, g, b = p, q, v elseif i == 4 then r, g, b = t, p, v else r, g, b = v, p, q end
    return { r * 255, g * 255, b * 255 }
end
local function rgb2hsv(c)
    local r, g, b = c[1] / 255, c[2] / 255, c[3] / 255
    local mx, mn = max(r, g, b), min(r, g, b)
    local d = mx - mn
    local h = 0
    if d > 0 then
        if mx == r then h = ((g - b) / d) % 6 elseif mx == g then h = (b - r) / d + 2 else h = (r - g) / d + 4 end
        h = h / 6
    end
    return h, (mx == 0) and 0 or d / mx, mx
end
local function toRGB(v)
    if type(v) == "string" then return hex2rgb(v) end
    if type(v) == "table" and v[1] and v[2] and v[3] then return { v[1], v[2], v[3] } end
    if type(v) == "table" and v.r and v.g and v.b then return { v.r, v.g, v.b } end
    local ok, r, g, b = pcall(function() return v.R, v.G, v.B end)
    if ok and type(r) == "number" then return { r * 255, g * 255, b * 255 } end
end

local PRESET_ORDER = { "zero pink", "monochrome", "graphite", "deep sea", "rose noir", "terminal",
                       "ultraviolet", "obsidian", "nordic", "sakura", "amber" }
local function P(a, bg, grp, top, bor, txt) return { accent = a, background = bg, group = grp, topbar = top, border = bor, text = txt } end
local PRESETS = {
    ["zero pink"]   = P({ 255, 92, 138 }, { 17, 13, 18 }, { 27, 22, 28 }, { 21, 17, 22 }, { 52, 45, 54 }, { 236, 232, 237 }),
    monochrome      = P({ 220, 220, 220 }, { 14, 14, 14 }, { 22, 22, 22 }, { 18, 18, 18 }, { 48, 48, 48 }, { 232, 232, 232 }),
    graphite        = P({ 130, 170, 255 }, { 20, 21, 24 }, { 29, 31, 35 }, { 24, 25, 29 }, { 54, 57, 63 }, { 226, 229, 235 }),
    ["deep sea"]    = P({ 60, 200, 220 }, { 9, 16, 24 }, { 15, 26, 38 }, { 11, 20, 31 }, { 30, 52, 72 }, { 218, 236, 244 }),
    ["rose noir"]   = P({ 232, 96, 124 }, { 14, 10, 12 }, { 24, 17, 20 }, { 18, 13, 15 }, { 56, 38, 44 }, { 240, 226, 230 }),
    terminal        = P({ 90, 255, 120 }, { 6, 10, 7 }, { 12, 18, 13 }, { 8, 13, 9 }, { 28, 52, 32 }, { 190, 245, 200 }),
    ultraviolet     = P({ 170, 110, 255 }, { 15, 11, 24 }, { 24, 18, 38 }, { 19, 14, 31 }, { 52, 40, 82 }, { 230, 222, 248 }),
    obsidian        = P({ 255, 255, 255 }, { 8, 8, 10 }, { 16, 16, 19 }, { 11, 11, 14 }, { 38, 38, 44 }, { 238, 238, 242 }),
    nordic          = P({ 136, 192, 208 }, { 36, 41, 51 }, { 46, 52, 64 }, { 41, 46, 57 }, { 67, 76, 94 }, { 229, 233, 240 }),
    sakura          = P({ 255, 150, 190 }, { 30, 22, 27 }, { 41, 31, 37 }, { 35, 26, 31 }, { 74, 56, 66 }, { 250, 232, 240 }),
    amber           = P({ 255, 176, 40 }, { 16, 12, 6 }, { 26, 20, 10 }, { 20, 15, 8 }, { 62, 48, 24 }, { 248, 236, 210 }),
}
local ROLE_LIST = { "accent", "background", "group", "topbar", "border", "text" }

Library.Roles = {}
for k, v in pairs(PRESETS["zero pink"]) do Library.Roles[k] = { v[1], v[2], v[3] } end

function Library:_derive()
    local r = self.Roles
    local R = { win = r.background, side = r.topbar, card = r.group, line = r.border, text = r.text, accent = r.accent }
    R.box    = mix(r.group, r.text, .09)
    R.hover  = mix(r.topbar, r.text, .06)
    R.active = mix(r.topbar, r.text, .11)
    R.sub    = mix(r.text, r.background, .22)
    R.mute   = mix(r.text, r.background, .52)
    self.R, self.C = R, {}
    for k, v in pairs(R) do self.C[k] = C3(v) end
    self._sv = self._sv + 1
    for _, w in ipairs(self.Windows) do w._dirty = true end
end
Library:_derive()

local FADE = { win = true, side = true, card = true, box = true, line = true, hover = true, active = true }
local DIM  = { text = "mute", sub = "mute", accent = "mute" }

----------------------------------------------------------------------
-- small helpers
----------------------------------------------------------------------
local function wrapText(s, n)
    local lines, cur = {}, ""
    for word in string.gmatch(s or "", "%S+") do
        if #cur > 0 and #cur + #word + 1 > n then lines[#lines + 1] = cur; cur = word
        else cur = (#cur > 0) and (cur .. " " .. word) or word end
    end
    if #cur > 0 then lines[#lines + 1] = cur end
    return lines
end
local function termsOf(q)
    local t = {}
    for w in string.gmatch(string.lower(q or ""), "%S+") do t[#t + 1] = w end
    return t
end
local function hasAll(s, terms)
    for _, t in ipairs(terms) do if not string.find(s, t, 1, true) then return false end end
    return true
end
local function inRect(mx, my, x, y, w, h) return mx >= x and mx <= x + w and my >= y and my <= y + h end
local function tw(s, size) return #tostring(s) * (size + Library.SizeDelta) * 0.54 end
local function copy(t) local c = {}; for k, v in pairs(t or {}) do c[k] = v end return c end
local function warnOnce(tag, msg)
    Library._warned = Library._warned or {}
    if not Library._warned[tag] then Library._warned[tag] = true; warn("[ZeroUI] " .. msg) end
end
local function setp(o, k, v)
    local ok, err = pcall(function() o[k] = v end)
    if not ok then warnOnce(k, "property '" .. tostring(k) .. "' not supported: " .. tostring(err)) end
    return ok
end
local function setTextSize(o, s)
    local m = Library._sizeMode
    if m == 1 then return pcall(function() o.FontSize = s end)
    elseif m == 2 then return pcall(function() o.Size = s end)
    elseif m == 3 then return pcall(function() o.Size = Vector2.new(s, s) end) end
    if pcall(function() o.FontSize = s end) then Library._sizeMode = 1
    elseif pcall(function() o.Size = s end) then Library._sizeMode = 2
    elseif pcall(function() o.Size = Vector2.new(s, s) end) then Library._sizeMode = 3 end
end
local function fmtNum(v, step)
    local dec = 0
    if step and step < 1 then dec = #(string.match(tostring(step), "%.(%d+)") or "") end
    if dec == 0 then return tostring(floor(v + .5)) end
    return string.format("%." .. dec .. "f", v)
end

----------------------------------------------------------------------
-- keys
----------------------------------------------------------------------
local KEYMAP = {}   -- name -> virtual key
for c = 0x41, 0x5A do KEYMAP[string.char(c)] = c end
for c = 0x30, 0x39 do KEYMAP[string.char(c)] = c end
for i = 1, 24 do KEYMAP["F" .. i] = 0x70 + i - 1 end
for i = 0, 9 do KEYMAP["NUM" .. i] = 0x60 + i end
for k, v in pairs({ LSHIFT = 0xA0, RSHIFT = 0xA1, LCTRL = 0xA2, RCTRL = 0xA3, LALT = 0xA4, RALT = 0xA5,
    SPACE = 0x20, TAB = 0x09, INS = 0x2D, DEL = 0x2E, HOME = 0x24, END = 0x23, PGUP = 0x21, PGDN = 0x22,
    LEFT = 0x25, UP = 0x26, RIGHT = 0x27, DOWN = 0x28, CAPS = 0x14, MB3 = 0x04, MB4 = 0x05, MB5 = 0x06 }) do KEYMAP[k] = v end
local KEYORDER = {}
for k in pairs(KEYMAP) do KEYORDER[#KEYORDER + 1] = k end
table.sort(KEYORDER)

local function keyDown(name)
    if name == "MB2" then return ismouse2pressed and ismouse2pressed() or false end
    local vk = KEYMAP[name]
    return vk and iskeypressed(vk) or false
end

-- typing: { vk, normal, shifted }
local TYPE = {}
for c = 0x41, 0x5A do TYPE[#TYPE + 1] = { c, string.char(c + 32), string.char(c) } end
local SHIFTNUM = { ")", "!", "@", "#", "$", "%", "^", "&", "*", "(" }
for c = 0x30, 0x39 do TYPE[#TYPE + 1] = { c, string.char(c), SHIFTNUM[c - 0x2F] } end
for c = 0x60, 0x69 do TYPE[#TYPE + 1] = { c, tostring(c - 0x60), tostring(c - 0x60) } end
for _, e in ipairs({ { 0x20, " ", " " }, { 0xBE, ".", ">" }, { 0xBC, ",", "<" }, { 0xBF, "/", "?" }, { 0xBD, "-", "_" },
    { 0xBB, "=", "+" }, { 0xBA, ";", ":" }, { 0xC0, "`", "~" }, { 0xDB, "[", "{" }, { 0xDD, "]", "}" }, { 0xDC, "\\", "|" },
    { 0xDE, "'", "\"" }, { 0x6E, ".", "." }, { 0x6D, "-", "-" } }) do TYPE[#TYPE + 1] = e end

----------------------------------------------------------------------
-- drawing parts / holders
----------------------------------------------------------------------
local Holder = {}
Holder.__index = Holder

local function newHolder(win, z)
    return setmetatable({ win = win, parts = {}, x = 0, y = 0, shown = false, vis = false, zb = z or 0 }, Holder)
end

local function mkObj(kind, z)
    local o = Drawing.new(kind)
    Library._objs[#Library._objs + 1] = o
    setp(o, "ZIndex", z)
    o.Visible = false
    return o
end

function Holder:_add(p)
    p.row = self.curRow
    self.parts[#self.parts + 1] = p
    return p
end
function Holder:rect(x, y, w, h, role, z, color)
    local o = mkObj("Square", z + self.zb)
    setp(o, "Filled", true)
    return self:_add({ o = o, kind = "rect", x = x, y = y, w = w, h = h, role = role, color = color, fade = FADE[role] })
end
function Holder:text(x, y, s, size, role, z, opts)
    local o = mkObj("Text", z + self.zb)
    setp(o, "Text", s)
    opts = opts or {}
    -- Matcha's Text.Center also centres vertically (text lands above where you put it), so
    -- centred / right-aligned text is placed by hand: x is the centre (cx) or the right edge.
    local p = self:_add({ o = o, kind = "text", x = x, y = y, s = s, size = size, role = role,
                          cx = opts.center and x or nil, right = opts.right })
    if p.cx then
        -- let the renderer centre it (exact for any font); fall back to the width estimate
        if opts.center and setp(o, "Center", true) then p.native, p.x = true, p.cx
        else p.x = p.cx - tw(s, size) / 2 end
    end
    if opts.right then p.x = opts.right - tw(s, size) end
    return p
end
function Holder:circle(x, y, r, role, z, filled)
    local o = mkObj("Circle", z + self.zb)
    setp(o, "NumSides", 24); setp(o, "Thickness", 1); setp(o, "Filled", filled and true or false); setp(o, "Radius", r)
    return self:_add({ o = o, kind = "circle", x = x, y = y, r = r, role = role })
end
function Holder:line(x1, y1, x2, y2, role, z)
    local o = mkObj("Line", z + self.zb)
    setp(o, "Thickness", 1)
    return self:_add({ o = o, kind = "line", x = x1, y = y1, x2 = x2, y2 = y2, role = role })
end
function Holder:image(x, y, w, h, z, data, rnd)
    local o = mkObj("Image", z + self.zb)
    setp(o, "Data", data); setp(o, "Size", Vector2.new(w, h)); setp(o, "Rounding", rnd or w / 2)
    return self:_add({ o = o, kind = "image", x = x, y = y, h = h })
end
function Holder:setText(p, s)
    s = tostring(s)
    if p.s == s then return end
    p.s = s
    p.o.Text = s
    if p.right then p.x = p.right - tw(s, p.size) end
    if p.cx and not p.native then p.x = p.cx - tw(s, p.size) / 2 end
    if self.win then self.win._dirty = true end
end
function Holder:destroy()
    for _, p in ipairs(self.parts) do
        pcall(function() p.o:Remove() end)
    end
    self.parts = {}
    self.shown, self.vis = false, false
end

local function restyle(p)
    local o, L = p.o, Library
    if p.kind == "text" then
        setTextSize(o, p.size + L.SizeDelta)
        if L.FontObj ~= nil then setp(o, "Font", L.FontObj) end
        setp(o, "Outline", L.TextOutline)
        -- font / size changed: re-place centred and right-aligned text
        if p.cx and not p.native then p.x = p.cx - tw(p.s, p.size) / 2 end
        if p.right then p.x = p.right - tw(p.s, p.size) end
    elseif p.fade then
        setp(o, "Transparency", L.Opacity)
    end
    p.sv = L._sv
end

function Holder:sync()
    local L = Library
    if not self.shown then
        if self.vis then
            for _, p in ipairs(self.parts) do
                if p.vis then p.o.Visible = false; p.vis = false end
            end
            self.vis = false
        end
        return
    end
    self.vis = true
    local ct, cb, sv = self.clipTop, self.clipBot, L._sv
    for _, p in ipairs(self.parts) do
        local o, row = p.o, p.row
        local show = p.on ~= false
        local ry, dim = 0, false
        if row then
            if not row.vis or row.group.collapsed then show = false end
            ry, dim = row.y or 0, row.disabled
        end
        if show then
            if p.sv ~= sv then restyle(p) end
            local rl = p.role
            local col = p.color or L.C[(dim and DIM[rl]) or rl]
            if p.cc ~= col then o.Color = col; p.cc = col end
            local ax, ay = self.x + p.x, self.y + ry + p.y
            if p.kind == "rect" then
                local top, bot = ay, ay + p.h
                if ct then top = max(top, ct); bot = min(bot, cb) end
                if bot - top < 1 then show = false
                elseif p.lax ~= ax or p.lt ~= top or p.lb ~= bot or p.lw ~= p.w then
                    p.lax, p.lt, p.lb, p.lw = ax, top, bot, p.w
                    o.Position = Vector2.new(ax, top); o.Size = Vector2.new(p.w, bot - top)
                end
            elseif p.kind == "line" then
                local ay2 = self.y + ry + p.y2
                if ct and (min(ay, ay2) < ct or max(ay, ay2) > cb) then show = false end
                local bx = self.x + p.x2
                if p.lax ~= ax or p.lay ~= ay or p.lbx ~= bx or p.lby ~= ay2 then
                    p.lax, p.lay, p.lbx, p.lby = ax, ay, bx, ay2
                    o.From = Vector2.new(ax, ay); o.To = Vector2.new(bx, ay2)
                end
            elseif p.kind == "circle" then
                if ct and (ay - p.r < ct or ay + p.r > cb) then show = false end
                if p.lax ~= ax or p.lay ~= ay then p.lax, p.lay = ax, ay; o.Position = Vector2.new(ax, ay) end
            else
                local h = (p.kind == "text") and (p.size + 4) or (p.h or 0)
                if ct and (ay < ct or ay + h > cb) then show = false end
                if p.native then ay = ay + (p.size + L.SizeDelta + 4) / 2 end
                if p.lax ~= ax or p.lay ~= ay then p.lax, p.lay = ax, ay; o.Position = Vector2.new(ax, ay) end
            end
        end
        if p.vis ~= show then o.Visible = show; p.vis = show end
    end
end

----------------------------------------------------------------------
-- handles (one per widget)
----------------------------------------------------------------------
local Handle = {}
Handle.__index = Handle

function Handle:Get() return self.value end
function Handle:Set(v, silent)
    if self._coerce then v = self._coerce(self, v) end
    if v == nil then return self end
    if self._same and self._same(self.value, v) then return self end
    self.value = v
    self._apply(self, v)
    if not silent then self:_fire() end
    return self
end
function Handle:_fire()
    if self.callback then
        local ok, err = pcall(self.callback, self._cbv and self._cbv(self) or self.value, self)
        if not ok then warn("[ZeroUI] callback '" .. tostring(self.flag or self.text) .. "': " .. tostring(err)) end
    end
    for _, fn in ipairs(self.listeners) do pcall(fn, self._cbv and self._cbv(self) or self.value, self) end
    self.win:_changed(self)
end
function Handle:OnChanged(fn) self.listeners[#self.listeners + 1] = fn; return self end
function Handle:SetText(t)
    self.text = tostring(t)
    if self.labelPart then self.group.holder:setText(self.labelPart, self.text) end
    return self
end
function Handle:SetVisible(b)
    self.row.userHidden = not b
    self.win:_updateDeps(); self.win._dirty = true
    return self
end
function Handle:SetEnabled(b)
    self.row.forceDisabled = not b
    self.win:_updateDeps(); self.win._dirty = true
    return self
end
function Handle:Reset()
    if self.default ~= nil then self:Set(self.default) end
    return self
end

----------------------------------------------------------------------
-- popups (dropdown list, colour picker)
----------------------------------------------------------------------
function Library:_closePopup()
    local p = self._popup
    if not p then return end
    self._popup = nil
    p.dead = true
    if self._focus and self._focus.pop == p then self._focus = nil end
    p.holder:destroy()
    if p.win then p.win._dirty = true end
end

local function popupBase(win, ax, ay, w, h)
    local vw, vh = Library:_viewport()
    ax = clamp(ax, 4, max(4, vw - w - 4))
    if ay + h > vh - 4 then ay = max(4, vh - h - 4) end
    local hd = newHolder(win, 100)
    hd.x, hd.y, hd.shown = ax, ay, true
    hd:rect(-1, -1, w + 2, h + 2, "line", 1)
    hd:rect(0, 0, w, h, "card", 2)
    return hd, ax, ay
end

function Library:_openDropdown(h, ax, ay, w)
    local win = h.win
    local vals = h.values
    local n = #vals
    local ITEM, MAXV, SEARCH_H = 22, 10, 30
    local searchable = n > 6                       -- small lists don't need a search box
    local visN = min(n, MAXV)
    local top = searchable and SEARCH_H or 0
    local height = top + visN * ITEM + 4
    local oy = ay
    if oy + height > select(2, self:_viewport()) - 4 then oy = ay - height - 28 end   -- flip above the box
    local hd, px, py = popupBase(win, ax, oy, w, height)
    local pop = { win = win, holder = hd, owner = h, x = px, y = py, w = w, h = height, offset = 0, query = "", caret = true }
    local list = vals                              -- currently visible (filtered) values

    -- search box
    local sTxt
    if searchable then
        hd:rect(6, 5, w - 12, 22, "line", 3)
        hd:rect(7, 6, w - 14, 20, "box", 4)
        sTxt = hd:text(13, 9, "", 13, "mute", 5)
    end
    -- scrollbar + empty message
    local sbTrack = hd:rect(w - 6, top + 3, 3, visN * ITEM, "line", 4); sbTrack.on = false
    local sbThumb = hd:rect(w - 6, top + 3, 3, 20, "mute", 5); sbThumb.on = false
    local emptyTxt = hd:text(10, top + 5, "no matches", 13, "mute", 5); emptyTxt.on = false

    local slots = {}
    for i = 1, visN do
        local y = top + 2 + (i - 1) * ITEM
        local hov = hd:rect(2, y, w - 4, ITEM, "hover", 3); hov.on = false
        local mark = hd:rect(w - 16, y + 7, 8, 8, "accent", 4); mark.on = false
        local txt = hd:text(10, y + 3, "", 13, "sub", 5)
        slots[i] = { hov = hov, mark = mark, txt = txt }
    end
    local hoverIdx
    local function selected(v)
        if h.multi then return h.value[v] == true end
        return h.value == v
    end
    local function maxOffset() return max(0, #list - visN) end

    function pop.refilter()
        local q = string.lower(pop.query or "")
        if q == "" then list = vals
        else
            local pre, mid = {}, {}
            for _, v in ipairs(vals) do
                local l = string.lower(tostring(v))
                local at = string.find(l, q, 1, true)
                if at == 1 then pre[#pre + 1] = v elseif at then mid[#mid + 1] = v end
            end
            for _, v in ipairs(mid) do pre[#pre + 1] = v end
            list = pre
        end
        pop.offset = clamp(pop.offset, 0, maxOffset())
        hoverIdx = nil
    end

    function pop.update()
        if pop.dead then return end
        if sTxt then
            if pop.query == "" and not (Library._focus and Library._focus.pop == pop) then
                hd:setText(sTxt, "search..."); sTxt.role = "mute"
            else
                hd:setText(sTxt, pop.query .. (pop.caret and "|" or " ")); sTxt.role = "text"
            end
        end
        for i = 1, visN do
            local v = list[pop.offset + i]
            local s = slots[i]
            if v ~= nil then
                local str = tostring(v)
                local maxc = floor((w - 38) / (13 * 0.54))
                if #str > maxc then str = string.sub(str, 1, maxc - 1) .. "." end
                hd:setText(s.txt, str)
                s.txt.on = true
                s.txt.role = selected(v) and "accent" or ((hoverIdx == i) and "text" or "sub")
                s.mark.on = h.multi and selected(v)
                s.hov.on = hoverIdx == i
            else
                s.txt.on, s.mark.on, s.hov.on = false, false, false
            end
        end
        emptyTxt.on = #list == 0
        -- scrollbar thumb
        local mo = maxOffset()
        if mo > 0 then
            local trackH = visN * ITEM
            local thumbH = max(18, floor(trackH * visN / #list))
            sbTrack.on, sbThumb.on = true, true
            sbThumb.h = thumbH
            sbThumb.y = top + 3 + floor((trackH - thumbH) * (pop.offset / mo))
        else
            sbTrack.on, sbThumb.on = false, false
        end
        hd:sync()
    end

    function pop.idxAt(mx, my)
        if not inRect(mx, my, px, py + top, w, height - top) then return nil end
        local i = floor((my - py - top - 2) / ITEM) + 1
        if i >= 1 and i <= visN and list[pop.offset + i] ~= nil then return i end
    end
    function pop.hover(mx, my)
        local i = pop.idxAt(mx, my)
        if i ~= hoverIdx then hoverIdx = i; pop.update() end
    end

    local function pick(v)
        if h.multi then
            local nv = copy(h.value)
            if nv[v] then nv[v] = nil else nv[v] = true end
            h:Set(nv)
            pop.update()
        else
            h:Set(v)
            Library:_closePopup()
        end
    end

    local function focusSearch()
        if not searchable then return end
        Library:_focusInput({
            pop = pop, win = win, buf = pop.query, max = 24,
            change = function(q)
                pop.query = q
                pop.offset = 0
                pop.refilter()
                pop.update()
            end,
            repaint = function(c) pop.caret = c and true or false; pop.update() end,
            leave = function(vk)
                if vk == 0x0D then                       -- enter: take the hovered / first match
                    local v = (hoverIdx and list[pop.offset + hoverIdx]) or list[1]
                    if v ~= nil then pick(v) end
                    return h.multi == true                   -- multi keeps the box focused
                end
                Library:_closePopup()                    -- esc closes the list
            end,
        })
    end

    function pop.press(mx, my)
        if not inRect(mx, my, px, py, w, height) then return false end
        -- search box
        if searchable and my < py + top then
            if not (Library._focus and Library._focus.pop == pop) then focusSearch() end
            return true
        end
        -- scrollbar drag
        if maxOffset() > 0 and mx >= px + w - 12 then
            local trackH = visN * ITEM
            local function seek(y)
                local f = clamp((y - (py + top + 3)) / trackH, 0, 1)
                pop.offset = floor(f * maxOffset() + .5)
                pop.update()
            end
            Library._drag = { win = win, fn = function(_, y, phase) if phase ~= "release" then seek(y) end end }
            seek(my)
            return true
        end
        local i = pop.idxAt(mx, my)
        if i then pick(list[pop.offset + i]) end
        return true
    end

    function pop.scroll(dir)
        if maxOffset() <= 0 then return end
        pop.offset = clamp(pop.offset + dir * 3, 0, maxOffset())
        pop.update()
    end

    self._popup = pop
    pop.refilter()
    pop.update()
    focusSearch()                                    -- start typing right away
end

function Library:_openColor(h, ax, ay)
    local win = h.win
    local W, H = 210, 134
    local hd, px, py = popupBase(win, ax, ay, W, H)
    local pop = { win = win, holder = hd, owner = h, x = px, y = py, w = W, h = H }
    local HS, SS = 38, 19
    local hue, sat, val = h.hsv[1], h.hsv[2], h.hsv[3]
    local hueSeg, satSeg, valSeg = {}, {}, {}
    for i = 1, HS do hueSeg[i] = hd:rect(10 + (i - 1) * 5, 10, 5, 14, nil, 3, C3(hsv2rgb((i - .5) / HS, 1, 1))) end
    for i = 1, SS do satSeg[i] = hd:rect(10 + (i - 1) * 10, 40, 10, 14, nil, 3, C3({ 0, 0, 0 })) end
    for i = 1, SS do valSeg[i] = hd:rect(10 + (i - 1) * 10, 70, 10, 14, nil, 3, C3({ 0, 0, 0 })) end
    local hm = hd:rect(10, 8, 2, 18, "text", 5)
    local sm = hd:rect(10, 38, 2, 18, "text", 5)
    local vm = hd:rect(10, 68, 2, 18, "text", 5)
    hd:text(10, 27, "hue", 10, "mute", 4); hd:text(10, 57, "saturation", 10, "mute", 4); hd:text(10, 87, "value", 10, "mute", 4)
    local prevBox = hd:rect(10, 104, 44, 22, nil, 4, C3({ 255, 255, 255 }))
    hd:rect(9, 103, 46, 24, "line", 3)
    local hexTxt = hd:text(62, 108, "", 13, "text", 4)

    local function repaint()
        for i = 1, SS do
            satSeg[i].color = C3(hsv2rgb(hue, (i - 1) / (SS - 1), 1))
            valSeg[i].color = C3(hsv2rgb(hue, sat, (i - 1) / (SS - 1)))
            satSeg[i].cc, valSeg[i].cc = nil, nil
        end
        local rgb = hsv2rgb(hue, sat, val)
        prevBox.color = C3(rgb); prevBox.cc = nil
        hm.x = 10 + hue * 188
        sm.x = 10 + sat * 188
        vm.x = 10 + val * 188
        hd:setText(hexTxt, rgb2hex(rgb))
        hd:sync()
    end
    local function commit()
        h:SetHSV(hue, sat, val)
    end
    local active
    local function drag(mx)
        local f = clamp((mx - (px + 10)) / 190, 0, 1)
        if active == "hue" then hue = min(f, .9999) elseif active == "sat" then sat = f elseif active == "val" then val = f end
        repaint(); commit()
    end
    function pop.press(mx, my)
        if not inRect(mx, my, px, py, W, H) then return false end
        for key, by in pairs({ hue = 10, sat = 40, val = 70 }) do
            if my >= py + by - 4 and my <= py + by + 18 and mx >= px + 6 and mx <= px + 204 then
                active = key
                Library._drag = { fn = function(x, _, phase) if phase ~= "release" then drag(x) end end, win = win }
                drag(mx)
                return true
            end
        end
        return true
    end
    function pop.hover() end
    function pop.scroll() end
    function pop.update() hd:sync() end
    self._popup = pop
    repaint()
end

----------------------------------------------------------------------
-- notifications, watermark, keybind list
----------------------------------------------------------------------
function Library:_viewport()
    local vw, vh = 1920, 1080
    pcall(function()
        local v = game.Workspace.CurrentCamera.ViewportSize
        if v.X > 0 then vw, vh = v.X, v.Y end
    end)
    return vw, vh
end

function Library:Notify(a, dur)
    local o = type(a) == "table" and a or { text = tostring(a), duration = dur }
    local text = tostring(o.text or "")
    local title = o.title and tostring(o.title) or nil
    local life = o.duration or dur or 3
    if o.key then
        for _, t in ipairs(self._toasts) do
            if t.key == o.key then
                t.dead = now(); t.expire = now() + life
                t.hd.parts[#t.hd.parts].s = nil
                t.hd:setText(t.txt, text)
                return
            end
        end
    end
    local w = clamp(max(tw(text, 13), title and tw(title, 13) or 0) + 28, 160, 340)
    local h = title and 46 or 30
    local hd = newHolder(nil, 200)
    hd:rect(-1, -1, w + 2, h + 2, "line", 1)
    hd:rect(0, 0, w, h, "card", 2)
    hd:rect(0, 0, 3, h, "accent", 3)
    local tt = title and hd:text(12, 5, title, 13, "accent", 4)
    local txt = hd:text(12, title and 24 or 8, text, 13, "text", 4)
    hd.w, hd.h = w, h
    hd.shown = true
    self._toasts[#self._toasts + 1] = { hd = hd, txt = txt, key = o.key, expire = now() + life, w = w, h = h }
    self._toastDirty = true
end

function Library:_stepToasts(t)
    local vw = self:_viewport()
    local y, any = 20, false
    for i = #self._toasts, 1, -1 do
        local ts = self._toasts[i]
        if t >= ts.expire then
            ts.hd:destroy(); table.remove(self._toasts, i); any = true
        end
    end
    if #self._toasts > 0 and (any or self._toastDirty) then
        for _, ts in ipairs(self._toasts) do
            ts.hd.x, ts.hd.y = vw - ts.w - 16, y
            ts.hd:sync()
            y = y + ts.h + 8
        end
        self._toastDirty = false
    end
end

-- draggable overlays (watermark / keybind list) -----------------------------------------------
function Library:_overlays()
    return { { key = "wm", hd = self._wm }, { key = "kl", hd = self._kl } }
end
function Library:_pressOverlay(mx, my)
    for _, ov in ipairs(self:_overlays()) do
        local hd = ov.hd
        if hd and hd.shown and hd.bg2 then
            if inRect(mx, my, hd.x, hd.y, hd.bg2.w, hd.bg2.h) then
                local dx, dy = mx - hd.x, my - hd.y
                self:_blur()
                self:_closePopup()
                self._drag = { fn = function(x, y, phase)
                    if phase ~= "drag" then return end
                    local vw, vh = self:_viewport()
                    hd.x = clamp(x - dx, 0, max(0, vw - hd.bg2.w))
                    hd.y = clamp(y - dy, 0, max(0, vh - hd.bg2.h))
                    self["_" .. ov.key .. "Pos"] = { x = hd.x, y = hd.y }
                    hd:sync()
                end }
                return true
            end
        end
    end
    return false
end

function Library:SetWatermark(text)
    self._wmText = tostring(text or "")
    self:_ensureWM()
end
function Library:SetWatermarkVisible(b)
    self._wmVisible = b and true or false
    self:_ensureWM()
end
function Library:_ensureWM()
    if self._wmVisible == nil then self._wmVisible = true end
    if not self._wm then
        local hd = newHolder(nil, 190)
        hd.x, hd.y = 12, 12
        if self._wmPos then hd.x, hd.y = self._wmPos.x, self._wmPos.y end
        hd.bg1 = hd:rect(-1, -1, 202, 26, "line", 1)
        hd.bg2 = hd:rect(0, 0, 200, 24, "card", 2)
        hd:rect(0, 0, 200, 2, "accent", 3)
        hd.txt = hd:text(8, 5, "", 13, "text", 4)
        self._wm = hd
    end
    self._wm.shown = self._wmVisible and not self._dead
    self._wmNext = 0
    if not self._wm.shown then self._wm:sync() end
end
function Library:_stepWM(t)
    local hd = self._wm
    if not hd or not hd.shown or t < (self._wmNext or 0) then return end
    self._wmNext = t + 0.5
    local parts = { self._wmText ~= "" and self._wmText or "zero ui" }
    local ok, ping = pcall(function() return GetPingValue() end)
    if ok and type(ping) == "number" then parts[#parts + 1] = floor(ping) .. "ms" end
    local ok2, tm = pcall(function() return os.date("%H:%M:%S") end)
    if ok2 and tm then parts[#parts + 1] = tm end
    local s = table.concat(parts, "  |  ")
    hd:setText(hd.txt, s)
    local w = tw(s, 13) + 16
    hd.bg1.w, hd.bg2.w = w + 2, w
    hd.parts[3].w = w
    hd:sync()
end

function Library:SetKeybindList(b)
    self._klVisible = b and true or false
    if not self._kl then
        local hd = newHolder(nil, 190)
        hd.x, hd.y = 12, 120
        if self._klPos then hd.x, hd.y = self._klPos.x, self._klPos.y end
        hd.bg1 = hd:rect(-1, -1, 162, 26, "line", 1)
        hd.bg2 = hd:rect(0, 0, 160, 24, "card", 2)
        hd:rect(0, 0, 160, 2, "accent", 3)
        hd:text(8, 5, "keybinds", 13, "accent", 4)
        hd.lines = {}
        for i = 1, 14 do hd.lines[i] = hd:text(8, 8 + i * 17, "", 12, "sub", 4); hd.lines[i].on = false end
        self._kl = hd
    end
    self._kl.shown = self._klVisible and not self._dead
    self._klNext = 0
    if not self._kl.shown then self._kl:sync() end
end
function Library:_stepKL(t)
    local hd = self._kl
    if not hd or not hd.shown or t < (self._klNext or 0) then return end
    self._klNext = t + 0.2
    local n = 0
    for _, win in ipairs(self.Windows) do
        for _, h in ipairs(win.flagOrder) do
            if h.kind == "keybind" and h.key and h.list ~= false and n < 14 then
                n = n + 1
                local ln = hd.lines[n]
                local name = h.bindName or h.text or h.flag or "bind"
                hd:setText(ln, "[" .. h.key .. "] " .. name)
                ln.on = true
                ln.role = h.state and "accent" or "mute"
            end
        end
    end
    for i = n + 1, 14 do hd.lines[i].on = false end
    local hh = 30 + n * 17
    hd.bg1.h, hd.bg2.h = hh + 2, hh
    hd:sync()
end

----------------------------------------------------------------------
-- theme / font API
----------------------------------------------------------------------
function Library:SetTheme(name)
    local p = PRESETS[name] or (type(name) == "string" and self.CustomThemes[name]) or nil
    if type(name) == "table" then p = name end
    if not p then return self end
    for _, k in ipairs(ROLE_LIST) do
        local c = toRGB(p[k])
        if c then self.Roles[k] = c end
    end
    if type(name) == "string" then self.PresetName = name end
    self:_derive()
    if self._onTheme then pcall(self._onTheme) end
    return self
end
function Library:SetThemeColor(role, color)
    local c = toRGB(color)
    if c and self.Roles[role] then self.Roles[role] = c; self:_derive() end
    return self
end
function Library:SetFont(name, size)
    if name and Drawing.Fonts and Drawing.Fonts[name] ~= nil then
        self.FontName, self.FontObj = name, Drawing.Fonts[name]
    end
    if size then self.TextSize = size; self.SizeDelta = size - 13 end
    self._sv = self._sv + 1
    for _, w in ipairs(self.Windows) do w._dirty = true end
    return self
end
function Library:SetOpacity(a)
    self.Opacity = clamp(a, .3, 1)
    self._sv = self._sv + 1
    return self
end
function Library:SetTextOutline(b)
    self.TextOutline = b and true or false
    self._sv = self._sv + 1
    return self
end
function Library:OnUnload(fn) self._unloadFns[#self._unloadFns + 1] = fn end

function Library:FontNames()
    local t = {}
    pcall(function() for k in pairs(Drawing.Fonts) do t[#t + 1] = k end end)
    table.sort(t)
    return t
end

----------------------------------------------------------------------
-- WINDOW
----------------------------------------------------------------------
local Window, Tab, Group = {}, {}, {}
Window.__index, Tab.__index, Group.__index = Window, Tab, Group

local SW = 165          -- sidebar width
local TOP = 64          -- first card y
local CLIP_T, CLIP_B = 56, 8

function Library:CreateWindow(o)
    o = o or {}
    local id = tostring(o.id or o.title or "zero_hub")
    for i = #self.Windows, 1, -1 do
        if self.Windows[i].id == id then self.Windows[i]:Destroy() end
    end
    local size = o.size or { 822, 640 }
    local win = setmetatable({
        id = id, title = o.title or "zero hub", subtitle = o.subtitle or "",
        W = size[1], H = size[2], columns = clamp(o.columns or 2, 1, 3),
        toggleKey = o.toggleKey or "RSHIFT", configFile = o.config, folder = o.folder,
        visible = o.visible ~= false, onUnload = o.onUnload,
        captureInput = o.captureInput, inputGuard = o.inputGuard,
        sections = {}, tabs = {}, flags = {}, flagOrder = {}, query = "", scroll = 0,
        _dirty = true, _pendingLoad = (o.autoload ~= false) and (o.config ~= nil or o.folder ~= nil),
        collapsedGroups = {}, _prevKey = false,
    }, Window)

    local vw, vh = self:_viewport()
    win.x = o.x or max(0, floor((vw - win.W) / 2))
    win.y = o.y or max(0, floor((vh - win.H) / 2))
    win.cardGap = 14
    win.contentX = SW + 14
    win.cardW = floor((win.W - win.contentX - 18 - (win.columns - 1) * win.cardGap) / win.columns)

    -- chrome ------------------------------------------------------
    local W, H = win.W, win.H
    local ch = newHolder(win, 0)
    win.chrome = ch
    ch:rect(0, 0, W, H, "line", 1)
    ch:rect(1, 1, W - 2, H - 2, "win", 1)
    ch:rect(1, 1, SW, H - 2, "side", 2)
    ch:rect(SW + 1, 1, 1, H - 2, "line", 2)
    win.titleP = ch:text(16, 16, win.title, 17, "text", 6)
    win.subP = ch:text(16, 40, win.subtitle, 12, "mute", 6)
    win.crumbSec = ch:text(179, 17, "", 15, "accent", 6)
    win.crumbSep = ch:text(240, 17, ">", 15, "mute", 6)
    win.crumbPage = ch:text(256, 17, "", 15, "text", 6)
    win.searchBorder = ch:rect(W - 131, 10, 115, 30, "line", 3)
    ch:rect(W - 130, 11, 113, 28, "box", 4)
    ch:circle(W - 112, 24, 5, "mute", 5, false)
    ch:line(W - 108, 28, W - 104, 32, "mute", 5)
    win.searchTxt = ch:text(W - 98, 17, "search...", 13, "mute", 5)
    win.noResults = ch:text(win.contentX, TOP + 8, "no results.", 13, "mute", 6); win.noResults.on = false
    win.sbTrack = ch:rect(W - 12, TOP, 5, 100, "box", 4); win.sbTrack.on = false
    win.sbThumb = ch:rect(W - 12, TOP, 5, 30, "mute", 5); win.sbThumb.on = false
    if o.user ~= false then
        ch:rect(14, H - 62, SW - 28, 1, "line", 5)
        ch:circle(34, H - 32, 15, "box", 5, true)
        local uname = "player"
        pcall(function() uname = lp.Name end)
        win.uname = uname
        ch:text(60, H - 40, string.sub(uname, 1, 2) .. string.rep("*", 9), 13, "text", 6)
    end

    self.Windows[#self.Windows + 1] = win
    self:_ensureLoop()
    if o.user ~= false and o.avatar ~= false then win:_loadAvatar() end
    return win
end

function Window:_loadAvatar()
    task.spawn(function()
        local ok, err = pcall(function()
            local id
            pcall(function() id = lp.UserId end)
            if not id or id == 0 then
                local body = HttpService:JSONEncode({ usernames = { self.uname }, excludeBannedUsers = true })
                id = HttpService:JSONDecode(game:HttpPost("https://users.roblox.com/v1/usernames/users", body, "application/json")).data[1].id
            end
            assert(id, "no user id")
            local url
            for _ = 1, 6 do
                local d = HttpService:JSONDecode(game:HttpGet("https://thumbnails.roblox.com/v1/users/avatar-headshot?userIds="
                    .. tostring(id) .. "&size=48x48&format=Png&isCircular=true")).data
                d = d and d[1]
                if d and d.state == "Completed" and d.imageUrl then url = d.imageUrl break end
                wait(0.5)
            end
            assert(url, "thumbnail not ready")
            local bin = game:HttpGet(url)
            if self._dead then return end
            self.chrome:image(19, self.H - 47, 30, 30, 7, bin)
            self._dirty = true
        end)
        if not ok then warnOnce("avatar", "avatar: " .. tostring(err)) end
    end)
end

-- sections / tabs ---------------------------------------------------------
function Window:_section(name)
    name = name or "general"
    for _, s in ipairs(self.sections) do if s.name == name then return s end end
    local s = { name = name, tabs = {}, collapsed = false }
    local hd = newHolder(self, 0)
    hd:text(16, 4, name, 12, "mute", 6)
    s.chevDown = { hd:line(SW - 26, 5, SW - 22, 9, "mute", 6), hd:line(SW - 22, 9, SW - 18, 5, "mute", 6) }
    s.chevRight = { hd:line(SW - 24, 3, SW - 20, 7, "mute", 6), hd:line(SW - 20, 7, SW - 24, 11, "mute", 6) }
    for _, p in ipairs(s.chevRight) do p.on = false end
    s.h = hd
    self.sections[#self.sections + 1] = s
    return s
end

-- a sidebar section header on its own (tabs added later with the same section name join it)
function Window:AddSection(name)
    self:_section(name)
    self._dirty = true
    return self
end

----------------------------------------------------------------------
-- tab icons (vector, drawn from lines / circles) - AddTab(name, section, icon)
-- icon = built-in name below, or an image url ("https://...png"), or nil for the default dot
----------------------------------------------------------------------
local ICON_ALIAS = { aim = "crosshair", settings = "cog", gear = "cog", config = "cog", player = "user",
    character = "user", defense = "shield", block = "shield", guard = "shield", offense = "target",
    shoot = "target", combo = "list", pass = "link", visuals = "eye", esp = "eye", misc = "dot", main = "home",
    lightning = "bolt", teleport = "map", treasure = "star", appraiser = "search", minigames = "play", cast = "target", reel = "bolt", accessories = "star", speed = "bolt", auto = "play", autoplay = "play" }
local ICONS = {
    dot       = function(C, L) C(0, 0, 6, false); C(0, 0, 1.5, true) end,
    target    = function(C, L) C(0, 0, 7, false); C(0, 0, 3.5, false); C(0, 0, 1, true) end,
    crosshair = function(C, L) C(0, 0, 5, false); L(-8, 0, -3, 0); L(3, 0, 8, 0); L(0, -8, 0, -3); L(0, 3, 0, 8) end,
    bolt      = function(C, L) L(3, -8, -4, 1); L(-4, 1, 0, 1); L(0, 1, -3, 8); L(-3, 8, 4, -2); L(4, -2, 0, -2); L(0, -2, 3, -8) end,
    shield    = function(C, L) L(-6, -6, 0, -8); L(0, -8, 6, -6); L(6, -6, 6, 1); L(6, 1, 0, 8); L(0, 8, -6, 1); L(-6, 1, -6, -6) end,
    user      = function(C, L) C(0, -4, 3, false); L(-6, 7, -5, 2); L(-5, 2, 5, 2); L(5, 2, 6, 7); L(-6, 7, 6, 7) end,
    list      = function(C, L) C(-6, -5, 1, true); L(-3, -5, 7, -5); C(-6, 0, 1, true); L(-3, 0, 7, 0); C(-6, 5, 1, true); L(-3, 5, 7, 5) end,
    link      = function(C, L) C(-3, 0, 4, false); C(3, 0, 4, false); L(-3, 0, 3, 0) end,
    cog       = function(C, L) C(0, 0, 3, false); C(0, 0, 6, false); L(0, -8, 0, -6); L(0, 6, 0, 8); L(-8, 0, -6, 0); L(6, 0, 8, 0) end,
    eye       = function(C, L) L(-8, 0, -3, -4); L(-3, -4, 3, -4); L(3, -4, 8, 0); L(8, 0, 3, 4); L(3, 4, -3, 4); L(-3, 4, -8, 0); C(0, 0, 2, true) end,
    home      = function(C, L) L(-8, 0, 0, -7); L(0, -7, 8, 0); L(-6, -1, -6, 7); L(6, -1, 6, 7); L(-6, 7, 6, 7) end,
    play      = function(C, L) L(-4, -7, -4, 7); L(-4, 7, 7, 0); L(7, 0, -4, -7) end,
    flag      = function(C, L) L(-5, -8, -5, 8); L(-5, -8, 6, -4); L(6, -4, -5, 0) end,
    search    = function(C, L) C(-2, -2, 5, false); L(2, 2, 8, 8) end,
    lock      = function(C, L) L(-6, -1, 6, -1); L(6, -1, 6, 8); L(6, 8, -6, 8); L(-6, 8, -6, -1); L(-3, -1, -3, -5); L(-3, -5, 0, -8); L(0, -8, 3, -5); L(3, -5, 3, -1) end,
    bell      = function(C, L) L(-6, 4, -4, -4); L(-4, -4, 0, -8); L(0, -8, 4, -4); L(4, -4, 6, 4); L(-6, 4, 6, 4); C(0, 7, 1.5, true) end,
    chart     = function(C, L) L(-7, -8, -7, 7); L(-7, 7, 8, 7); L(-4, 3, -1, -1); L(-1, -1, 2, 2); L(2, 2, 7, -5) end,
    heart     = function(C, L) C(-3, -3, 3.5, false); C(3, -3, 3.5, false); L(-6.3, -1.5, 0, 8); L(6.3, -1.5, 0, 8) end,
    clock     = function(C, L) C(0, 0, 8, false); L(0, 0, 0, -5); L(0, 0, 4, 2) end,
    plus      = function(C, L) L(-7, 0, 7, 0); L(0, -7, 0, 7) end,
    check     = function(C, L) L(-7, 1, -2, 6); L(-2, 6, 7, -5) end,
    map       = function(C, L) L(-8, -5, -3, -7); L(-3, -7, 3, -5); L(3, -5, 8, -7); L(-8, -5, -8, 6); L(-8, 6, -3, 8); L(-3, 8, 3, 6); L(3, 6, 8, 8); L(8, -7, 8, 8); L(-3, -7, -3, 8); L(3, -5, 3, 6) end,
    star      = function(C, L)
        local pts = {}
        for i = 0, 9 do
            local r = (i % 2 == 0) and 8 or 3.4
            local a = -math.pi / 2 + i * math.pi / 5
            pts[#pts + 1] = { math.cos(a) * r, math.sin(a) * r }
        end
        for i = 1, 10 do local a, b = pts[i], pts[i % 10 + 1]; L(a[1], a[2], b[1], b[2]) end
    end,
}
Library.IconNames = function() local t = {}; for k in pairs(ICONS) do t[#t + 1] = k end table.sort(t) return t end

local TAB_ICONS = true   -- set to false for the plain dot on every tab
local function buildTabIcon(tab, it, icon)
    if not TAB_ICONS then icon = "dot" end
    local cx, cy = 24, 16
    tab.iconParts = {}
    local parts = tab.iconParts
    local function C(x, y, r, fill) parts[#parts + 1] = it:circle(cx + x, cy + y, r, "mute", 6, fill) end
    local function L(x1, y1, x2, y2) parts[#parts + 1] = it:line(cx + x1, cy + y1, cx + x2, cy + y2, "mute", 6) end
    if type(icon) == "string" and string.sub(icon, 1, 4) == "http" then
        task.spawn(function()
            local ok, err = pcall(function()
                local bin = game:HttpGet(icon)
                if tab.win._dead or not bin or #bin == 0 then return end
                local p = it:image(cx - 8, cy - 8, 16, 16, 6, bin, 0)
                p.isImage = true
                parts[#parts + 1] = p
                for i = #parts, 1, -1 do if parts[i] ~= p and not parts[i].isImage then parts[i].on = false end end
                tab.win._dirty = true
            end)
            if not ok then warnOnce("icon_" .. tostring(icon), "tab icon '" .. tostring(icon) .. "': " .. tostring(err)) end
        end)
        ICONS.dot(C, L)   -- placeholder until the image arrives
        return
    end
    local name = type(icon) == "string" and string.lower(icon) or "dot"
    name = ICON_ALIAS[name] or name
    local fn = ICONS[name] or ICONS.dot
    fn(C, L)
end

function Window:AddTab(name, section, icon)
    name = tostring(name)
    local sec = self:_section(section)
    local tab = setmetatable({ win = self, name = name, section = sec, groups = {}, nextCol = 1 }, Tab)
    local it = newHolder(self, 0)
    tab.hover = it:rect(8, 0, SW - 16, 32, "hover", 4); tab.hover.on = false
    tab.act   = it:rect(8, 0, SW - 16, 32, "active", 4); tab.act.on = false
    tab.bar   = it:rect(2, 4, 3, 24, "accent", 5); tab.bar.on = false
    buildTabIcon(tab, it, icon or ICON_ALIAS[string.lower(name)] or string.lower(name))
    tab.lbl   = it:text(42, 8, name, 14, "sub", 6)
    tab.item = it
    sec.tabs[#sec.tabs + 1] = tab
    self.tabs[#self.tabs + 1] = tab
    if not self.active then self.active = tab end
    self._dirty = true
    return tab
end

function Window:SelectTab(t)
    if type(t) == "string" then
        for _, tab in ipairs(self.tabs) do if tab.name == t then t = tab break end end
    end
    if type(t) ~= "table" then return self end
    Library:_closePopup()
    self.active, self.query, self.scroll = t, "", 0
    self._dirty = true
    if self.configFile then self._saveAt = now() + .75 end
    return self
end
function Tab:Select() self.win:SelectTab(self) return self end

function Tab:AddGroup(title, col, opts)
    opts = opts or {}
    local win = self.win
    if col == "left" or col == nil then col = (col == nil) and self.nextCol or 1 elseif col == "right" then col = 2 end
    col = clamp(col, 1, win.columns)
    self.nextCol = (col % win.columns) + 1
    local g = setmetatable({ tab = self, win = win, title = tostring(title), col = col, rows = {}, cw = win.cardW,
        collapsed = opts.collapsed == true }, Group)
    local hd = newHolder(win, 0)
    g.holder = hd
    g.bg = hd:rect(0, 0, g.cw, 100, "card", 3)
    hd:circle(24, 18, 7, "accent", 5, false)
    hd:circle(24, 18, 2, "accent", 5, true)
    hd:text(44, 9, g.title, 15, "text", 6)
    g.tag = hd:text(g.cw - 120, 11, "", 12, "mute", 6); g.tag.on = false
    local cx, cy = g.cw - 22, 18
    g.chevDown  = { hd:line(cx - 5, cy - 2, cx, cy + 3, "mute", 6), hd:line(cx, cy + 3, cx + 5, cy - 2, "mute", 6) }
    g.chevRight = { hd:line(cx - 2, cy - 5, cx + 3, cy, "mute", 6), hd:line(cx + 3, cy, cx - 2, cy + 5, "mute", 6) }
    self.groups[#self.groups + 1] = g
    win._dirty = true
    return g
end
function Tab:AddLeftGroup(t, o) return self:AddGroup(t, 1, o) end
function Tab:AddRightGroup(t, o) return self:AddGroup(t, 2, o) end
function Group:SetCollapsed(b) self.collapsed = b and true or false; self.win._dirty = true; return self end
function Group:Toggle() return self:SetCollapsed(not self.collapsed) end
function Group:SetTitle(t) self.title = tostring(t); return self end

-- flags --------------------------------------------------------------------
function Window:GetValue(flag)
    local h = self.flags[flag]
    return h and h:Get() or nil
end
function Window:SetValue(flag, v, silent)
    local h = self.flags[flag]
    if h then h:Set(v, silent) end
    return self
end
Window.Flags = nil

function Window:_changed(h)
    self._dirty = true
    self:_updateDeps()
    if self.configFile and not self._loading then self._saveAt = now() + .75 end
end

function Window:_updateDeps()
    for _, tab in ipairs(self.tabs) do
        for _, g in ipairs(tab.groups) do
            for _, row in ipairs(g.rows) do
                local ok = true
                local d = row.dep
                if d ~= nil then
                    local fn = false
                    if type(d) == "function" then
                        local s, r = pcall(d); ok = s and r and true or false
                    elseif type(d) == "table" and d.kind then
                        ok = d.value and true or false
                    elseif type(d) == "table" and d[1] then
                        ok = d[1].value == d[2]
                    end
                end
                row.depHidden = (not ok) and row.hideDisabled or false
                row.disabled = (not ok) or row.forceDisabled or false
                row.userHiddenEff = row.userHidden or row.depHidden
            end
        end
    end
end

----------------------------------------------------------------------
-- rows + widgets
----------------------------------------------------------------------
function Group:_row(h, kw, o)
    local row = { group = self, h = h, y = 0, vis = true, hits = {}, kw = string.lower(kw or ""),
                  userHidden = false, dep = o and o.depends, hideDisabled = o and o.hideDisabled }
    self.rows[#self.rows + 1] = row
    self.holder.curRow = row
    return row
end
function Group:_endRow() self.holder.curRow = nil end

local function descOf(o) return o.desc or o.tooltip end
local function descLines(g, o)
    local d = descOf(o)
    if type(d) == "table" then d = d.text end
    return wrapText(d, floor((g.cw - 28) / (12 * 0.54)))
end
local function addDesc(g, lines, y)
    for i, l in ipairs(lines) do g.holder:text(14, y + (i - 1) * 14, l, 12, "mute", 6) end
end

local function newHandle(g, row, kind, o)
    local h = setmetatable({ win = g.win, group = g, row = row, kind = kind, flag = o.flag, text = o.text,
        listeners = {}, callback = o.callback, save = o.save ~= false, default = o.default }, Handle)
    row.handle = h
    if o.flag then
        g.win.flags[o.flag] = h
        Library.Flags[o.flag] = h
        g.win.flagOrder[#g.win.flagOrder + 1] = h
    else
        g.win.flagOrder[#g.win.flagOrder + 1] = h
        h.save = false
    end
    return h
end

local function bw_(s, size) return #tostring(s) * (size + Library.SizeDelta) * 0.45 end
local function badgeOf(g, o, x, y)
    local b = o.badge
    if not b then return 0 end
    local txt, role = b, "accent"
    if type(b) == "table" then txt = b.text or "!" else
        if b == "!" then txt, role = "[!]", "accent" elseif b == "?" then txt = "[?]" elseif b == "p" then txt = "[p]" end
    end
    g.holder:text(x, y, txt, 12, role, 6)
    return tw(txt, 12) + 4
end

-- inline sub-widgets that ride on a toggle row ---------------------------------
local function inlineKeybind(h, o)
    local g, row = h.group, h.row
    g.holder.curRow = row
    local right = h._inlineRight or (g.cw - 14)
    local w = 46
    local x = right - w
    local box = g.holder:rect(x, 3, w, 18, "line", 4)
    local fill = g.holder:rect(x + 1, 4, w - 2, 16, "box", 5)
    local lab = g.holder:text(x + w / 2, 6, "", 12, "sub", 6, { center = true })
    g.holder.curRow = nil
    h._inlineRight = x - 6
    h._inlineLeft = x
    local kb = Library:_makeKeybind(g, row, o, { box = box, fill = fill, lab = lab, x = x, y = 3, w = w, h = 18 }, h)
    table.insert(row.hits, 1, kb._hit)   -- inline hits are tested before the toggle's own full-width hit
    return kb
end

local function inlineColor(h, o)
    local g, row = h.group, h.row
    g.holder.curRow = row
    local right = h._inlineRight or (g.cw - 14)
    local w = 28
    local x = right - w
    local box = g.holder:rect(x, 4, w, 16, "line", 4)
    local sw = g.holder:rect(x + 1, 5, w - 2, 14, nil, 5, C3({ 255, 255, 255 }))
    g.holder.curRow = nil
    h._inlineRight = x - 6
    h._inlineLeft = x
    local c = Library:_makeColor(g, row, o, sw, { x = x, y = 4, w = w, h = 16 })
    table.insert(row.hits, 1, c._hit)
    return c
end

function Group:AddToggle(o)
    local g, hd = self, self.holder
    local lines = descLines(g, o)
    local rh = (#lines > 0) and (28 + #lines * 14 + 10) or 32
    local row = g:_row(rh, (o.text or "") .. " " .. (descOf(o) or ""), o)
    hd:rect(14, 1, 20, 20, "line", 4)
    hd:rect(15, 2, 18, 18, "box", 5)
    local mark = hd:rect(19, 6, 10, 10, "accent", 6)
    local lab = hd:text(44, 2, tostring(o.text or ""), 14, "text", 6)
    badgeOf(g, o, 44 + bw_(o.text or "", 14) + 2, 4)
    addDesc(g, lines, 28)
    g:_endRow()
    local h = newHandle(g, row, "toggle", o)
    h.labelPart = lab
    h.value = o.default == true
    mark.on = h.value
    h._coerce = function(_, v) return v and true or false end
    h._same = function(a, b) return a == b end
    h._apply = function(self, v) mark.on = v; self.win._dirty = true end
    h._hit = { x = 0, y = 0, w = g.cw, h = 24, fn = function(mx, my, phase)
        if phase ~= "press" then return end
        local left = h._inlineLeft
        if left then
            local ax = hd.x
            if mx >= ax + left - 4 then return end
        end
        h:Set(not h.value)
    end }
    row.hits[1] = h._hit
    h.AddKeybind = function(self, ko) return inlineKeybind(self, ko or {}) end
    h.AddColor = function(self, co) return inlineColor(self, co or {}) end
    return h
end

function Group:AddSlider(o)
    local g, hd = self, self.holder
    local lines = descLines(g, o)
    local rh = 46 + #lines * 14 + ((#lines > 0) and 8 or 4)
    local row = g:_row(rh, (o.text or "") .. " " .. (descOf(o) or ""), o)
    local tracks = g.cw - 28
    local lab = hd:text(14, 1, tostring(o.text or ""), 14, "text", 6)
    badgeOf(g, o, 14 + bw_(o.text or "", 14) + 2, 3)
    local valP = hd:text(0, 1, "", 14, "mute", 6, { right = g.cw - 14 })
    hd:rect(14, 26, tracks, 6, "box", 4)
    local fill = hd:rect(14, 26, 10, 6, "accent", 5)
    local knob = hd:circle(14, 29, 7, "text", 7, true)
    addDesc(g, lines, 42)
    g:_endRow()
    local mn, mx, step = o.min or 0, o.max or 100, o.step or 1
    local suffix = o.suffix or ""
    local h = newHandle(g, row, "slider", o)
    h.labelPart = lab
    h.value = clamp(o.default or mn, mn, mx)
    h._coerce = function(_, v)
        v = tonumber(v)
        if not v then return nil end
        v = clamp(v, mn, mx)
        return mn + floor((v - mn) / step + .5) * step
    end
    h._same = function(a, b) return a == b end
    h._apply = function(self, v)
        local f = (mx > mn) and clamp((v - mn) / (mx - mn), 0, 1) or 0
        fill.w = max(1, tracks * f)
        knob.x = 14 + tracks * f
        hd:setText(valP, fmtNum(v, step) .. suffix)
        self.win._dirty = true
    end
    h:_apply(h.value)
    local function setFromX(mxp)
        local f = clamp((mxp - (hd.x + 14)) / tracks, 0, 1)
        h:Set(mn + f * (mx - mn))
    end
    h._hit = { x = 8, y = 18, w = g.cw - 16, h = 24, drag = true, fn = function(mxp, _, phase)
        if phase == "release" then return end
        setFromX(mxp)
    end }
    row.hits[1] = h._hit

    -- click the number (top right) to type an exact value: enter / click away applies, esc cancels
    local function showTyping(buf, caret)
        if buf == nil then
            valP.role = "mute"
            hd:setText(valP, fmtNum(h.value, step) .. suffix)
        else
            valP.role = "accent"
            hd:setText(valP, buf .. (caret and "|" or " "))
        end
        h.win._dirty = true
    end
    h._numHit = { x = g.cw - 14 - 96, y = 0, w = 96, h = 17, fn = function(_, _, phase)
        if phase ~= "press" then return end
        local fcs
        fcs = {
            h = h, buf = "", max = 10, numeric = true, win = g.win,
            change = function(b) showTyping(b, true) end,
            repaint = function(caret) if Library._focus == fcs then showTyping(fcs.buf, caret) end end,
            leave = function(vk) if vk == 0x1B then fcs.cancel = true end end,   -- esc = cancel
            commit = function(b)
                local n = (not fcs.cancel) and tonumber(b) or nil
                if n then h:Set(n) end
                showTyping(nil)
            end,
        }
        Library:_focusInput(fcs)
        showTyping("", true)
    end }
    row.hits[2] = h._numHit
    return h
end

function Group:AddDropdown(o)
    local g, hd = self, self.holder
    local lines = descLines(g, o)
    local rh = 56 + #lines * 14 + ((#lines > 0) and 6 or 0)
    local row = g:_row(rh, (o.text or "") .. " " .. (descOf(o) or ""), o)
    local lab = hd:text(14, 1, tostring(o.text or ""), 14, "text", 6)
    badgeOf(g, o, 14 + bw_(o.text or "", 14) + 2, 3)
    local bw = g.cw - 28
    hd:rect(14, 22, bw, 26, "line", 4)
    hd:rect(15, 23, bw - 2, 24, "box", 5)
    local valP = hd:text(22, 28, "", 13, "text", 6)
    local cx = g.cw - 28
    local cd = { hd:line(cx - 4, 32, cx, 36, "mute", 6), hd:line(cx, 36, cx + 4, 32, "mute", 6) }
    addDesc(g, lines, 54)
    g:_endRow()
    local h = newHandle(g, row, "dropdown", o)
    h.labelPart = lab
    h.values = copy(o.values or {})
    h.multi = o.multi == true
    local function show(self)
        local s
        if self.multi then
            local t = {}
            for _, v in ipairs(self.values) do if self.value[v] then t[#t + 1] = tostring(v) end end
            s = (#t > 0) and table.concat(t, ", ") or "none"
        else s = tostring(self.value == nil and "none" or self.value) end
        local maxc = floor((bw - 40) / (13 * 0.54))
        if #s > maxc then s = string.sub(s, 1, maxc - 1) .. "." end
        hd:setText(valP, s)
    end
    if h.multi then
        h.value = {}
        local d = o.default
        if type(d) == "table" then
            for k, v in pairs(d) do if type(k) == "number" then h.value[v] = true elseif v then h.value[k] = true end end
        end
        h._coerce = function(_, v)
            if type(v) ~= "table" then return nil end
            local m = {}
            for k, x in pairs(v) do if type(k) == "number" then m[x] = true elseif x then m[k] = true end end
            return m
        end
        h._ser = function(self) local t = {}; for _, v in ipairs(self.values) do if self.value[v] then t[#t + 1] = v end end return t end
    else
        h.value = o.default
        if h.value == nil and o.allowNone ~= true then h.value = h.values[1] end
        h._coerce = function(_, v) return v end
        h._same = function(a, b) return a == b end
    end
    h._apply = function(self) show(self); self.win._dirty = true end
    show(h)
    h.SetValues = function(self, vals)
        self.values = copy(vals)
        if not self.multi and self.value ~= nil then
            local found = false
            for _, v in ipairs(self.values) do if v == self.value then found = true end end
            if not found then self:Set(self.values[1]) end
        end
        show(self)
        return self
    end
    h._hit = { x = 14, y = 22, w = bw, h = 26, fn = function(mxp, myp, phase)
        if phase ~= "press" then return end
        local t = now()
        if Library._closedOwner == h and t - (Library._closedAt or 0) < 0.25 then return end
        if #h.values == 0 then return end
        Library:_closePopup()
        Library:_openDropdown(h, hd.x + 14, hd.y + row.y + 50, bw)
    end }
    row.hits[1] = h._hit
    return h
end

-- colour --------------------------------------------------------------------
function Library:_makeColor(g, row, o, swatch, rect)
    local h = setmetatable({ win = g.win, group = g, row = row, kind = "color", flag = o.flag, text = o.text,
        listeners = {}, callback = o.callback, save = o.save ~= false, default = o.default }, Handle)
    if o.flag then g.win.flags[o.flag] = h; Library.Flags[o.flag] = h; g.win.flagOrder[#g.win.flagOrder + 1] = h
    else h.save = false end
    local rgb = toRGB(o.default) or { 255, 255, 255 }
    local hh, ss, vv = rgb2hsv(rgb)
    h.hsv = { hh, ss, vv }
    h.rgb = rgb
    h.value = C3(rgb)
    h._coerce = function(_, v) local c = toRGB(v); if not c then return nil end return c end
    h._same = nil
    h._apply = function(self, c)
        self.rgb = c
        local a, b, d = rgb2hsv(c)
        self.hsv = { a, b, d }
        self.value = C3(c)
        swatch.color = self.value; swatch.cc = nil
        self.win._dirty = true
    end
    h:_apply(rgb)
    h._ser = function(self) return rgb2hex(self.rgb) end
    h._de = function(self, v) return hex2rgb(v) end
    h.GetRGB = function(self) return self.rgb[1], self.rgb[2], self.rgb[3] end
    h.GetHex = function(self) return rgb2hex(self.rgb) end
    h.SetHSV = function(self, a, b, d)
        local c = hsv2rgb(a, b, d)
        self.hsv = { a, b, d }
        self.rgb = c
        self.value = C3(c)
        swatch.color = self.value; swatch.cc = nil
        self.win._dirty = true
        self:_fire()
    end
    h.Set = function(self, v, silent)
        local c = toRGB(v)
        if not c then return self end
        self:_apply(c)
        if not silent then self:_fire() end
        return self
    end
    h._hit = { x = rect.x - 4, y = rect.y - 2, w = rect.w + 8, h = rect.h + 4, fn = function(mx, my, phase)
        if phase ~= "press" then return end
        if Library._closedOwner == h and now() - (Library._closedAt or 0) < 0.25 then return end
        Library:_closePopup()
        local hd = g.holder
        Library:_openColor(h, hd.x + rect.x - 160, hd.y + row.y + rect.y + rect.h + 4)
    end }
    return h
end

function Group:AddColor(o)
    local g, hd = self, self.holder
    local lines = descLines(g, o)
    local rh = (#lines > 0) and (28 + #lines * 14 + 10) or 32
    local row = g:_row(rh, (o.text or "") .. " " .. (descOf(o) or ""), o)
    local lab = hd:text(14, 2, tostring(o.text or ""), 14, "text", 6)
    badgeOf(g, o, 14 + bw_(o.text or "", 14) + 2, 4)
    hd:rect(g.cw - 14 - 34, 2, 34, 18, "line", 4)
    local sw = hd:rect(g.cw - 14 - 33, 3, 32, 16, nil, 5, C3({ 255, 255, 255 }))
    addDesc(g, lines, 28)
    g:_endRow()
    local c = Library:_makeColor(g, row, o, sw, { x = g.cw - 14 - 34, y = 2, w = 34, h = 18 })
    c.labelPart = lab
    row.handle = c
    row.hits[1] = c._hit
    return c
end

-- textbox -----------------------------------------------------------------------
function Group:AddTextbox(o)
    local g, hd = self, self.holder
    local lines = descLines(g, o)
    local rh = 56 + #lines * 14 + ((#lines > 0) and 6 or 0)
    local row = g:_row(rh, (o.text or "") .. " " .. (descOf(o) or ""), o)
    local lab = hd:text(14, 1, tostring(o.text or ""), 14, "text", 6)
    local bw = g.cw - 28
    local border = hd:rect(14, 22, bw, 26, "line", 4)
    hd:rect(15, 23, bw - 2, 24, "box", 5)
    local valP = hd:text(22, 28, "", 13, "text", 6)
    addDesc(g, lines, 54)
    g:_endRow()
    local h = newHandle(g, row, "textbox", o)
    h.labelPart = lab
    h.value = tostring(o.default or "")
    local maxc = floor((bw - 20) / (13 * 0.54))
    local function show(self, caret)
        local s = self.value
        if s == "" and not caret then
            hd:setText(valP, tostring(o.placeholder or "")); valP.role = "mute"
        else
            local t = s
            if #t > maxc - 1 then t = string.sub(t, -(maxc - 1)) end
            hd:setText(valP, t .. (caret and "|" or "")); valP.role = "text"
        end
        border.role = caret and "accent" or "line"
    end
    h._coerce = function(_, v)
        v = tostring(v or "")
        if o.maxLength then v = string.sub(v, 1, o.maxLength) end
        return v
    end
    h._same = function(a, b) return a == b end
    h._apply = function(self) show(self, Library._focus and Library._focus.h == self and Library._blink) end
    show(h)
    h._hit = { x = 14, y = 22, w = bw, h = 26, fn = function(mx, my, phase)
        if phase ~= "press" then return end
        Library:_focusInput({
            h = h, buf = h.value, max = o.maxLength or 60, numeric = o.numeric, win = g.win,
            change = function(s)
                h.value = s
                if o.live then h:_fire() end
                show(h, true)
            end,
            commit = function(s)
                local before = h.value
                h.value = (o.numeric and tonumber(s)) and s or s
                show(h, false)
                h:_fire()
            end,
            repaint = function(caret) show(h, caret) end,
        })
    end }
    row.hits[1] = h._hit
    return h
end

-- keybind -------------------------------------------------------------------------
function Library:_makeKeybind(g, row, o, ui, toggleH)
    local win = g.win
    local h = setmetatable({ win = win, group = g, row = row, kind = "keybind", flag = o.flag, text = o.text,
        listeners = {}, callback = o.callback, save = o.save ~= false, default = o.default, list = o.list,
        notify = o.notify, onClick = o.onClick, sync = o.sync ~= false, toggle = toggleH,
        bindName = o.text or (toggleH and toggleH.text) or o.flag }, Handle)
    if o.flag then win.flags[o.flag] = h; self.Flags[o.flag] = h; win.flagOrder[#win.flagOrder + 1] = h
    else h.save = false; win.flagOrder[#win.flagOrder + 1] = h end
    h.mode = o.mode or "toggle"
    h.key = o.default and string.upper(tostring(o.default)) or nil
    if h.key and not (KEYMAP[h.key] or h.key == "MB2") then h.key = nil end
    h.state = (h.mode == "always")
    local function label(self)
        local s = self.key and tostring(self.key) or "none"
        if self.listening then s = "..." end
        local maxc = floor((ui.w - 6) / (12 * 0.54))
        if #s > maxc then s = string.sub(s, 1, maxc) end
        g.holder:setText(ui.lab, s)
        ui.lab.role = self.listening and "accent" or (self.key and "text" or "mute")
        ui.box.role = self.listening and "accent" or "line"
    end
    h.value = h.key
    h._same = nil
    h._coerce = function(_, v) return v end
    h._apply = function(self, v) self.key = (v and v ~= "") and string.upper(tostring(v)) or nil; self.value = self.key; label(self) end
    h._cbv = function(self) return self.state end
    h._ser = function(self) return { key = self.key or "", mode = self.mode } end
    h._de = function(self, v)
        if type(v) == "table" then self.mode = v.mode or self.mode; return (v.key ~= "") and v.key or nil end
        return v
    end
    h.GetKey = function(self) return self.key end
    h.GetState = function(self) return self.state end
    h.SetMode = function(self, m) if m == "toggle" or m == "hold" or m == "always" then self.mode = m end return self end
    h.OnClick = function(self, fn) self.onClick = fn return self end
    h.Get = function(self) return self.key end
    h.Set = function(self, v, silent)
        if v ~= nil and v ~= "" then
            v = string.upper(tostring(v))
            if not (KEYMAP[v] or v == "MB2") then return self end
        end
        self:_apply(v)
        if not silent then self.win:_changed(self) end
        return self
    end
    label(h)
    h._label = label
    h._hit = { x = ui.x - 3, y = ui.y - 2, w = ui.w + 6, h = ui.h + 4, fn = function(mx, my, phase)
        if phase ~= "press" then return end
        Library:_closePopup()
        Library:_listenKey(h)
    end, right = function()
        local nxt = { toggle = "hold", hold = "always", always = "toggle" }
        h.mode = nxt[h.mode] or "toggle"
        Library:Notify({ text = (h.bindName or "bind") .. " mode: " .. h.mode, duration = 2, key = "mode_" .. tostring(h.flag or h) })
        win:_changed(h)
        h._prev = nil
    end }
    return h
end

function Group:AddKeybind(o)
    local g, hd = self, self.holder
    o = o or {}
    local lines = descLines(g, o)
    local rh = (#lines > 0) and (28 + #lines * 14 + 10) or 32
    local row = g:_row(rh, (o.text or "") .. " " .. (descOf(o) or ""), o)
    local lab = hd:text(14, 2, tostring(o.text or ""), 14, "text", 6)
    local w = 46
    local x = g.cw - 14 - w
    local box = hd:rect(x, 3, w, 18, "line", 4)
    local fill = hd:rect(x + 1, 4, w - 2, 16, "box", 5)
    local kl = hd:text(x + w / 2, 6, "", 12, "sub", 6, { center = true })
    addDesc(g, lines, 28)
    g:_endRow()
    local h = Library:_makeKeybind(g, row, o, { box = box, fill = fill, lab = kl, x = x, y = 3, w = w, h = 18 }, nil)
    h.labelPart = lab
    row.handle = h
    row.hits[1] = h._hit
    return h
end

-- button / label / divider ------------------------------------------------------------
function Group:AddButton(o)
    local g, hd = self, self.holder
    local lines = descLines(g, o)
    local rh = 38 + #lines * 14 + ((#lines > 0) and 6 or 0)
    local row = g:_row(rh, (o.text or "") .. " " .. (descOf(o) or ""), o)
    local bw = g.cw - 28
    local border = hd:rect(14, 2, bw, 28, "line", 4)
    hd:rect(15, 3, bw - 2, 26, "box", 5)
    local lab = hd:text(14 + bw / 2, 9, tostring(o.text or ""), 13, "text", 6, { center = true })
    addDesc(g, lines, 36)
    g:_endRow()
    local h = newHandle(g, row, "button", o)
    h.labelPart = lab
    h.save = false
    h.value = nil
    h._apply = function() end
    h.Get = function() return nil end
    h.Set = function(self) return self end
    local label = tostring(o.text or "")
    h._hit = { x = 14, y = 2, w = bw, h = 28, fn = function(mx, my, phase)
        if phase ~= "press" then return end
        if o.confirm and not h._armed then
            h._armed = now()
            hd:setText(lab, "click again to confirm")
            border.role = "accent"
            return
        end
        h._armed = nil
        hd:setText(lab, h.text or label)
        border.role = "line"
        h:_fire()
        if o.onClick then pcall(o.onClick, h) end
    end }
    h.step = function(self, t)
        if self._armed and t - self._armed > 2.5 then
            self._armed = nil
            hd:setText(lab, self.text or label)
            border.role = "line"
            self.win._dirty = true
        end
    end
    row.hits[1] = h._hit
    h.SetText = function(self, t) self.text = tostring(t); hd:setText(lab, self.text) return self end
    return h
end

function Group:AddLabel(o)
    if type(o) == "string" then o = { text = o } end
    local g, hd = self, self.holder
    local lines = wrapText(o.text, floor((g.cw - 28) / (13 * 0.54)))
    if #lines == 0 then lines = { "" } end
    local row = g:_row(#lines * 15 + 8, o.text, o)
    local parts = {}
    for i, l in ipairs(lines) do parts[i] = hd:text(14, 2 + (i - 1) * 15, l, 13, o.dim and "mute" or "sub", 6) end
    g:_endRow()
    local h = newHandle(g, row, "label", o)
    h.save = false
    h.Get = function() return nil end
    h.Set = function(self) return self end
    h.SetText = function(self, t)
        self.text = tostring(t)
        local ls = wrapText(self.text, floor((g.cw - 28) / (13 * 0.54)))
        for i, p in ipairs(parts) do hd:setText(p, ls[i] or "") end
        return self
    end
    return h
end

function Group:AddDivider()
    local g, hd = self, self.holder
    local row = g:_row(14, "", {})
    hd:rect(14, 6, g.cw - 28, 1, "line", 4)
    g:_endRow()
    local h = newHandle(g, row, "divider", {})
    h.Get = function() return nil end
    return h
end

----------------------------------------------------------------------
-- input helpers (focus typing, key listening)
----------------------------------------------------------------------
function Library:_blur()
    local f = self._focus
    if not f then return end
    self._focus = nil
    if f.commit then pcall(f.commit, f.buf) end
    if f.repaint then pcall(f.repaint, false) end
    if f.win then f.win._dirty = true end
end

function Library:_focusInput(f)
    self:_blur()
    self._focus = f
    self._keys = self._keys or {}
    for _, e in ipairs(TYPE) do self._keys[e[1]] = iskeypressed(e[1]) end
    for _, vk in ipairs({ 0x08, 0x0D, 0x1B }) do self._keys[vk] = iskeypressed(vk) end
    self._blink = true
    if f.repaint then f.repaint(true) end
end

function Library:_typeStep(t)
    local f = self._focus
    if not f then return end
    local shift = iskeypressed(0xA0) or iskeypressed(0xA1)
    local buf = f.buf
    for _, e in ipairs(TYPE) do
        local d = iskeypressed(e[1])
        if d and not self._keys[e[1]] and #buf < (f.max or 60) then
            local ch = shift and e[3] or e[2]
            if not f.numeric or string.find(ch, "[%d%.%-]") then buf = buf .. ch end
        end
        self._keys[e[1]] = d
    end
    local bs = iskeypressed(0x08)
    if bs then
        if not self._keys[0x08] then buf = string.sub(buf, 1, -2); self._bsNext = t + .4
        elseif t >= (self._bsNext or 0) then buf = string.sub(buf, 1, -2); self._bsNext = t + .05 end
    end
    self._keys[0x08] = bs
    local leave, leaveVk = false, nil
    for _, vk in ipairs({ 0x0D, 0x1B }) do
        local d = iskeypressed(vk)
        if d and not self._keys[vk] then leave = true; leaveVk = vk end
        self._keys[vk] = d
    end
    if buf ~= f.buf then
        f.buf = buf
        if f.change then pcall(f.change, buf) end
    end
    local b = (floor(t * 2) % 2) == 0
    if b ~= self._blink then
        self._blink = b
        if f.repaint then f.repaint(b) end
    end
    if leave then
        local keep = false
        if f.leave then local ok, r = pcall(f.leave, leaveVk); keep = ok and r == true end
        if not keep and self._focus == f then self:_blur() end
    end
end

function Library:_listenKey(h)
    self:_blur()
    self._listen = h
    h.listening = true
    h._label(h)
    h.win._dirty = true
    self._lkeys = {}
    for _, name in ipairs(KEYORDER) do self._lkeys[name] = keyDown(name) end
    self._lkeys.MB2 = keyDown("MB2")
    self._lkeys.ESC, self._lkeys.BS = iskeypressed(0x1B), iskeypressed(0x08)
end

function Library:_listenStep()
    local h = self._listen
    if not h then return end
    local esc, bs = iskeypressed(0x1B), iskeypressed(0x08)
    local done, newKey = false, nil
    if esc and not self._lkeys.ESC then done = true
    elseif bs and not self._lkeys.BS then done, newKey = true, "" end
    self._lkeys.ESC, self._lkeys.BS = esc, bs
    if not done then
        for _, name in ipairs(KEYORDER) do
            local d = keyDown(name)
            if d and not self._lkeys[name] then done, newKey = true, name end
            self._lkeys[name] = d
        end
    end
    if done then
        self._listen = nil
        h.listening = false
        if newKey ~= nil then h:Set(newKey) else h._label(h) end
        h._prev = keyDown(h.key or "")
        h.win._dirty = true
    end
end

-- while a text field has focus (or a keybind is listening) keep keystrokes away from the game
-- a window's captureInput / inputGuard may be a bool or a function; false / true respectively means "hands off"
local function optv(v)
    if type(v) == "function" then
        local ok, r = pcall(v)
        if not ok then return nil end
        return r   -- keep a literal false (captureInput = function() return false end)
    end
    return v
end
function Library:_mayBlock()
    for _, w in ipairs(self.Windows) do
        if optv(w.captureInput) == false or optv(w.inputGuard) == true then return false end
    end
    return true
end

-- game-input blocking was removed in 1.0.10: calling setrobloxinput from the menu froze it. Kept as a no-op.
function Library:_gameInput(on) end

-- keybinds polling -------------------------------------------------------------------------
function Library:_pollBinds(t)
    if self._focus or self._listen then return end
    for _, win in ipairs(self.Windows) do
        for _, h in ipairs(win.flagOrder) do
            if h.kind == "keybind" and h.key then
                local d = keyDown(h.key)
                local prev = h._prev
                if prev == nil then prev = d end
                if h.mode == "always" then
                    if not h.state then
                        h.state = true
                        if h.toggle and h.sync then h.toggle:Set(true) end
                        h:_fire()
                    end
                elseif h.mode == "hold" then
                    if d ~= h.state then
                        h.state = d
                        if h.toggle and h.sync then h.toggle:Set(d) end
                        h:_fire()
                    end
                else
                    if d and not prev then
                        if h.toggle and h.sync then
                            h.toggle:Set(not h.toggle.value)
                            h.state = h.toggle.value
                        else
                            h.state = not h.state
                        end
                        if h.onClick then pcall(h.onClick, h) end
                        h:_fire()
                        if h.notify ~= false then
                            local nm = h.bindName or "bind"
                            local txt = (h.toggle or h.onClick == nil) and (nm .. ": " .. (h.state and "on" or "off")) or nm
                            Library:Notify({ text = txt, duration = 2, key = "kb_" .. tostring(h.flag or h) })
                        end
                    end
                end
                h._prev = d
            end
        end
    end
end

----------------------------------------------------------------------
-- layout
----------------------------------------------------------------------
function Window:_groupsInView()
    local terms = termsOf(self.query)
    if #terms == 0 then
        local t = self.active
        local list = {}
        if t then
            for _, g in ipairs(t.groups) do
                g._tag = nil
                for _, r in ipairs(g.rows) do r.sHidden = false end
                list[#list + 1] = g
            end
        end
        return list, false, terms
    end
    local qn = table.concat(terms, " ")
    local list = {}
    for _, tab in ipairs(self.tabs) do
        local tabHit = string.sub(string.lower(tab.name), 1, #qn) == qn
                    or (tab.section.name ~= "" and string.sub(string.lower(tab.section.name), 1, #qn) == qn)
        for _, g in ipairs(tab.groups) do
            local gHit = tabHit or hasAll(string.lower(g.title), terms)
            local any = false
            for _, r in ipairs(g.rows) do
                local hit = gHit or (r.kw ~= "" and hasAll(string.lower(g.title) .. " " .. r.kw, terms))
                r.sHidden = not hit
                if hit then any = true end
            end
            if any then g._tag = tab.name; list[#list + 1] = g end
        end
    end
    return list, true, terms
end

function Window:_layout()
    local L = Library
    local vis = self.visible
    local terms = termsOf(self.query)
    local searching = #terms > 0

    -- sidebar
    local y = 74
    local lastSec
    for _, sec in ipairs(self.sections) do
        sec.h.shown = vis
        sec.h.x, sec.h.y = self.x, self.y + y
        sec.sy = y
        for _, p in ipairs(sec.chevDown) do p.on = not sec.collapsed end
        for _, p in ipairs(sec.chevRight) do p.on = sec.collapsed end
        y = y + 30
        for _, tab in ipairs(sec.tabs) do
            local it = tab.item
            if sec.collapsed then it.shown = false
            else
                it.shown, it.x, it.y, tab.sy = vis, self.x, self.y + y, y
                y = y + 32
            end
            local a = (tab == self.active) and not searching
            local m = searching and (string.sub(string.lower(tab.name), 1, #table.concat(terms, " ")) == table.concat(terms, " "))
            tab.act.on, tab.bar.on = a, a
            local ir = (a or m) and "accent" or "mute"
            for _, ip in ipairs(tab.iconParts or {}) do ip.role = ir end
            tab.lbl.role = (a or m) and "text" or ((searching) and "mute" or "sub")
            tab.hover.on = (tab == self._hoverTab) and not a and not searching
        end
        y = y + 6
    end

    -- breadcrumb
    local lead, tail
    if searching then
        lead, tail = "search", string.sub(self.query, 1, 24)
    else
        lead = self.active and self.active.section.name or ""
        tail = self.active and self.active.name or ""
    end
    self.chrome:setText(self.crumbSec, lead)
    self.chrome:setText(self.crumbPage, tail)
    self.crumbSep.x = 179 + tw(lead, 15) + 8
    self.crumbPage.x = self.crumbSep.x + 16

    -- cards
    local list, isSearch = self:_groupsInView()
    local inList = {}
    local colY = {}
    for i = 1, self.columns do colY[i] = TOP end
    for _, g in ipairs(list) do
        inList[g] = true
        local cy = 44
        for _, r in ipairs(g.rows) do
            r.vis = (not r.userHidden) and (not r.depHidden) and (not r.sHidden)
            if r.vis then r.y = cy; cy = cy + r.h end
        end
        g.dh = g.collapsed and 36 or (cy + 2)
        local col = g.col
        if isSearch then
            col = 1
            for i = 2, self.columns do if colY[i] < colY[col] then col = i end end
        end
        g.dcol, g.ry = col, colY[col]
        colY[col] = colY[col] + g.dh + 14
    end
    local content = 0
    for i = 1, self.columns do content = max(content, colY[i]) end
    content = content - 14
    local view = (self.H - CLIP_B) - TOP
    local maxScroll = max(0, content - TOP - view)
    self.scroll = clamp(self.scroll, 0, maxScroll)

    for _, tab in ipairs(self.tabs) do
        for _, g in ipairs(tab.groups) do
            local hd = g.holder
            hd.shown = vis and inList[g] == true
            if inList[g] then
                g.bg.h = g.dh
                for _, p in ipairs(g.chevDown) do p.on = not g.collapsed end
                for _, p in ipairs(g.chevRight) do p.on = g.collapsed end
                g.tag.on = isSearch and g._tag ~= nil
                if g.tag.on then
                    self.chrome.win = self.chrome.win
                    hd:setText(g.tag, g._tag)
                    g.tag.x = g.cw - 44 - tw(g._tag, 12)
                end
                hd.x = self.x + self.contentX + (g.dcol - 1) * (g.cw + self.cardGap)
                hd.y = self.y + g.ry - self.scroll
                hd.clipTop, hd.clipBot = self.y + CLIP_T, self.y + self.H - CLIP_B
            end
        end
    end
    self.view = list
    self.chrome.x, self.chrome.y, self.chrome.shown = self.x, self.y, vis
    self.noResults.on = isSearch and #list == 0

    -- scrollbar
    self.sb = { max = maxScroll, trackY = TOP, trackH = view, thumbH = 0, thumbY = TOP }
    if maxScroll > 0 then
        local thumbH = max(28, floor(view * view / (content - TOP)))
        local thumbY = TOP + floor((view - thumbH) * (self.scroll / maxScroll))
        self.sb.thumbH, self.sb.thumbY = thumbH, thumbY
        self.sbTrack.y, self.sbTrack.h = TOP, view
        self.sbThumb.y, self.sbThumb.h = thumbY, thumbH
        self.sbTrack.on, self.sbThumb.on = true, true
    else
        self.sbTrack.on, self.sbThumb.on = false, false
    end

    local focus = L._focus
    local sf = focus and focus.search == self
    local s = self.query
    if #s > 12 then s = string.sub(s, -12) end
    if s == "" and not sf then
        self.chrome:setText(self.searchTxt, "search..."); self.searchTxt.role = "mute"
    else
        self.chrome:setText(self.searchTxt, s .. ((sf and L._blink) and "|" or " ")); self.searchTxt.role = "text"
    end
    self.searchBorder.role = sf and "accent" or "line"
end

function Window:Refresh()
    self:_layout()
    self.chrome:sync()
    for _, sec in ipairs(self.sections) do
        sec.h:sync()
        for _, tab in ipairs(sec.tabs) do tab.item:sync() end
    end
    for _, tab in ipairs(self.tabs) do
        for _, g in ipairs(tab.groups) do g.holder:sync() end
    end
    self._dirty = false
end

----------------------------------------------------------------------
-- window input
----------------------------------------------------------------------
function Window:_contains(mx, my) return self.visible and inRect(mx, my, self.x, self.y, self.W, self.H) end

function Window:_setQuery(q)
    Library:_closePopup()
    self.query, self.scroll = q, 0
    self._dirty = true
end

function Window:_scrollTo(my)
    local sb = self.sb
    if not sb or sb.max <= 0 then return end
    local span = sb.trackH - sb.thumbH
    if span <= 0 then return end
    local f = (my - self._sdrag.dy - (self.y + sb.trackY)) / span
    self.scroll = floor(clamp(f, 0, 1) * sb.max + .5)
    self._dirty = true
end

function Window:_press(mx, my)
    local L = Library
    -- search box
    if inRect(mx, my, self.x + self.W - 131, self.y + 10, 115, 30) then
        L:_focusInput({
            search = self, win = self, buf = self.query, max = 24,
            change = function(s) self:_setQuery(s) end,
            repaint = function() self._dirty = true end,
        })
        self._dirty = true
        return true
    end
    -- sidebar
    for _, sec in ipairs(self.sections) do
        if inRect(mx, my, self.x + 8, self.y + sec.sy, SW - 16, 24) then
            sec.collapsed = not sec.collapsed
            self._dirty = true
            return true
        end
        if not sec.collapsed then
            for _, tab in ipairs(sec.tabs) do
                if inRect(mx, my, self.x + 8, self.y + tab.sy, SW - 16, 32) then
                    self:SelectTab(tab)
                    return true
                end
            end
        end
    end
    -- scrollbar
    local sb = self.sb
    if sb and sb.max > 0 and inRect(mx, my, self.x + self.W - 18, self.y + sb.trackY, 16, sb.trackH) then
        local top = self.y + sb.thumbY
        if my >= top and my <= top + sb.thumbH then self._sdrag = { dy = my - top }
        else self._sdrag = { dy = sb.thumbH / 2 }; self:_scrollTo(my) end
        L._drag = { win = self, fn = function(_, y, phase) if phase ~= "release" then self:_scrollTo(y) end end }
        return true
    end
    -- cards
    if my >= self.y + CLIP_T and my <= self.y + self.H - CLIP_B then
        for _, g in ipairs(self.view or {}) do
            local hd = g.holder
            if inRect(mx, my, hd.x, hd.y, g.cw, g.dh) then
                if my <= hd.y + 36 then
                    g.collapsed = not g.collapsed
                    self.collapsedGroups[g.tab.name .. "/" .. g.title] = g.collapsed
                    if self.configFile then self._saveAt = now() + .75 end
                    self._dirty = true
                    return true
                end
                if not g.collapsed then
                    for _, row in ipairs(g.rows) do
                        if row.vis and not row.disabled then
                            for _, ht in ipairs(row.hits) do
                                if inRect(mx, my, hd.x + ht.x, hd.y + row.y + ht.y, ht.w, ht.h) then
                                    ht.fn(mx, my, "press")
                                    if ht.drag then L._drag = { fn = ht.fn, win = self } end
                                    self._dirty = true
                                    return true
                                end
                            end
                        end
                    end
                end
                return true
            end
        end
    end
    -- title bar drag
    if inRect(mx, my, self.x, self.y, self.W - 140, 56) then
        L._drag = { win = self, fn = function(x, y, phase)
            if phase == "drag" then
                self.x, self.y = x - self._wd.dx, y - self._wd.dy
                self._dirty = true
            end
        end }
        self._wd = { dx = mx - self.x, dy = my - self.y }
        L:_closePopup()
        return true
    end
    return true
end

function Window:_rpress(mx, my)
    if my < self.y + CLIP_T or my > self.y + self.H - CLIP_B then return end
    for _, g in ipairs(self.view or {}) do
        local hd = g.holder
        if not g.collapsed and inRect(mx, my, hd.x, hd.y, g.cw, g.dh) then
            for _, row in ipairs(g.rows) do
                if row.vis then
                    for _, ht in ipairs(row.hits) do
                        if ht.right and inRect(mx, my, hd.x + ht.x, hd.y + row.y + ht.y, ht.w, ht.h) then ht.right() return end
                    end
                end
            end
        end
    end
end

function Window:Show() self.visible = true; self._dirty = true; return self end
function Window:Hide()
    self.visible = false
    Library:_closePopup(); Library:_blur()
    self._dirty = true
    return self
end
function Window:Toggle() if self.visible then return self:Hide() end return self:Show() end
function Window:IsVisible() return self.visible end
function Window:SetTitle(t, s)
    self.chrome:setText(self.titleP, tostring(t))
    if s then self.chrome:setText(self.subP, tostring(s)) end
    return self
end

----------------------------------------------------------------------
-- persistence
----------------------------------------------------------------------
local function ensureFolder(path)
    local acc = ""
    for part in string.gmatch(path, "[^/\\]+") do
        acc = (acc == "") and part or (acc .. "/" .. part)
        pcall(function() if not isfolder(acc) then makefolder(acc) end end)
    end
end

function Window:_collect(withWindow)
    local flags = {}
    for _, h in ipairs(self.flagOrder) do
        if h.flag and h.save then
            local v
            if h._ser then v = h:_ser() else v = h.value end
            if v ~= nil then flags[h.flag] = v end
        end
    end
    local d = { flags = flags }
    if withWindow then
        d.window = { x = self.x, y = self.y, tab = self.active and self.active.name, collapsed = self.collapsedGroups,
            wm = Library._wmPos, kl = Library._klPos }
    end
    return d
end

function Window:_apply(d)
    if type(d) ~= "table" then return end
    self._loading = true
    for flag, v in pairs(d.flags or {}) do
        local h = self.flags[flag]
        if h and h.save then
            local val = v
            if h._de then val = h:_de(v) end
            if h.kind == "keybind" then
                h.mode = type(v) == "table" and v.mode or h.mode
                pcall(function() h:Set(val, true) end)
                h._prev = nil
                if h.flag then h:_fire() end
            else
                pcall(function() h:Set(val) end)
            end
        end
    end
    self._loading = false
    self:_updateDeps()
    self._dirty = true
end

local function encode(t) local ok, s = pcall(function() return HttpService:JSONEncode(t) end) return ok and s or nil end
local function decode(s) local ok, t = pcall(function() return HttpService:JSONDecode(s) end) return ok and t or nil end

function Window:SaveSettings()
    if not self.configFile then return self end
    local s = encode(self:_collect(true))
    if s then pcall(writefile, self.configFile, s) end
    return self
end

function Window:LoadSettings()
    self._pendingLoad = false
    if not self.configFile then return self end
    local ok, s = pcall(function() if isfile(self.configFile) then return readfile(self.configFile) end end)
    local d = ok and s and decode(s)
    if d then
        self:_apply(d)
        local w = d.window
        if type(w) == "table" then
            if type(w.x) == "number" and type(w.y) == "number" then self.x, self.y = w.x, w.y end
            for _, k in ipairs({ "wm", "kl" }) do
                local pp = w[k]
                if type(pp) == "table" and type(pp.x) == "number" and type(pp.y) == "number" then
                    Library["_" .. k .. "Pos"] = { x = pp.x, y = pp.y }
                    local hd = Library["_" .. k]
                    if hd then hd.x, hd.y = pp.x, pp.y; hd:sync() end
                end
            end
            if type(w.collapsed) == "table" then
                for _, tab in ipairs(self.tabs) do
                    for _, g in ipairs(tab.groups) do
                        local c = w.collapsed[tab.name .. "/" .. g.title]
                        if c ~= nil then g.collapsed = c; self.collapsedGroups[tab.name .. "/" .. g.title] = c end
                    end
                end
            end
            if w.tab then self:SelectTab(w.tab) end
        end
    end
    self._dirty = true
    return self
end

local function cfgPath(self, name) return (self.folder or "ZeroUI") .. "/" .. tostring(name) .. ".json" end
function Window:SaveConfig(name)
    if not name or name == "" then return false end
    ensureFolder(self.folder or "ZeroUI")
    local s = encode(self:_collect(false))
    if not s then return false end
    return pcall(writefile, cfgPath(self, name), s)
end
function Window:LoadConfig(name)
    local ok, s = pcall(function() local p = cfgPath(self, name); if isfile(p) then return readfile(p) end end)
    local d = ok and s and decode(s)
    if not d then return false end
    self:_apply(d)
    if self.configFile then self._saveAt = now() + .75 end
    return true
end
function Window:DeleteConfig(name)
    return pcall(function() delfile(cfgPath(self, name)) end)
end
function Window:ListConfigs()
    local out = {}
    pcall(function()
        for _, p in ipairs(listfiles(self.folder or "ZeroUI")) do
            local n = string.match(string.gsub(p, "\\", "/"), "([^/]+)%.json$")
            -- theme store lives in the same folder: keep it out of the config list
            if n and n ~= "__themes" then out[#out + 1] = n end
        end
    end)
    table.sort(out)
    return out
end
function Window:SetAutoload(name)
    ensureFolder(self.folder or "ZeroUI")
    pcall(writefile, (self.folder or "ZeroUI") .. "/__autoload.txt", name or "")
    return self
end
function Window:GetAutoload()
    local ok, s = pcall(function()
        local p = (self.folder or "ZeroUI") .. "/__autoload.txt"
        if isfile(p) then return readfile(p) end
    end)
    if ok and s and s ~= "" then return s end
end

function Window:ResetAll()
    for _, h in ipairs(self.flagOrder) do
        if h.flag and h.default ~= nil and string.sub(h.flag, 1, 2) ~= "__" and h.kind ~= "keybind" and h.kind ~= "button" then
            pcall(function() h:Set(h.default) end)
        end
    end
    Library:Notify("settings reset to defaults", 3)
end

function Window:Destroy()
    Library:_closePopup()
    Library:_blur()
    self._dead = true
    self.chrome:destroy()
    for _, sec in ipairs(self.sections) do
        sec.h:destroy()
        for _, tab in ipairs(sec.tabs) do
            tab.item:destroy()
            for _, g in ipairs(tab.groups) do g.holder:destroy() end
        end
    end
    for i, w in ipairs(Library.Windows) do if w == self then table.remove(Library.Windows, i) break end end
    for _, h in ipairs(self.flagOrder) do if h.flag and Library.Flags[h.flag] == h then Library.Flags[h.flag] = nil end end
end

function Window:Unload()
    if self.configFile then self:SaveSettings() end
    if self.onUnload then pcall(self.onUnload) end
    self:Destroy()
    if #Library.Windows == 0 then Library:Unload() end
end

----------------------------------------------------------------------
-- custom (named) themes
----------------------------------------------------------------------
local function themePath(self) return (self.folder or "ZeroUI") .. "/__themes.json" end

function Window:_readThemes()
    local ok, s = pcall(function() local p = themePath(self); if isfile(p) then return readfile(p) end end)
    local d = ok and s and decode(s)
    return type(d) == "table" and d or {}
end
function Window:_writeThemes(all)
    ensureFolder(self.folder or "ZeroUI")
    local s = encode(all)
    if not s then return false end
    return (pcall(writefile, themePath(self), s))
end
function Window:_loadThemes()
    Library.CustomThemes = self:_readThemes()
end
function Window:ListThemes()
    local out = {}
    for n in pairs(Library.CustomThemes) do out[#out + 1] = n end
    table.sort(out)
    return out
end
-- saves the colours currently on screen under a name; returns ok, name-or-error
function Window:SaveTheme(name)
    name = string.gsub(tostring(name or ""), "^%s+", "")
    name = string.gsub(name, "%s+$", "")
    if name == "" then return false, "type a theme name first" end
    if PRESETS[name] then return false, "that name is a built-in preset" end
    local t = {}
    for _, role in ipairs(ROLE_LIST) do t[role] = rgb2hex(Library.Roles[role]) end
    local all = self:_readThemes()
    all[name] = t
    if not self:_writeThemes(all) then return false, "could not write theme file" end
    Library.CustomThemes = all
    Library.PresetName = name
    return true, name
end
function Window:ApplyTheme(name)
    if not Library.CustomThemes[name] then return false end
    Library:SetTheme(name)
    return true
end
function Window:DeleteTheme(name)
    local all = self:_readThemes()
    if not all[name] then return false end
    all[name] = nil
    if not self:_writeThemes(all) then return false end
    Library.CustomThemes = all
    return true
end

----------------------------------------------------------------------
-- settings tab
----------------------------------------------------------------------
function Window:AddSettingsTab(name, section)
    local win = self
    local tab = self:AddTab(name or "settings", section or "hub", "cog")

    win:_loadThemes()
    local function allPresets()
        local t = {}
        for _, n in ipairs(PRESET_ORDER) do t[#t + 1] = n end
        for _, n in ipairs(win:ListThemes()) do t[#t + 1] = n end
        return t
    end

    local ui = tab:AddGroup("interface", 1)
    local presetDD = ui:AddDropdown({ text = "preset", flag = "__preset", values = allPresets(), default = Library.PresetName,
        callback = function(v) Library:SetTheme(v) end })
    ui:AddSlider({ text = "opacity", flag = "__opacity", min = 30, max = 100, default = floor(Library.Opacity * 100), suffix = "%",
        callback = function(v) Library:SetOpacity(v / 100) end })
    ui:AddToggle({ text = "text outline", flag = "__outline", default = Library.TextOutline,
        callback = function(v) Library:SetTextOutline(v) end })
    local fonts = Library:FontNames()
    if #fonts > 0 then
        ui:AddDropdown({ text = "font", flag = "__font", values = fonts, default = Library.FontName,
            callback = function(v) Library:SetFont(v) end })
    end
    ui:AddSlider({ text = "font size", flag = "__fontsize", min = 10, max = 20, default = Library.TextSize,
        callback = function(v) Library:SetFont(nil, v) end })
    ui:AddToggle({ text = "watermark", flag = "__watermark", default = false,
        callback = function(v) Library:SetWatermarkVisible(v) end })
    ui:AddToggle({ text = "keybind list", flag = "__keylist", default = false,
        callback = function(v) Library:SetKeybindList(v) end })

    local th = tab:AddGroup("theme colors", 1, { collapsed = true })
    local roleHandles = {}
    local labels = { accent = "accent", background = "background", group = "cards", topbar = "sidebar", border = "border", text = "text" }
    for _, role in ipairs(ROLE_LIST) do
        roleHandles[role] = th:AddColor({ text = labels[role], flag = "__c_" .. role, default = rgb2hex(Library.Roles[role]),
            callback = function(c)
                -- ignore echoes while a preset is being applied
                if win._themeSync then return end
                Library:SetThemeColor(role, c)
            end })
    end
    Library._onTheme = function()
        win._themeSync = true
        for role, h in pairs(roleHandles) do pcall(function() h:Set(rgb2hex(Library.Roles[role]), true) end) end
        pcall(function() presetDD:Set(Library.PresetName, true) end)
        win._themeSync = false
    end

    -- named themes: tweak the colours above, name them, save; apply or delete later
    local ct = tab:AddGroup("custom themes", 1)
    local tName = ct:AddTextbox({ text = "theme name", flag = "__themename", placeholder = "type a name",
        save = false, maxLength = 24, desc = "tweak the colors above, name it, then save" })
    local tList = ct:AddDropdown({ text = "saved themes", flag = "__themelist", values = { "none" },
        default = "none", save = false })
    local function refreshThemes()
        local l = win:ListThemes()
        tList:SetValues(#l > 0 and l or { "none" })
        presetDD:SetValues(allPresets())
        pcall(function() presetDD:Set(Library.PresetName, true) end)
    end
    local function chosenTheme()
        local n = tName:Get()
        if n == "" then n = tList:Get() end
        if n == nil or n == "none" or n == "" then return nil end
        return n
    end
    ct:AddButton({ text = "save current colors", callback = function()
        local ok, res = win:SaveTheme(chosenTheme() or "")
        if ok then Library:Notify("saved theme: " .. res, 3); refreshThemes()
        else Library:Notify(tostring(res), 3) end
    end })
    ct:AddButton({ text = "apply", callback = function()
        local n = chosenTheme()
        if n and win:ApplyTheme(n) then Library:Notify("applied theme: " .. n, 3)
        else Library:Notify("no such theme", 3) end
    end })
    ct:AddButton({ text = "delete", confirm = true, callback = function()
        local n = chosenTheme()
        if n and win:DeleteTheme(n) then Library:Notify("deleted theme: " .. n, 3); refreshThemes()
        else Library:Notify("no such theme", 3) end
    end })
    refreshThemes()

    local menu = tab:AddGroup("menu", 2)
    menu:AddKeybind({ text = "menu key", flag = "__menukey", default = win.toggleKey, notify = false, list = false,
        callback = function() end })
    local mk = Library.Flags["__menukey"]
    if mk then
        mk.mode = "toggle"
        mk.onClick = nil
        mk:OnChanged(function() end)
        -- the menu key is read from the handle, so rebinding takes effect immediately
        win._menuKeyHandle = mk
    end
    menu:AddSlider({ text = "cursor offset x", flag = "__curx", min = -80, max = 80, default = 0, suffix = "px",
        desc = "nudge if clicks land left or right of the pointer",
        callback = function(v) Library.Settings.cursorOffset[1] = v end })
    menu:AddSlider({ text = "cursor offset y", flag = "__cury", min = -80, max = 80, default = 0, suffix = "px",
        desc = "nudge if clicks land above or below the pointer",
        callback = function(v) Library.Settings.cursorOffset[2] = v end })
    menu:AddButton({ text = "reset hub settings", confirm = true, desc = "every toggle, slider and colour back to its default",
        callback = function() win:ResetAll() end })
    menu:AddButton({ text = "unload", confirm = true, callback = function() win:Unload() end })

    local cf = tab:AddGroup("configs", 2)
    local nameBox = cf:AddTextbox({ text = "config name", flag = "__cfgname", placeholder = "type a name", save = false, maxLength = 24 })
    local list = cf:AddDropdown({ text = "saved configs", flag = "__cfglist", values = { "none" }, default = "none", save = false })
    local function refresh()
        local l = win:ListConfigs()
        if #l == 0 then l = { "none" } end
        list:SetValues(l)
    end
    local function chosen()
        local n = nameBox:Get()
        if n == "" then n = list:Get() end
        if n == nil or n == "none" or n == "" then return nil end
        return n
    end
    cf:AddButton({ text = "save", callback = function()
        local n = nameBox:Get(); if n == "" then n = chosen() end
        if not n then Library:Notify("type a config name first", 3) return end
        if win:SaveConfig(n) then Library:Notify("saved config: " .. n, 3) else Library:Notify("could not save config", 3) end
        refresh()
    end })
    cf:AddButton({ text = "load", callback = function()
        local n = chosen()
        if n and win:LoadConfig(n) then Library:Notify("loaded config: " .. n, 3) else Library:Notify("no such config", 3) end
    end })
    cf:AddButton({ text = "delete", confirm = true, callback = function()
        local n = chosen()
        if n and win:DeleteConfig(n) then Library:Notify("deleted config: " .. n, 3); refresh() end
    end })
    cf:AddButton({ text = "set as autoload", callback = function()
        local n = chosen()
        if n then win:SetAutoload(n); Library:Notify("autoload: " .. n, 3) end
    end })
    cf:AddButton({ text = "refresh list", callback = refresh })
    refresh()
    return tab
end

----------------------------------------------------------------------
-- main loop
----------------------------------------------------------------------
function Library:_ensureLoop()
    if self._loop or not RunService then return end
    local prevDown, prevR, lastErr = false, false, nil
    local warnedMouse = false
    self._loop = RunService.Heartbeat:Connect(function()
        local ok, err = pcall(function()
            local t = now()
            -- menu key + deferred autoload
            for _, win in ipairs(self.Windows) do
                if win._pendingLoad then
                    win._pendingLoad = false
                    win:LoadSettings()
                    local an = win:GetAutoload()
                    if an then win:LoadConfig(an) end
                end
                local mkh = win._menuKeyHandle
                local keyName = mkh and mkh.key or win.toggleKey
                if mkh then win.toggleKey = keyName or win.toggleKey end
                local d = keyName and keyDown(keyName) or false
                if d and not win._prevKey and not self._focus and not self._listen then win:Toggle() end
                win._prevKey = d
            end

            self:_listenStep()
            self:_typeStep(t)
            self:_pollBinds(t)

            -- buttons waiting for confirmation
            for _, win in ipairs(self.Windows) do
                for _, h in ipairs(win.flagOrder) do if h.step then h:step(t) end end
            end

            local anyVisible = false
            for _, win in ipairs(self.Windows) do if win.visible then anyVisible = true end end

            local overUI = false
            if anyVisible and (not isrbxactive or isrbxactive()) then
                local mx, my = self:_mouse()
                if mx then
                    local down = ismouse1pressed()
                    local rdown = ismouse2pressed and ismouse2pressed() or false
                    local pop = self._popup

                    if pop and pop.hover then pop.hover(mx, my) end

                    -- wheel / page keys
                    local wheel = self._wheel
                    self._wheel = 0
                    local pgU, pgD = iskeypressed(0x21), iskeypressed(0x22)
                    local dir = wheel
                    if pgU and not self._pgU then dir = dir - 2 end
                    if pgD and not self._pgD then dir = dir + 2 end
                    self._pgU, self._pgD = pgU, pgD
                    if dir ~= 0 then
                        if pop and inRect(mx, my, pop.x, pop.y, pop.w, pop.h) then
                            pop.scroll(dir > 0 and 1 or -1)
                        else
                            for i = #self.Windows, 1, -1 do
                                local win = self.Windows[i]
                                if win:_contains(mx, my) then
                                    self:_closePopup()
                                    win.scroll = win.scroll + dir * 60
                                    win._dirty = true
                                    break
                                end
                            end
                        end
                    end

                    if down and not prevDown then
                        local handled = false
                        if pop then
                            if pop.press(mx, my) then handled = true
                            else
                                -- outside click: close, and remember the owner so the same click
                                -- on its opener doesn't immediately reopen it
                                self._closedOwner, self._closedAt = pop.owner, now()
                                self:_closePopup()
                            end
                        end
                        if not handled and self:_pressOverlay(mx, my) then handled = true end
                        if not handled then
                            local f = self._focus
                            local hit
                            for i = #self.Windows, 1, -1 do
                                local win = self.Windows[i]
                                if win:_contains(mx, my) then hit = win break end
                            end
                            if f and not (hit and f.search and inRect(mx, my, hit.x + hit.W - 131, hit.y + 10, 115, 30)) then self:_blur() end
                            if hit then
                                -- bring to front
                                for i, w in ipairs(self.Windows) do if w == hit then table.remove(self.Windows, i) break end end
                                self.Windows[#self.Windows + 1] = hit
                                hit:_press(mx, my)
                            end
                        end
                    elseif down then
                        if self._drag then self._drag.fn(mx, my, "drag") end
                    elseif prevDown then
                        local d = self._drag
                        self._drag = nil
                        if d then d.fn(mx, my, "release") end
                        for _, win in ipairs(self.Windows) do
                            if win._saveAt == nil and win.configFile then win._saveAt = t + .75 end
                        end
                    end
                    if rdown and not prevR then
                        for i = #self.Windows, 1, -1 do
                            local win = self.Windows[i]
                            if win:_contains(mx, my) then win:_rpress(mx, my) break end
                        end
                    end
                    prevDown, prevR = down, rdown
                    for _, win in ipairs(self.Windows) do
                        if win:_contains(mx, my) then overUI = true end
                    end
                    local pp = self._popup
                    if pp and inRect(mx, my, pp.x, pp.y, pp.w, pp.h) then overUI = true end

                    -- sidebar hover
                    if not down then
                        for _, win in ipairs(self.Windows) do
                            local hov
                            if win:_contains(mx, my) then
                                for _, sec in ipairs(win.sections) do
                                    if not sec.collapsed then
                                        for _, tab in ipairs(sec.tabs) do
                                            if inRect(mx, my, win.x + 8, win.y + (tab.sy or -99), SW - 16, 32) then hov = tab end
                                        end
                                    end
                                end
                            end
                            if hov ~= win._hoverTab then win._hoverTab = hov; win._dirty = true end
                        end
                    end
                elseif not warnedMouse then
                    warnedMouse = true
                    warn("[ZeroUI] no mouse position available - the menu draws but cannot be clicked")
                end
            end

            -- hold keys/clicks back from the game while typing, binding, a list is open, or the pointer is on the menu
            self:_gameInput(not (self._focus or self._listen or self._popup))

            -- saves + redraw
            for _, win in ipairs(self.Windows) do
                if win._saveAt and t >= win._saveAt and not self._drag then
                    win._saveAt = nil
                    win:SaveSettings()
                end
                if win._dirty then win:Refresh() end
            end
            if self._popup then self._popup.update() end
            self:_stepToasts(t)
            self:_stepWM(t)
            self:_stepKL(t)
        end)
        if not ok and err ~= lastErr then
            lastErr = err
            warn("[ZeroUI] " .. tostring(err))
        end
    end)
    self._conns[#self._conns + 1] = self._loop
end

function Library:_mouse()
    local m = self._mouseObj
    if not m then
        if self._mouseRetry and now() < self._mouseRetry then return nil end
        self._mouseRetry = now() + .5
        local ok, mm = pcall(function() return lp:GetMouse() end)
        if ok and mm then
            m = mm
            self._mouseObj = mm
            if not self._wheelHooked then
                self._wheelHooked = true
                pcall(function()
                    local f, b = mm.WheelForward, mm.WheelBackward
                    if f then self._conns[#self._conns + 1] = f:Connect(function() self._wheel = self._wheel - 1 end) end
                    if b then self._conns[#self._conns + 1] = b:Connect(function() self._wheel = self._wheel + 1 end) end
                end)
            end
        else
            return nil
        end
    end
    local x, y = m.X, m.Y
    if type(x) ~= "number" or type(y) ~= "number" then self._mouseObj = nil return nil end
    local off = self.Settings.cursorOffset
    return x + (off[1] or 0), y + (off[2] or 0)
end

function Library:Unload()
    if self._dead then return end
    self._dead = true
    self._gameOn = nil; self:_gameInput(true)
    for _, fn in ipairs(self._unloadFns) do pcall(fn) end
    self:_closePopup()
    for i = #self.Windows, 1, -1 do pcall(function() self.Windows[i]:Destroy() end) end
    for _, c in ipairs(self._conns) do pcall(function() c:Disconnect() end) end
    for _, ts in ipairs(self._toasts) do pcall(function() ts.hd:destroy() end) end
    if self._wm then self._wm:destroy() end
    if self._kl then self._kl:destroy() end
    for _, o in ipairs(self._objs) do pcall(function() o:Remove() end) end
    self._objs = {}
    if rawget(_G, "ZeroUI") == self then _G.ZeroUI = nil end
end

return Library
