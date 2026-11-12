local _, ns = ...
local N = ns.N
local M = N.Media
local L = N.L
local UnitExists, UnitIsUnit, UnitIsConnected, UnitIsDeadOrGhost = UnitExists, UnitIsUnit, UnitIsConnected, UnitIsDeadOrGhost

-- Unit frame visual layer shared by the group frames (real units) and test mode (mock data).

local UF = {}
N.UnitFrame = UF

local Abbrev = N.Abbreviate or _G.AbbreviateNumbers or function(v)
    if v >= 1e6 then return string.format("%.1fM", v / 1e6) end
    if v >= 1e3 then return string.format("%.0fK", v / 1e3) end
    return tostring(v)
end

-- Text templates: {p} percent, {v} value, {m} max, {d} deficit; one gsub pass keeps arguments in order.
local function applyCustomFormat(fs, tmpl, val, valMax, pct)
    local args = {}
    local spec = (tmpl or ""):gsub("%%", "%%%%")
    spec = spec:gsub("{(%a)}", function(tok)
        -- A token with a nil value is dropped: a "%d" without an argument would make SetFormattedText throw.
        if tok == "p" then
            if pct == nil then return "" end
            args[#args + 1] = pct
            return "%d%%"
        elseif tok == "v" then
            if val == nil then return "" end
            args[#args + 1] = val
            return "%d"
        elseif tok == "m" then
            if valMax == nil then return "" end
            args[#args + 1] = valMax
            return "%d"
        elseif tok == "d" then
            if N.IsSecret(val) or N.IsSecret(valMax) or not valMax then return "" end
            args[#args + 1] = valMax - val
            return "%d"
        end
        return "{" .. tok .. "}"
    end)
    fs:SetFormattedText(spec, unpack(args))
end

-- The first n characters of a UTF-8 string (a name), whole characters only.
local function limitChars(str, n)
    local i, count, len = 1, 0, #str
    while i <= len do
        local ch = str:byte(i)
        count = count + 1
        if count > n then return str:sub(1, i - 1) end
        i = i + ((ch >= 240 and 4) or (ch >= 224 and 3) or (ch >= 192 and 2) or 1)
    end
    return str
end

local UNIT_EVENTS = {
    "UNIT_HEALTH", "UNIT_MAXHEALTH",
    "UNIT_NAME_UPDATE", "UNIT_CONNECTION",
    "UNIT_THREAT_SITUATION_UPDATE",
}
-- Power events are registered only while the power bar or its text is shown.
local POWER_EVENTS = { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER" }


local function snap(frame, v)
    local PU = _G.PixelUtil
    if PU and PU.GetNearestPixelSize and frame and frame.GetEffectiveScale then
        local s = frame:GetEffectiveScale()
        if s and s > 0 then
            local r = PU.GetNearestPixelSize(math.abs(v), s, 1)
            return v < 0 and -r or r
        end
    end
    return v
end

function UF.CreateVisual(b, key)
    if b._nucVisual then return end
    b._nucVisual = true
    b.groupKey = key

    N.SkinPanel(b, M.color.frameBg)

    local health = CreateFrame("StatusBar", nil, b)
    health:SetPoint("TOPLEFT", snap(b, 1), snap(b, -1))
    N.SkinBar(health)
    b.health = health

    local power = CreateFrame("StatusBar", nil, b)
    power:SetPoint("BOTTOMLEFT", 1, 1)
    power:SetPoint("BOTTOMRIGHT", -1, 1)
    power:SetHeight(4)
    N.SkinBar(power)
    b.power = power

    local overlay = CreateFrame("Frame", nil, b)
    overlay:SetAllPoints(b)
    overlay:SetFrameLevel(math.max(health:GetFrameLevel(), power:GetFrameLevel()) + 4)
    b.overlay = overlay

    local top = CreateFrame("Frame", nil, b)
    top:SetAllPoints(b)
    top:SetFrameLevel(overlay:GetFrameLevel() + 50)
    b.topOverlay = top

    -- Target / mouseover outline textures; points and size are set in applyOutlineStyle / LayoutBars.
    local function makeOutline()
        local edges = {}
        for _ = 1, 4 do
            local t = overlay:CreateTexture(nil, "OVERLAY", nil, 1)
            t:SetTexture(M.flat)
            t:Hide()
            edges[#edges + 1] = t
        end
        return edges
    end
    b.targetEdges = makeOutline()
    b.hoverEdges = makeOutline()
    b.frameEdges = {}
    for i = 1, 4 do
        local t = overlay:CreateTexture(nil, "OVERLAY", nil, 0)
        t:SetTexture(M.flat)
        t:Hide()
        b.frameEdges[i] = t
    end

    local nameText = N.FontString(overlay, 11)
    nameText:SetJustifyH("CENTER")
    nameText:SetWordWrap(false)
    b.nameText = nameText

    local hpText = N.FontString(overlay, 10)
    hpText:SetJustifyH("CENTER")
    hpText:SetTextColor(0.85, 0.85, 0.87)
    b.hpText = hpText

    local powerText = N.FontString(overlay, 9)
    powerText:SetJustifyH("CENTER")
    powerText:Hide()
    b.powerText = powerText

    if N.Indicators then N.Indicators.Build(b) end
    if N.Auras then N.Auras.Create(b) end
    if N.Tooltip then N.Tooltip.Attach(b) end

    UF.LayoutBars(b)
end

-- Preview mask: button._previewOnly = <element name> hides everything else.
local function pShow(b, name)
    return (not b._previewOnly) or b._previewOnly == name
        or (b._previewOnly == "actions" and name == "name")
end

local function pOn(b, name, enabled)
    return enabled or b._previewOnly == name or (b._previewOnly == "actions" and name == "name")
end

local OUTLINES = { thin = "OUTLINE", thick = "THICKOUTLINE", none = "", shadow = "" }
function UF.Outline(o)
    return OUTLINES[o and o.outline or "thin"] or "OUTLINE"
end

-- "shadow": a drop shadow instead of an outline.
function UF.Shadow(fs, o)
    if o and o.outline == "shadow" then
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

local function styleText(fs, o, dim)
    fs:SetFont(M.font, o.size or 11, UF.Outline(o))
    UF.Shadow(fs, o)
    local c = (dim and M.color.textDim) or o.color or M.color.text
    fs:SetTextColor(c[1], c[2], c[3])
end

-- The bundled font lacks CJK glyphs: such names use a Blizzard font.
local function glyphFont(text)
    if type(text) ~= "string" or N.IsSecret(text) then return false end
    if text:find("[\234-\237]") then return "Fonts/2002.TTF" end
    if text:find("[\227-\233]") then return "Fonts/ARKai_T.ttf" end
    return false
end

local function setNameFont(b, o, text)
    local gf = glyphFont(text)
    if gf == b._nameGlyph then return end
    b._nameGlyph = gf
    local fs = b.nameText
    if not (gf and fs:SetFont(gf, o.size or 11, UF.Outline(o))) then
        b._nameGlyph = false
        fs:SetFont(M.font, o.size or 11, UF.Outline(o))
    end
    UF.Shadow(fs, o)
end

-- 9-point text placement: { point, justifyH, justifyV, inset x, inset y }.
local ANCHORS = {
    topleft     = { "TOPLEFT",     "LEFT",   "TOP",     2, -2 },
    top         = { "TOP",         "CENTER", "TOP",     0, -2 },
    topright    = { "TOPRIGHT",    "RIGHT",  "TOP",    -2, -2 },
    left        = { "LEFT",        "LEFT",   "MIDDLE",  2,  0 },
    center      = { "CENTER",      "CENTER", "MIDDLE",  0,  0 },
    right       = { "RIGHT",       "RIGHT",  "MIDDLE", -2,  0 },
    bottomleft  = { "BOTTOMLEFT",  "LEFT",   "BOTTOM",  2,  2 },
    bottom      = { "BOTTOM",      "CENTER", "BOTTOM",  0,  2 },
    bottomright = { "BOTTOMRIGHT", "RIGHT",  "BOTTOM", -2,  2 },
}
UF.TEXT_POSITIONS = { "topleft", "top", "topright", "left", "center", "right",
                      "bottomleft", "bottom", "bottomright" }

-- o = the indicator's settings; dy = shift when name and health text share the middle.
local function placeText(fs, host, o, dy)
    local a = ANCHORS[o.position or "center"] or ANCHORS.center
    fs:ClearAllPoints()
    fs:SetPoint(a[1], host, a[1], a[4] + (o.x or 0), a[5] + (o.y or 0) + (dy or 0))
    fs:SetJustifyH(a[2])
    fs:SetJustifyV(a[3])
    -- A new justification only shows once the text is laid out again, and an unchanged text is not.
    local just = a[2] .. a[3]
    if fs._nucJust ~= just then
        fs._nucJust = just
        local ok, text = pcall(fs.GetText, fs)
        fs:SetText("")
        if ok and text ~= nil then pcall(fs.SetText, fs, text) end
    end
end

UF.PlaceText = placeText

-- Outline edges in TOP / BOTTOM / LEFT / RIGHT order, growing outward; TOP / BOTTOM take the corners.
local MARGIN = 0
local function applyOutlineStyle(edges, cfg)
    local c = cfg.color or { 1, 1, 1 }
    local th = snap(edges[1]:GetParent(), cfg.thickness or 1)
    local top, bottom, left, right = edges[1], edges[2], edges[3], edges[4]
    local reach = MARGIN + th

    for i = 1, 4 do edges[i]:SetColorTexture(c[1], c[2], c[3], 1) end

    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", top:GetParent(), "TOPLEFT", -reach, reach)
    top:SetPoint("TOPRIGHT", top:GetParent(), "TOPRIGHT", reach, reach)
    top:SetHeight(th)

    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", bottom:GetParent(), "BOTTOMLEFT", -reach, -reach)
    bottom:SetPoint("BOTTOMRIGHT", bottom:GetParent(), "BOTTOMRIGHT", reach, -reach)
    bottom:SetHeight(th)

    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", left:GetParent(), "TOPLEFT", -reach, MARGIN)
    left:SetPoint("BOTTOMLEFT", left:GetParent(), "BOTTOMLEFT", -reach, -MARGIN)
    left:SetWidth(th)

    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", right:GetParent(), "TOPRIGHT", reach, MARGIN)
    right:SetPoint("BOTTOMRIGHT", right:GetParent(), "BOTTOMRIGHT", reach, -MARGIN)
    right:SetWidth(th)
end

local function applyFrameBorder(b, cfg)
    cfg = cfg or { enabled = true, thickness = 1, color = { 0, 0, 0 } }
    local on = cfg.enabled ~= false
    local c = cfg.color or { 0, 0, 0 }
    local th = snap(b, cfg.thickness or 1)
    local top, bottom, left, right = b.frameEdges[1], b.frameEdges[2], b.frameEdges[3], b.frameEdges[4]
    for i = 1, 4 do
        b.frameEdges[i]:SetColorTexture(c[1], c[2], c[3], 1)
        b.frameEdges[i]:SetShown(on)
    end
    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    top:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
    top:SetHeight(th)
    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    bottom:SetHeight(th)
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -th)
    left:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, th)
    left:SetWidth(th)
    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, -th)
    right:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, th)
    right:SetWidth(th)
    N.SetPanelBorder(b, { 0, 0, 0, 0 })
end

-- Whether this unit's role may show a power bar; unknown / secret roles are allowed.
function UF.PowerAllowed(b)
    -- No roles here: the power bar is switched on or off per class.
    local pb = N.db[b.groupKey].indicators.powerBar
    local class = b.class
    if class == nil or N.IsSecret(class) then return true end
    local byClass = pb.filter and pb.filter[class]
    return not (byClass and byClass.ALL == false)
end

-- Height the shown power bar takes at the bottom: icons on a bottom point sit above it.
function N.PowerInset(b)
    local pb = b.power
    if not (pb and pb:IsShown()) then return 0 end
    local o = N.db[b.groupKey].indicators.powerBar
    if o.position == "top" or o.position == "left" or o.position == "right" then return 0 end
    return (o.height or 4) + (o.y or 0)
end

-- Registers or drops the power events as the power bar / power text appears and disappears.
local function syncPowerEvents(b)
    local unit = b.unit
    if not unit then return end
    local pb = N.db[b.groupKey].indicators.powerBar
    local want = (pb.enabled and b._powerShown) and true or false
    if b._powerEvents == want then return end
    b._powerEvents = want
    for _, ev in ipairs(POWER_EVENTS) do
        if want then N.SafeRegisterUnit(b, ev, unit) else b:UnregisterEvent(ev) end
    end
end

function UF.LayoutBars(b)
    local ind = N.db[b.groupKey].indicators
    local appearance = N.db[b.groupKey].appearance
    local pb = ind.powerBar
    b._powerShown = UF.PowerAllowed(b)
    local ph = (pOn(b, "powerBar", pb.enabled) and b._powerShown and (pb.height or 4)) or 0

    -- Changing the texture resets the tint, so SetStatusBarColor is re-applied by the next render().
    N.SetBarTexture(b.health, appearance.barTexture)
    N.SetBarTexture(b.power, appearance.barTexture)
    N.SetBarLossColor(b.health, appearance.healthLossColor)
    N.SetBarLossColor(b.power, appearance.healthLossColor)

    applyOutlineStyle(b.targetEdges, appearance.targetBorder)
    applyOutlineStyle(b.hoverEdges, appearance.hoverBorder)
    applyFrameBorder(b, appearance.frameBorder)

    b.power:SetShown(pOn(b, "powerBar", pb.enabled) and b._powerShown and pShow(b, "powerBar"))
    -- The bar sits along one edge; left and right make it vertical. Health gives up the strip it takes.
    local pos = pb.position
    if pos ~= "top" and pos ~= "left" and pos ~= "right" then pos = "bottom" end
    local thick, ox, oy = pb.height or 4, pb.x or 0, pb.y or 0
    b.power:ClearAllPoints()
    if pos == "left" or pos == "right" then
        local side = (pos == "left") and "LEFT" or "RIGHT"
        local sx = (pos == "left") and snap(b, 1) or snap(b, -1)
        b.power:SetOrientation("VERTICAL")
        b.power:SetHeight(0)
        b.power:SetWidth(thick)
        b.power:SetPoint("TOP" .. side, b, "TOP" .. side, sx + ox, snap(b, -1) + oy)
        b.power:SetPoint("BOTTOM" .. side, b, "BOTTOM" .. side, sx + ox, snap(b, 1) + oy)
    else
        local edge = (pos == "top") and "TOP" or "BOTTOM"
        local sy = (pos == "top") and snap(b, -1) or snap(b, 1)
        b.power:SetOrientation("HORIZONTAL")
        b.power:SetWidth(0)
        b.power:SetHeight(thick)
        b.power:SetPoint(edge .. "LEFT", b, edge .. "LEFT", snap(b, 1) + ox, sy + oy)
        b.power:SetPoint(edge .. "RIGHT", b, edge .. "RIGHT", snap(b, -1) + ox, sy + oy)
    end
    local gap = (ph > 0) and (ph + 1) or 0
    b.health:SetPoint("TOPLEFT", b, "TOPLEFT",
        snap(b, pos == "left" and 1 + gap or 1), snap(b, pos == "top" and -(1 + gap) or -1))
    b.health:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT",
        snap(b, pos == "right" and -(1 + gap) or -1), snap(b, pos == "bottom" and 1 + gap or 1))

    -- Explicit width from the frame width so long names truncate; one anchor lets X / Y move the text.
    local textW = N.db[b.groupKey].width - 6
    local name, hp = ind.name, ind.healthText
    styleText(b.nameText, name)
    b._nameGlyph = nil
    setNameFont(b, name, b.nameText:GetText())
    styleText(b.hpText, hp)
    b.nameText:SetWidth(textW)
    b.hpText:SetWidth(textW)
    local stacked = pOn(b, "name", name.enabled) and pOn(b, "healthText", hp.enabled)
        and (name.position or "center") == "center" and (hp.position or "center") == "center"
    placeText(b.nameText, b.health, name, stacked and 6 or 0)
    placeText(b.hpText, b.health, hp, stacked and -6 or 0)

    b.powerText:SetFont(M.font, pb.textSize or 9, "OUTLINE")
    b.powerText:SetWidth(0)
    placeText(b.powerText, b.health, { position = pb.textPosition, x = pb.textX, y = pb.textY })
    b.powerText:SetShown(pOn(b, "powerBar", pb.enabled) and b._powerShown and pb.text and pShow(b, "powerBar"))
    syncPowerEvents(b)

    if N.Auras then N.Auras.Layout(b) end
end


local IsSecret, AnySecret = N.IsSecret, N.AnySecret

local function desecret(v, fallback)
    if IsSecret(v) then return fallback end
    if v == nil then return fallback end
    return v
end

-- Every styled button, and the buttons by the unit they show: the indicator events look them up here.
local allButtons, byUnit = {}, {}
local unitWatchers = {}
local function mapUnit(b, old, new)
    local set = old and byUnit[old]
    if set then
        set[b] = nil
        if not next(set) then
            byUnit[old] = nil
            for i = 1, #unitWatchers do unitWatchers[i][2](old) end
        end
    end
    if new then
        set = byUnit[new]
        if not set then
            set = {}
            byUnit[new] = set
            for i = 1, #unitWatchers do unitWatchers[i][1](new) end
        end
        set[b] = true
    end
end

-- onNew(unit) on a unit's first frame (also existing ones), onGone(unit) on its last; events only for these.
function UF.WatchUnits(onNew, onGone)
    unitWatchers[#unitWatchers + 1] = { onNew, onGone }
    for unit in pairs(byUnit) do onNew(unit) end
end
function UF.AllButtons() return allButtons end
function UF.ButtonsOfUnit(unit) return byUnit[unit] end

local function readUnit(b)
    local u = b.unit
    b.connected = desecret(UnitIsConnected(u), true)
    b.dead = desecret(UnitIsDeadOrGhost(u), false)
    b.hp, b.hpMax = UnitHealth(u) or 0, UnitHealthMax(u) or 1
    b.class = select(2, UnitClass(u))
    b.pName = desecret(UnitName(u), "")
    b.pp, b.ppMax = UnitPower(u), UnitPowerMax(u)
    b.ppEnum, b.ppType = UnitPowerType(u) -- numeric type (for UnitPowerPercent), token (for colours)
    b.aggroStatus = desecret(UnitThreatSituation(u), 0)
    local tgt = UnitExists("target") and UnitIsUnit(u, "target")
    b.isTarget = (not IsSecret(tgt)) and tgt == true
end


-- The gradient does arithmetic only on N.HealthFraction (nil when unknown).
local function healthColor(b, appearance)
    if b.dead and appearance.deadColorEnabled then
        local d = appearance.deadColor
        if d then return d[1], d[2], d[3] end
    end
    local mode = appearance.healthColorMode
    if mode == "custom" then
        local c = appearance.healthCustomColor
        return c[1], c[2], c[3]
    elseif mode == "gradient" then
        local frac = b.unit and N.HealthFraction(b.unit)
        if not frac and not AnySecret(b.hp, b.hpMax) and b.hpMax and b.hpMax > 0 then
            frac = b.hp / b.hpMax
        end
        if frac then
            frac = math.max(0, math.min(1, frac))
            if frac < 0.5 then
                return 1, frac * 2, 0
            else
                return 1 - (frac - 0.5) * 2, 1, 0
            end
        end
    end
    return N.ClassRGB(b.class)
end

local function textRGB(b, o, fallback)
    if o.colorMode == "class" then return N.ClassRGB(b.class) end
    local c = o.color or fallback
    return c[1], c[2], c[3]
end

-- AbbreviateNumbers takes secrets; the result only goes into a FontString.
local function shortNum(v)
    if v == nil then return nil end
    local ok, s = pcall(Abbrev, v)
    if ok then return s end
    return nil
end

local function hpPercent(b)
    local pct
    if b.unit then pct = N.HealthPercent(b.unit) end
    if pct == nil and not AnySecret(b.hp, b.hpMax) and b.hp and b.hpMax and b.hpMax > 0 then
        pct = b.hp / b.hpMax * 100
    end
    return pct
end

-- Missing health as "-12.3K"; TruncateWhenZero blanks zero even when secret.
local function setDeficitText(b, fs)
    local missing
    if _G.UnitHealthMissing and b.unit then missing = UnitHealthMissing(b.unit, true) end
    if missing == nil and not AnySecret(b.hp, b.hpMax) and b.hp and b.hpMax then
        missing = b.hpMax - b.hp
    end
    if missing == nil then fs:SetText(""); return end
    if not IsSecret(missing) then
        local s = missing > 0 and shortNum(missing) or nil
        fs:SetText(s and ("-" .. s) or "")
        return
    end
    local trunc = _G.C_StringUtil and C_StringUtil.TruncateWhenZero
    if trunc then
        fs:SetText(trunc(missing))
        local t = fs:GetText()
        if not t or (not IsSecret(t) and t == "") then return end
    end
    local s = shortNum(missing)
    if s then fs:SetFormattedText("-%s", s) else fs:SetText("") end
end

-- Blank the text at 100%; with hidden health a curve the game evaluates drives the text alpha instead.
local fullCurve
local function fullHealthCurve()
    if fullCurve == nil then
        fullCurve = false
        if C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor then
            local cv = C_CurveUtil.CreateColorCurve()
            cv:AddPoint(0, CreateColor(1, 1, 1, 1))
            cv:AddPoint(0.999, CreateColor(1, 1, 1, 1))
            cv:AddPoint(1, CreateColor(1, 1, 1, 0))
            fullCurve = cv
        end
    end
    return fullCurve or nil
end

local function hideWhenFull(b, fs, o)
    if not o.hideAtFull then
        fs:SetAlpha(1)
        return false
    end
    local frac = b.unit and N.HealthFraction(b.unit)
    if frac then
        fs:SetAlpha(1)
        if frac >= 1 then fs:SetText(""); return true end
        return false
    end
    local curve = fullHealthCurve()
    if curve and b.unit and b.healCalc and _G.UnitGetDetailedHealPrediction then
        local ok, a = pcall(function()
            UnitGetDetailedHealPrediction(b.unit, nil, b.healCalc)
            local _, _, _, al = b.healCalc:EvaluateCurrentHealthPercent(curve):GetRGBA()
            return al
        end)
        if ok and a ~= nil then
            fs:SetAlpha(a)
            return false
        end
    end
    fs:SetAlpha(1)
    return false
end

-- All health-text formats; secret numbers can't be read but can be formatted into a FontString.
local function setHealthText(b, fs, o)
    if hideWhenFull(b, fs, o) then return end
    local mode = o.format or "percent"
    if mode == "custom" then
        applyCustomFormat(fs, o.customFormat, b.hp, b.hpMax, hpPercent(b))
        return
    end
    if mode == "deficit" then
        setDeficitText(b, fs)
        return
    end
    local pct = hpPercent(b)
    local cur = shortNum(b.hp)
    if mode == "value" then
        if cur ~= nil then fs:SetText(cur) else fs:SetText("") end
    elseif mode == "valuePercent" and cur ~= nil and pct ~= nil then
        fs:SetFormattedText("%s | %d%%", cur, pct)
    elseif mode == "percentValue" and cur ~= nil and pct ~= nil then
        fs:SetFormattedText("%d%% | %s", pct, cur)
    elseif mode == "percentNoSign" and pct ~= nil then
        fs:SetFormattedText("%d", pct)
    elseif pct ~= nil then
        fs:SetFormattedText("%d%%", pct)
    else
        fs:SetText("")
    end
end

local function powerPercent(b)
    if b.unit and b.ppEnum and _G.UnitPowerPercent then
        local scale = _G.CurveConstants and CurveConstants.ScaleTo100
        local ok, pct = pcall(UnitPowerPercent, b.unit, b.ppEnum, true, scale)
        if ok and pct ~= nil then return pct end
    end
    if not AnySecret(b.pp, b.ppMax) and b.pp and b.ppMax and b.ppMax > 0 then
        return b.pp / b.ppMax * 100
    end
    return nil
end

-- Power type color: Blizzard's PowerBarColor, with fallbacks so no class ends up on the wrong color.
local POWER_FALLBACK = {
    MANA = { 0.00, 0.00, 1.00 }, RAGE = { 1.00, 0.00, 0.00 }, FOCUS = { 0.867, 0.573, 0.216 },
    ENERGY = { 1.00, 0.96, 0.41 }, COMBO_POINTS = { 1.00, 0.96, 0.41 }, RUNES = { 0.50, 0.50, 0.50 },
    RUNIC_POWER = { 0.00, 0.82, 1.00 }, SOUL_SHARDS = { 0.50, 0.32, 0.55 },
    LUNAR_POWER = { 0.30, 0.52, 0.90 }, HOLY_POWER = { 0.95, 0.90, 0.60 },
    MAELSTROM = { 0.00, 0.50, 1.00 }, INSANITY = { 0.40, 0.00, 0.80 }, CHI = { 0.71, 1.00, 0.92 },
    ARCANE_CHARGES = { 0.10, 0.10, 0.98 }, FURY = { 0.788, 0.259, 0.992 }, PAIN = { 1.00, 0.61, 0.00 },
    ESSENCE = { 0.20, 0.58, 0.50 },
}
local function powerRGB(b)
    local t = b.ppType
    if type(t) == "string" and not N.IsSecret(t) then
        local fb = POWER_FALLBACK[t]
        if fb then return fb[1], fb[2], fb[3] end
        local pc = PowerBarColor[t]
        if pc then return pc.r, pc.g, pc.b end
    end
    local e = b.ppEnum
    if type(e) == "number" and not N.IsSecret(e) then
        local pc = PowerBarColor[e]
        if pc then return pc.r, pc.g, pc.b end
    end
    local pc = PowerBarColor[t or 0] or PowerBarColor[0]
    if pc then return pc.r, pc.g, pc.b end
    return 0, 0, 1
end

local function powerTextRGB(b, o)
    local mode = o.textColorMode or "power"
    if mode == "class" then return N.ClassRGB(b.class) end
    if mode == "custom" then
        local c = o.textColor or { 1, 1, 1 }
        return c[1], c[2], c[3]
    end
    return powerRGB(b)
end

local function setPowerText(b, fs, o)
    if not b.connected or b.dead then fs:SetText(""); return end
    local mode = o.textFormat or "percent"
    local pct = powerPercent(b)
    if mode == "custom" then
        applyCustomFormat(fs, o.customFormat, b.pp, b.ppMax, pct)
    else
        local cur = shortNum(b.pp)
        if mode == "value" and cur ~= nil then
            fs:SetText(cur)
        elseif mode == "valuePercent" and cur ~= nil and pct ~= nil then
            fs:SetFormattedText("%s | %d%%", cur, pct)
        elseif mode == "percentValue" and cur ~= nil and pct ~= nil then
            fs:SetFormattedText("%d%% | %s", pct, cur)
        elseif mode == "percentNoSign" and pct ~= nil then
            fs:SetFormattedText("%d", pct)
        elseif pct ~= nil then
            fs:SetFormattedText("%d%%", pct)
        else
            fs:SetText("")
        end
    end
    fs:SetTextColor(powerTextRGB(b, o))
end

local function powerBarRGB(b, o)
    local mode = o and o.barColorMode or "power"
    if mode == "class" then return N.ClassRGB(b.class) end
    if mode == "custom" then
        local tok = b.ppType
        local own = o.barColors and type(tok) == "string" and not N.IsSecret(tok) and o.barColors[tok]
        local c = own or o.barColor or { 0.2, 0.4, 1 }
        return c[1], c[2], c[3]
    end
    return powerRGB(b)
end

local function renderPower(b, ind)
    if b.power:IsShown() then
        -- A unit that does not exist (Spotlight target without a target) reports no power at all.
        b.power:SetMinMaxValues(0, type(b.ppMax) == "number" and b.ppMax or 1)
        if b.connected and type(b.pp) == "number" then b.power:SetValue(b.pp) else b.power:SetValue(0) end
        b.power:SetStatusBarColor(powerBarRGB(b, ind.powerBar))
    end

    if b.powerText:IsShown() then
        setPowerText(b, b.powerText, ind.powerBar)
    end
end

local function render(b)
    local appearance = N.db[b.groupKey].appearance

    b.hpMax = b.hpMax or 1; b.hp = b.hp or 0
    b.health:SetMinMaxValues(0, b.hpMax)
    if b.connected then b.health:SetValue(b.hp) else b.health:SetValue(0) end
    b.health:SetStatusBarColor(healthColor(b, appearance))

    local ind = N.db[b.groupKey].indicators

    -- The power bar's visibility is re-checked on every paint instead of waiting for the next layout pass.
    local wantPower = pOn(b, "powerBar", ind.powerBar.enabled) and b._powerShown and pShow(b, "powerBar")
    if (wantPower and true or false) ~= (b.power:IsShown() and true or false) then UF.LayoutBars(b) end

    local statusMsg = nil

    b.nameText:SetShown(pOn(b, "name", ind.name.enabled) and not statusMsg and pShow(b, "name"))
    if pOn(b, "name", ind.name.enabled) and not statusMsg then
        local shown = N.Translit(b.pName) or ""
        local maxChars = ind.name.maxChars
        if type(shown) == "string" and type(maxChars) == "number" and maxChars > 0 then
            shown = limitChars(shown, maxChars)
        end
        b.nameText:SetText(shown)
        setNameFont(b, ind.name, shown)
        if (not b.connected) or b.dead then
            b.nameText:SetTextColor(M.color.textDim[1], M.color.textDim[2], M.color.textDim[3])
        else
            b.nameText:SetTextColor(textRGB(b, ind.name, { 0.92, 0.92, 0.94 }))
        end
    end

    b.hpText:SetShown(pOn(b, "healthText", ind.healthText.enabled) and not statusMsg and pShow(b, "healthText"))
    if pOn(b, "healthText", ind.healthText.enabled) and not statusMsg then
        setHealthText(b, b.hpText, ind.healthText)
        b.hpText:SetTextColor(textRGB(b, ind.healthText, { 0.85, 0.85, 0.87 }))
    end

    renderPower(b, ind)

    for i = 1, #b.targetEdges do b.targetEdges[i]:SetShown(b.isTarget and not b._previewOnly) end

    if N.Indicators then N.Indicators.UpdateAll(b) end
    if N.Auras then N.Auras.Update(b) end
end
UF.Render = render

local function fullUpdate(b)
    if not b.unit or not UnitExists(b.unit) then return end
    readUnit(b)
    -- The power bar can be limited to roles, and a role can change or become known after layout.
    if b._powerShown ~= UF.PowerAllowed(b) then UF.LayoutBars(b) end
    render(b)
end
UF.FullUpdate = fullUpdate

function UF.ApplyMock(b, m)
    b._mock = m
    mapUnit(b, b.unit, nil)
    b.unit = nil
    b.connected = m.connected ~= false
    b.dead = m.dead or false
    b.hpMax = m.hpMax or 100
    b.hp = m.hp or b.hpMax
    b.class = m.class
    b.pName = m.name
    b.ppMax = m.ppMax or 100
    b.pp = m.pp or 0
    b.ppType = m.ppType or 0
    b.aggroStatus = m.aggro and 3 or 0
    b.isTarget = m.isTarget or false
    if b._powerShown ~= UF.PowerAllowed(b) then UF.LayoutBars(b) end
    render(b)
end


local function bindUnit(b)
    local unit = (b._secure or b):GetAttribute("unit")
    if unit == b.unit then return end
    mapUnit(b, b.unit, unit)
    b.unit = unit
    b:UnregisterAllEvents()
    b._powerEvents = nil
    if unit then
        for _, ev in ipairs(UNIT_EVENTS) do
            N.SafeRegisterUnit(b, ev, unit)
        end
        fullUpdate(b)
        syncPowerEvents(b)
        -- Bar widths resolve a frame after anchoring: lay out again once they have.
        C_Timer.After(0, function()
            if b.unit == unit then
                UF.LayoutBars(b)
                render(b)
            end
        end)
    end
end

-- Unit events are collected per button and handled once next frame.
local function refreshPower(b)
    local u = b.unit
    b.pp, b.ppMax = UnitPower(u), UnitPowerMax(u)
    renderPower(b, N.db[b.groupKey].indicators)
end

local FAST_EVENTS = {
    UNIT_POWER_UPDATE = { "power", refreshPower },
}
local dirty, flushQueued = {}, false

local function flushDirty()
    flushQueued = false
    for b, d in pairs(dirty) do
        dirty[b] = nil
        if b.unit and UnitExists(b.unit) then
            if d.full then
                fullUpdate(b)
            else
                for _, fn in pairs(d) do fn(b) end
            end
        end
    end
end

local function onEvent(b, event)
    local d = dirty[b]
    if not d then d = {}; dirty[b] = d end
    local fast = FAST_EVENTS[event]
    if fast then
        if not d.full then d[fast[1]] = fast[2] end
    else
        d.full = true
    end
    if not flushQueued then
        flushQueued = true
        C_Timer.After(0, flushDirty)
    end
end

local function updateRange(b)
    if not b.unit or not UnitExists(b.unit) then return end

    local appearance = N.db[b.groupKey].appearance

    -- UnitInRange can return a secret boolean; SetAlphaFromBoolean takes it directly.
    local alpha = 1
    -- Only the first return is used; the second can be missing and would keep every frame at full alpha.
    local inRange
    local me = UnitIsUnit(b.unit, "player")
    if me ~= nil and not N.IsSecret(me) and not me then me = UnitIsUnit(b.unit, "pet") end
    if me == nil or N.IsSecret(me) or not me then
        local checked
        inRange, checked = UnitInRange(b.unit)
        -- Pets and units outside the group (target, focus): UnitInRange says false for an unchecked range, so
        -- fade only after a real check.
        local u = b.unit
        local outside = u:find("pet") or not (u:find("^party%d") or u:find("^raid%d"))
        if outside and not (checked ~= nil and not N.IsSecret(checked) and checked) then
            inRange = nil
        end
    end
    if inRange ~= nil and N.IsSecret(inRange) and b.SetAlphaFromBoolean then
        b.curAlpha = nil
        b:SetAlphaFromBoolean(inRange, 1, appearance.outOfRangeAlpha)
        return
    end
    if inRange == false then
        alpha = appearance.outOfRangeAlpha
    elseif appearance.healthFade.enabled then
        -- HealthFraction is nil when the value isn't safely known: the fade then just stays off.
        local frac = N.HealthFraction(b.unit)
        if frac and frac >= (appearance.healthFade.threshold or 1) then
            alpha = appearance.outOfRangeAlpha
        end
    end
    b.curAlpha = alpha
    b:SetAlpha(alpha)
end

-- UNIT_IN_RANGE_UPDATE names the unit; one slow timer covers the rest (fade, dead units, pets, new frames).
local rangeFrame = CreateFrame("Frame")
N.SafeRegister(rangeFrame, "UNIT_IN_RANGE_UPDATE")
rangeFrame:SetScript("OnEvent", function(_, _, unit)
    local set = unit and UF.ButtonsOfUnit(unit)
    if not set then return end
    for b in pairs(set) do
        if b:IsShown() then updateRange(b) end
    end
end)
local rangeElapsed = 0
rangeFrame:SetScript("OnUpdate", function(_, dt)
    rangeElapsed = rangeElapsed + dt
    if rangeElapsed < math.max(N.db.core.rangeUpdateInterval or 0.5, 0.5) then return end
    rangeElapsed = 0
    local all = UF.AllButtons()
    for n = 1, #all do
        local b = all[n]
        if b:IsShown() then updateRange(b) end
    end
end)

-- Run inside the header's secure update: our reaction is queued, so none of our code runs there.
local pendingBind, bindScheduled = {}, false
local function flushBinds()
    bindScheduled = false
    for b, w in pairs(pendingBind) do
        pendingBind[b] = nil
        if w.bind then bindUnit(b) end
        if w.full and b:IsShown() then fullUpdate(b); updateRange(b) end
    end
end
local function queueBind(b, what)
    local w = pendingBind[b]
    if not w then w = {}; pendingBind[b] = w end
    w[what] = true
    if not bindScheduled then
        bindScheduled = true
        C_Timer.After(0, flushBinds)
    end
end

-- Header children are Blizzard's: nothing of ours goes into their tables; we draw on a "visual" frame inside.
local visualOf = setmetatable({}, { __mode = "k" })
local plainStyled = setmetatable({}, { __mode = "k" })

function UF.VisualOf(child) return visualOf[child] end
-- The Nucleus button (visual) behind a secure button, nil if it is not styled yet.
function UF.ButtonOf(child) return visualOf[child] or (plainStyled[child] and child) or nil end
function UF.BindChild(child)
    local v = UF.ButtonOf(child)
    if v then bindUnit(v) end
end

local function isHeaderChild(child)
    local p = child:GetParent()
    return p ~= nil and N.headers ~= nil
        and (p == N.headers.party or p == N.headers.raid or p == N.headers.groupPets or N.HeaderHolder(p) ~= nil)
end

function N.StyleUnitButton(name)
    local child = _G[name]
    if not child or visualOf[child] or plainStyled[child] then return end

    local parent = child:GetParent()
    local key = (parent and N.HeaderKey(parent)) or "party"
    local b = child
    if isHeaderChild(child) then
        b = CreateFrame("Frame", nil, child)
        b:SetAllPoints(child)
        b:EnableMouse(false)
        b._secure = child
        visualOf[child] = b
        b:SetShown(child:IsShown())
    else
        plainStyled[child] = true
    end
    UF.CreateVisual(b, key)
    allButtons[#allButtons + 1] = b

    -- A plain Button only knows the left button; without this right / middle clicks never fire.
    child:RegisterForClicks("AnyUp")

    child:HookScript("OnAttributeChanged", function(_, attr)
        if attr == "unit" then queueBind(b, "bind") end
    end)
    child:HookScript("OnShow", function()
        if b ~= child then b:Show() end
        queueBind(b, "full")
    end)
    if b ~= child then child:HookScript("OnHide", function() b:Hide() end) end
    child:HookScript("OnEnter", function()
        if not b.isTarget then
            for i = 1, #b.hoverEdges do b.hoverEdges[i]:Show() end
        end
    end)
    child:HookScript("OnLeave", function()
        for i = 1, #b.hoverEdges do b.hoverEdges[i]:Hide() end
    end)
    b:SetScript("OnEvent", onEvent)

    bindUnit(b)
end

local function forEachButton(fn)
    for _, header in pairs(N.headers or {}) do
        local i, child = 1, _G[header:GetName() .. "UnitButton1"]
        while child do
            local b = UF.ButtonOf(child)
            if b and b._nucVisual then fn(b, header) end
            i = i + 1
            child = _G[header:GetName() .. "UnitButton" .. i]
        end
    end
end
UF.ForEachButton = forEachButton

-- A button keeps its token when the person behind it changes: compare the GUID, outside the header update.
local rosterWatch = CreateFrame("Frame")
rosterWatch:RegisterEvent("GROUP_ROSTER_UPDATE")
local function checkGuids()
    forEachButton(function(b)
        if b.unit and b:IsShown() then
            local guid = UnitGUID(b.unit)
            if N.IsSecret(guid) or N.IsSecret(b._drawnGuid) or guid ~= b._drawnGuid then
                b._drawnGuid = guid
                fullUpdate(b)
            end
        end
    end)
end
rosterWatch:SetScript("OnEvent", function()
    C_Timer.After(0, checkGuids)
    C_Timer.After(0.5, checkGuids)
end)

local relayoutPending
function N.RefreshAllButtons()
    forEachButton(function(child)
        UF.LayoutBars(child)
        if child:IsShown() then fullUpdate(child) end
    end)
    -- A size change reaches the bars a frame later, so the overlay widths are measured again.
    if not relayoutPending then
        relayoutPending = true
        C_Timer.After(0, function()
            relayoutPending = false
            forEachButton(function(child)
                UF.LayoutBars(child)
                if child:IsShown() then render(child) end
            end)
        end)
    end
end

N:On("NUCLEUS_SETTING_CHANGED", function(_, section, path)
    if N.GROUP_KEYS[section] and path and path:find("%.appearance%.") then
        N.RefreshAllButtons()
    elseif path == "translitNames" then
        N.RefreshAllButtons()
    end
end)

local watcher = CreateFrame("Frame")
N.SafeRegister(watcher, "PLAYER_TARGET_CHANGED")
N.SafeRegister(watcher, "PLAYER_FOCUS_CHANGED")
N.SafeRegister(watcher, "UNIT_TARGET")
watcher:SetScript("OnEvent", function(_, event, unit)
    if event ~= "UNIT_TARGET" or unit == "target" or unit == "player" then
        forEachButton(function(child)
            local u = child.unit
            if (u == "target" or u == "focus" or u == "targettarget") and child:IsShown() then fullUpdate(child) end
        end)
    end
    if event == "PLAYER_FOCUS_CHANGED" or event == "UNIT_TARGET" then return end
    forEachButton(function(child)
        if child.unit then
            local tgt = UnitExists("target") and UnitIsUnit(child.unit, "target")
            child.isTarget = (not IsSecret(tgt)) and tgt == true
            for i = 1, #child.targetEdges do child.targetEdges[i]:SetShown(child.isTarget) end
        end
    end)
end)
