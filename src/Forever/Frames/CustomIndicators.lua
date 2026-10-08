local _, ns = ...
local N = ns.N
local M = N.Media
local A = N.Auras
local Indicators = N.Indicators
local IsSecret = N.IsSecret

-- Custom indicators: the player builds their own from Options > Indicators > "+". Each watches a
-- list of spells (buffs or debuffs, optionally only the player's own) on every unit frame and
-- shows while one of them is present.
--
--   icon / icons  one aura icon (cooldown, stacks) / up to N icons
--   text          stacks, remaining time or fixed text
--   rect          a colored block (works like an icon)
--   color         a colored area (solid, gradient or class color)
--   bar           a small bar that runs down with the aura
--   glow          the whole frame glows (pixel, halo or pulse)
--   border        a colored frame border
--   overlay       a tint over the health bar
--
-- Entries live in N.db[group].customIndicators (a list). Matching needs the aura's spell ID: when
-- the game hides it nothing matches. With "only mine" the game itself limits the auras to the
-- player's.

local CI = {}
N.CustomIndicators = CI

CI.TYPES = { "icon", "icons", "text", "rect", "color", "bar", "border", "overlay", "glow" }
CI.GLOWS = { "pixel", "halo", "pulse" }

local ROW = { kind = "custom" }

local function newID()
    return ("%d%03d"):format(time(), math.random(0, 999))
end

function CI.NewEntry(kind, name)
    local e = {
        id = newID(), name = name, type = kind, enabled = true,
        aura = "buff", mine = true, spells = "",
        point = "TOPRIGHT", x = 0, y = 0, color = { 1.00, 0.80, 0.20 },
        size = 16, max = 3, spacing = 1, growth = "LEFT",
        showStacks = true, showCooldown = true, cdStyle = "spiral", showTime = false,
        timeSize = 10, timeX = 0, timeY = 0, stackSize = 10, stackX = 1, stackY = -1,
        textKind = "fixed", text = "{stacks}", fontSize = 12,
        width = 12, height = 12,
        thickness = 2, opacity = 0.35, around = "frame", -- border: "frame" | "health"
        -- glow: style (see CI.GLOWS), particles, speed (turns per second / pulses), length
        glow = "pixel", count = 8, speed = 0.3, length = 8, offset = 0,
        fill = "left", -- bar: the way it runs down: "left" | "right" | "down" | "up"
        colorMode = "solid", color2 = { 0.90, 0.25, 0.25 }, -- color: "solid" | "class" | "gradient-v" | "gradient-h"
        colorArea = "free", -- color: "free" | "frame" | "health" | "health-current" | "health-loss"
    }
    if kind == "bar" then e.width, e.height, e.point = 40, 5, "BOTTOM" end
    if kind == "rect" then e.point = "TOPLEFT" end
    if kind == "color" then e.width, e.height, e.point, e.opacity = 40, 12, "CENTER", 1 end
    return e
end

-- Suggestions for the options: healing buffs plus the defensive, external and offensive cooldown
-- lists, all classes (the options list the player's own class first). Debuffs have none.
function CI.Suggestions(aura)
    local out = {}
    if aura == "debuff" then return out end
    local seen = {}
    local function add(id)
        if not seen[id] and N.SpellClass and N.SpellClass[id] then seen[id] = true; out[#out + 1] = id end
    end
    for _, id in ipairs((N.SpellPool and N.SpellPool.buffs) or {}) do add(id) end
    local auras = N.Defaults and N.Defaults.party and N.Defaults.party.auras
    for _, row in ipairs({ "defensives", "externals", "offensives" }) do
        for tok in ((auras and auras[row] and auras[row].list) or ""):gmatch("%d+") do add(tonumber(tok)) end
    end
    return out
end
local setCache = {}
local function parseList(str)
    if not str or str == "" then return nil end
    local set = setCache[str]
    if not set then
        set = {}
        for tok in str:gmatch("%d+") do set[tonumber(tok)] = true end
        setCache[str] = set
    end
    return set
end

--------------------------------------------------------------------------------
-- Matching auras
--------------------------------------------------------------------------------

-- Spells that custom indicators with "remove from Buffs" claim for themselves:
-- the Buffs row skips them. Returns a set, or nil when there are none.
function CI.BuffExclusions(groupKey)
    local list = N.db[groupKey] and N.db[groupKey].customIndicators
    if not list then return nil end
    local out
    for _, e in ipairs(list) do
        if e.enabled and e.hideFromBuffs and e.aura == "buff" then
            local set = parseList(e.spells)
            if set then
                out = out or {}
                for id in pairs(set) do out[id] = true end
            end
        end
    end
    return out
end

local SAMPLE_ICONS = { 135953, 136041, 135987 }

local function collect(b, e, out)
    local want = (e.type == "icons") and (e.max or 3) or 1
    if b._mock then
        local now = GetTime()
        for i = 1, want do
            out[i] = { icon = SAMPLE_ICONS[(i - 1) % #SAMPLE_ICONS + 1], applications = 3,
                       duration = 20, expirationTime = now + 14 - i }
        end
        return
    end
    local set = parseList(e.spells)
    if not (set and b.unit and C_UnitAuras) then return end
    local base = (e.aura == "debuff") and "HARMFUL" or "HELPFUL"
    local filter = e.mine and (base .. "|PLAYER") or base
    for _, d in ipairs(N.AuraCache.Each(b.unit, filter)) do
        local id = d.spellId
        if id ~= nil and not IsSecret(id) and set[id] then
            out[#out + 1] = d
            if #out >= want then break end
        end
    end
end

--------------------------------------------------------------------------------
-- Widgets, one set per entry and unit button
--------------------------------------------------------------------------------

local function anchorOf(b, e, frame, extraX, extraY)
    local ax, ay = A.EdgeSign(e.point)
    frame:ClearAllPoints()
    frame:SetPoint(e.point, b, e.point, ax + (extraX or 0) + (e.x or 0), ay + (extraY or 0) + (e.y or 0))
end

local function rgb(e) local c = e.color or { 1, 1, 1 } return c[1], c[2], c[3] end

local builders = {}

-- icon / icons -----------------------------------------------------------------
builders.icon = function(b)
    local w = { icons = {} }
    function w.show(e, auras)
        local size, sp = e.size or 16, e.spacing or 1
        for i, d in ipairs(auras) do
            local ic = w.icons[i]
            if not ic then ic = A.MakeIcon(b.overlay); w.icons[i] = ic end
            ic:SetSize(size, size)
            local off = (i - 1) * (size + sp)
            local dx, dy = 0, 0
            if e.growth == "RIGHT" then dx = off elseif e.growth == "UP" then dy = off
            elseif e.growth == "DOWN" then dy = -off else dx = -off end
            anchorOf(b, e, ic, dx, dy)
            A.ApplyAura(ic, d, e, ROW, b.unit)
        end
        for i = #auras + 1, #w.icons do w.icons[i]:Hide() end
    end
    function w.hide() for _, ic in ipairs(w.icons) do ic:Hide() end end
    return w
end
builders.icons = builders.icon

-- text -------------------------------------------------------------------------
builders.text = function(b)
    local w = {}
    w.fs = N.FontString(b.overlay, 12)
    w.cd = CreateFrame("Cooldown", nil, b.overlay, "CooldownFrameTemplate")
    w.cd:SetDrawSwipe(false)
    w.cd:SetDrawEdge(false)
    w.cd:SetDrawBling(false)
    w.cd:SetHideCountdownNumbers(false)
    w.cd:SetFrameLevel(b.overlay:GetFrameLevel() + 3)
    w.ticker = CreateFrame("Frame", nil, b.overlay)

    function w.render()
        local d, tpl = w.aura, w.tpl
        if not (d and tpl) then return end
        local name = ""
        local sid = d.spellId
        if d.name and not IsSecret(d.name) then
            name = d.name
        elseif sid ~= nil and not IsSecret(sid) and C_Spell and C_Spell.GetSpellName then
            name = C_Spell.GetSpellName(sid) or ""
        end
        tpl = tpl:gsub("{name}", function() return name end)
        tpl = tpl:gsub("{time}", function()
            if d.expirationTime and not N.AnySecret(d.expirationTime, d.duration) and d.expirationTime > 0 then
                local left = math.max(0, d.expirationTime - GetTime())
                if left >= 60 then return ("%dm"):format(left / 60) end
                if left >= 10 then return ("%d"):format(left) end
                return ("%.1f"):format(left)
            end
            return ""
        end)
        local n = 0
        local fmt = tpl:gsub("%%", "%%%%"):gsub("{stacks}", function() n = n + 1; return "%d" end)
        if n == 0 then
            w.fs:SetText(tpl)
        else
            local c = d.applications
            if not IsSecret(c) and type(c) ~= "number" then c = 0 end
            local args = {}
            for i = 1, n do args[i] = c end
            w.fs:SetFormattedText(fmt, unpack(args))
        end
    end

    function w.show(e, auras)
        local d = auras[1]
        local r, g, bl = rgb(e)
        w.fs:SetFont(M.font, e.fontSize or 12, "OUTLINE")
        w.fs:SetTextColor(r, g, bl)
        w.fs:ClearAllPoints()
        anchorOf(b, e, w.fs)
        if e.textKind == "duration" then
            w.fs:Hide()
            w.cd:SetSize(60, 30)
            anchorOf(b, e, w.cd)
            if d.duration and not N.AnySecret(d.duration, d.expirationTime)
                and d.duration > 0 and d.expirationTime and d.expirationTime > 0 then
                w.cd:SetCooldown(d.expirationTime - d.duration, d.duration)
            elseif b.unit and d.auraInstanceID and w.cd.SetCooldownFromDurationObject then
                local ok, obj = pcall(C_UnitAuras.GetAuraDuration, b.unit, d.auraInstanceID)
                if ok and obj then w.cd:SetCooldownFromDurationObject(obj) end
            end
            if not w.cdFS then
                for _, reg in ipairs({ w.cd:GetRegions() }) do
                    if reg.GetObjectType and reg:GetObjectType() == "FontString" then w.cdFS = reg break end
                end
            end
            if w.cdFS then
                w.cdFS:SetFont(M.font, e.fontSize or 12, "OUTLINE")
                w.cdFS:SetTextColor(r, g, bl)
                w.cdFS:ClearAllPoints()
                w.cdFS:SetPoint("CENTER", w.cd, "CENTER")
            end
            w.cd:Show()
        else
            -- Own text with placeholders: {stacks} stack count, {time} remaining
            -- time, {name} spell name (older "stacks" entries are the text "{stacks}").
            w.cd:Hide()
            w.tpl = (e.textKind == "stacks") and "{stacks}" or (e.text or "")
            w.aura = d
            w.render()
            w.fs:Show()
            if w.tpl:find("{time}", 1, true) then
                local acc = 0
                w.ticker:SetScript("OnUpdate", function(_, dt)
                    acc = acc + dt
                    if acc >= 0.2 then acc = 0; w.render() end
                end)
            else
                w.ticker:SetScript("OnUpdate", nil)
            end
        end
    end
    function w.hide() w.fs:Hide(); w.cd:Hide(); w.ticker:SetScript("OnUpdate", nil) end
    return w
end

-- rect -------------------------------------------------------------------------
-- A block behaves like a spell icon, just filled with a color instead of the spell picture:
-- cooldown animation, remaining time and stacks all work.
builders.rect = function(b)
    local w = {}
    function w.show(e, auras)
        if not w.ic then w.ic = A.MakeIcon(b.overlay) end
        local ic = w.ic
        ic:SetSize(e.width or 12, e.height or 12)
        anchorOf(b, e, ic)
        A.ApplyAura(ic, auras[1], e, ROW, b.unit)
        ic.tex:SetTexture(M.flat)
        ic.tex:SetTexCoord(0, 1, 0, 1)
        ic.tex:SetVertexColor(rgb(e))
    end
    function w.hide() if w.ic then w.ic:Hide() end end
    return w
end

-- color ------------------------------------------------------------------------
-- A colored area: one color, the unit's class color, or a gradient of two.
-- Returns mode ("solid" | "gradient-v" | "gradient-h"), first color, second color.
function CI.ResolveColor(e, unit)
    local mode = e.colorMode or "solid"
    local c1 = e.color or { 1, 1, 1 }
    local c2 = e.color2 or c1
    if mode == "class" then
        local r, g, bl = 0.7, 0.7, 0.7
        if unit and UnitExists(unit) then
            local _, token = UnitClass(unit)
            if token and not IsSecret(token) then r, g, bl = N.ClassRGB(token) end
        end
        return "solid", { r, g, bl }, { r, g, bl }
    end
    if mode ~= "gradient-v" and mode ~= "gradient-h" then mode = "solid" end
    return mode, c1, c2
end

-- Fits a texture to an area of the frame: the whole frame, the health bar, its filled part
-- (current health) or its empty part (missing health).
function CI.AnchorArea(tex, b, area)
    tex:ClearAllPoints()
    local hb = b.health
    if area == "health" and hb then
        tex:SetAllPoints(hb)
    elseif (area == "health-current" or area == "health-loss") and hb and hb.GetStatusBarTexture then
        local ft = hb:GetStatusBarTexture()
        if area == "health-current" then
            tex:SetAllPoints(ft)
        else
            tex:SetPoint("TOPLEFT", ft, "TOPRIGHT")
            tex:SetPoint("BOTTOMRIGHT", hb, "BOTTOMRIGHT")
        end
    else
        tex:SetAllPoints(b)
    end
end

-- Paints a texture with the resolved colours (a solid colour is a flat gradient).
function CI.PaintFill(tex, mode, c1, c2)
    tex:SetTexture(M.flat)
    tex:SetVertexColor(1, 1, 1, 1)
    local a = CreateColor(c1[1], c1[2], c1[3], 1)
    local z = CreateColor(c2[1], c2[2], c2[3], 1)
    if mode == "gradient-v" then
        tex:SetGradient("VERTICAL", z, a) -- first colour on top
    elseif mode == "gradient-h" then
        tex:SetGradient("HORIZONTAL", a, z) -- first colour on the left
    else
        tex:SetGradient("HORIZONTAL", a, a)
    end
end

builders.color = function(b)
    local w = {}
    w.frame = CreateFrame("Frame", nil, b.overlay)
    w.frame:SetFrameLevel(b.overlay:GetFrameLevel() + 2)
    w.tex = w.frame:CreateTexture(nil, "ARTWORK")
    function w.show(e)
        if (e.colorArea or "free") == "free" then
            w.tex:ClearAllPoints()
            w.tex:SetAllPoints(w.frame)
            w.frame:SetSize(e.width or 40, e.height or 12)
            anchorOf(b, e, w.frame)
        else
            w.frame:ClearAllPoints()
            w.frame:SetAllPoints(b)
            CI.AnchorArea(w.tex, b, e.colorArea)
        end
        local mode, c1, c2 = CI.ResolveColor(e, b.unit)
        CI.PaintFill(w.tex, mode, c1, c2)
        w.tex:SetAlpha(e.opacity or 1)
        w.frame:Show()
    end
    function w.hide() w.frame:Hide() end
    return w
end

-- bar --------------------------------------------------------------------------
builders.bar = function(b)
    local w = {}
    w.frame = CreateFrame("Frame", nil, b.overlay)
    w.frame:SetFrameLevel(b.overlay:GetFrameLevel() + 2)
    w.bg = w.frame:CreateTexture(nil, "BACKGROUND")
    w.bg:SetAllPoints()
    w.bg:SetColorTexture(0, 0, 0, 0.55)
    w.bar = CreateFrame("StatusBar", nil, w.frame)
    w.bar:SetPoint("TOPLEFT", N.Snap(w.bar, 1), N.Snap(w.bar, -1))
    w.bar:SetPoint("BOTTOMRIGHT", N.Snap(w.bar, -1), N.Snap(w.bar, 1))
    w.bar:SetStatusBarTexture(M.flat)
    function w.show(e, auras)
        w.frame:SetSize(e.width or 40, e.height or 5)
        anchorOf(b, e, w.frame)
        w.bar:SetStatusBarColor(rgb(e))
        -- The bar shrinks towards its fixed edge: "left" = the free end runs from
        -- right to left, "right" = left to right, "down" = top to bottom, "up" = bottom to top.
        local f = e.fill or "left"
        w.bar:SetOrientation((f == "down" or f == "up") and "VERTICAL" or "HORIZONTAL")
        w.bar:SetReverseFill(f == "right" or f == "up")
        if not A.TimerBar(w.bar, auras[1], b.unit, true) then
            w.bar:SetMinMaxValues(0, 1)
            w.bar:SetValue(1)
        end
        w.frame:Show()
    end
    function w.hide() w.frame:Hide() end
    return w
end

-- border -----------------------------------------------------------------------
builders.border = function(b)
    local w = { edges = {} }
    for i = 1, 4 do
        local t = b.overlay:CreateTexture(nil, "ARTWORK", nil, 6)
        t:SetTexture(M.flat)
        w.edges[i] = t
    end
    function w.show(e)
        local th = N.Snap(b, e.thickness or 2)
        local t = (e.around == "health" and b.health) or b
        local top, bottom, left, right = w.edges[1], w.edges[2], w.edges[3], w.edges[4]
        for i = 1, 4 do w.edges[i]:SetVertexColor(rgb(e)); w.edges[i]:Show() end
        top:ClearAllPoints(); top:SetPoint("TOPLEFT", t, "TOPLEFT"); top:SetPoint("TOPRIGHT", t, "TOPRIGHT"); top:SetHeight(th)
        bottom:ClearAllPoints(); bottom:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT"); bottom:SetHeight(th)
        left:ClearAllPoints(); left:SetPoint("TOPLEFT", t, "TOPLEFT", 0, -th); left:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 0, th); left:SetWidth(th)
        right:ClearAllPoints(); right:SetPoint("TOPRIGHT", t, "TOPRIGHT", 0, -th); right:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", 0, th); right:SetWidth(th)
    end
    function w.hide() for _, t in ipairs(w.edges) do t:Hide() end end
    return w
end

-- overlay ----------------------------------------------------------------------
builders.overlay = function(b)
    local w = {}
    w.tex = b.overlay:CreateTexture(nil, "ARTWORK", nil, 4)
    w.tex:SetTexture(M.flat)
    function w.show(e)
        CI.AnchorArea(w.tex, b, e.colorArea or "health")
        local mode, c1, c2 = CI.ResolveColor(e, b.unit)
        CI.PaintFill(w.tex, mode, c1, c2)
        w.tex:SetAlpha(e.opacity or 0.35)
        w.tex:Show()
    end
    function w.hide() w.tex:Hide() end
    return w
end

-- glow -------------------------------------------------------------------------
-- A glow around the whole frame, drawn with plain textures and animations:
--   pixel  short lines running around the border
--   halo   a soft colored glow behind the frame, pulsing
--   pulse  a solid colored border that pulses
local PROC_ATLAS = "UI-HUD-ActionBar-Proc-Loop-Flipbook"

-- Position s (0..1, clockwise from the top-left corner) on a w x h rectangle:
-- returns x, y (from the top-left, downwards) and which edge it is on.
local function perimeter(width, height, s)
    local d = s * 2 * (width + height)
    if d < width then return d, 0, 1 end
    d = d - width
    if d < height then return width, d, 2 end
    d = d - height
    if d < width then return width - d, height, 3 end
    d = d - width
    return 0, height - d, 4
end

builders.glow = function(b)
    local w = {}
    w.frame = CreateFrame("Frame", nil, b)
    -- Above the bars, below the texts and icons (which live on b.overlay).
    w.frame:SetFrameLevel(math.max(0, b.overlay:GetFrameLevel() - 1))
    w.frame:SetAllPoints(b)
    w.frame:Hide()
    w.glow = N.AuraEngine.NewGlow(w.frame, b)

    function w.show(e)
        local r, g, bl = rgb(e)
        local style = e.glow or "pixel"
        local sig = table.concat({ style, r, g, bl, e.offset or 0, e.thickness or 2, e.speed or 0.3, e.length or 8,
            math.floor(b:GetWidth() or 0), math.floor(b:GetHeight() or 0) }, "|")
        -- Aura events call this often: a running glow is left alone.
        if w.sig == sig and w.frame:IsShown() then return end
        w.sig = sig
        w.frame:Show()
        w.glow:Show(style, r, g, bl, e.offset or 0, e.thickness or 2, e.speed or 0.3, e.length or 8)
    end
    function w.hide() w.sig = nil; w.glow:Hide(); w.frame:Hide() end
    return w
end
local function widgetFor(b, obj, e)
    local w = obj.items[e.id]
    if w and w.kind ~= e.type then
        w.hide()
        w = nil
    end
    if not w then
        w = builders[e.type](b)
        w.kind = e.type
        obj.items[e.id] = w
    end
    return w
end

--------------------------------------------------------------------------------
-- Indicator hook
--------------------------------------------------------------------------------

-- Engine path (Retail 12.1+): each entry is one aura container of the game's own
-- (Frames/AuraEngine.lua), so it keeps working in combat. Glows are not available there.
local function engineOn(b)
    return not b._mock and N.AuraEngine and N.AuraEngine.Supported()
end

local function engineSpec(b, e)
    if not e.enabled then return nil end
    if b._previewCustom and b._previewCustom ~= e.id then return nil end
    local set = parseList(e.spells)
    if not (set and next(set)) then return nil end
    local base = (e.aura == "debuff") and "HARMFUL" or "HELPFUL"
    local filter = e.mine and (base .. "|PLAYER") or base
    local appearance = N.db[b.groupKey].appearance
    local shape = (e.type == "icons" or e.type == "icon") and "icon" or e.type
    if e.type == "color" then shape = ((e.colorArea or "free") == "free") and "rect" or "overlay" end
    local max = (e.type == "icons") and (e.max or 3) or 1
    local spec = {
        shape = shape, point = e.point, x = e.x, y = e.y, growth = e.growth, spacing = e.spacing,
        size = e.size, max = max, width = e.width, height = e.height, color = e.color,
        thickness = e.thickness, opacity = e.opacity, around = e.around, fill = e.fill,
        cd = e.showCooldown and (e.cdStyle or "spiral") or "none",
        stacks = e.showStacks, time = e.showTime,
        timeSize = e.timeSize, timeX = e.timeX, timeY = e.timeY,
        stackSize = e.stackSize, stackX = e.stackX, stackY = e.stackY,
        timeColor = appearance and appearance.timeColor, fontSize = e.fontSize,
        glow = e.glow, offset = e.offset, speed = e.speed, length = e.length,
        isColor = (e.type == "color" or e.type == "overlay") or nil,
        groups = { { key = "ci", filter = filter, candidate = { includeSpellIDs = set }, max = max } },
    }
    if e.type == "color" or e.type == "overlay" then
        local mode, c1, c2 = CI.ResolveColor(e, b.unit)
        spec.colorMode, spec.color, spec.color2 = mode, c1, c2
        spec.colorArea = e.colorArea or (e.type == "overlay" and "health" or "free")
        spec.opacity = e.opacity or (e.type == "overlay" and 0.35 or 1)
        spec.cd, spec.stacks, spec.time = "none", false, false
    end
    if shape == "text" then
        if e.textKind == "duration" then spec.text = "{time}"
        elseif e.textKind == "stacks" then spec.text = "{stacks}"
        else spec.text = e.text or "" end
    end
    return spec
end

local function engineSync(b, obj)
    local E = N.AuraEngine
    obj.ids = obj.ids or {}
    local seen = {}
    for _, e in ipairs(N.db[b.groupKey].customIndicators or {}) do
        if builders[e.type] then
            seen[e.id] = true
            obj.ids[e.id] = true
            E.Apply(b, "ci:" .. e.id, engineSpec(b, e))
        end
    end
    for id in pairs(obj.ids) do
        if not seen[id] then E.Remove(b, "ci:" .. id); obj.ids[id] = nil end
    end
end

Indicators.Register("custom", {
    events = {}, -- redrawn by the aura cache (below) once it is current
    create = function(b)
        local obj = { items = {}, button = b }
        function obj:Hide()
            for _, w in pairs(self.items) do w.hide() end
            if self.ids and self.button then
                for id in pairs(self.ids) do N.AuraEngine.Remove(self.button, "ci:" .. id) end
            end
        end
        return obj
    end,
    update = function(b, obj)
        if engineOn(b) then
            engineSync(b, obj)
            return
        end
        local list = N.db[b.groupKey].customIndicators
        local seen = {}
        for _, e in ipairs(list or {}) do
            if builders[e.type] then
                seen[e.id] = true
                local w = widgetFor(b, obj, e)
                local auras = {}
                if (e.enabled or b._previewCustom == e.id) and (not b._previewCustom or b._previewCustom == e.id) then
                    collect(b, e, auras)
                end
                if #auras > 0 then w.show(e, auras) else w.hide() end
            end
        end
        for id, w in pairs(obj.items) do
            if not seen[id] then w.hide() end
        end
    end,
})

N:On("NUCLEUS_SETTING_CHANGED", function(_, _, path)
    if not (path and path:find("%.customIndicators")) then return end
    if N.UnitFrame then
        N.UnitFrame.ForEachButton(function(child)
            if child:IsShown() then Indicators.UpdateAll(child) end
        end)
    end
end)

N.AuraCache.OnChange(function(unit)
    if not (N.db and N.UnitFrame) then return end
    N.UnitFrame.ForEachButton(function(child)
        if child.unit == unit and child:IsShown() then Indicators.UpdateOne(child, "custom") end
    end)
end)
