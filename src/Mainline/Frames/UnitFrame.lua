local _, ns = ...
local N = ns.N
local M = N.Media
local L = N.L

-- Unit frame visual layer. Split in three so the same look drives both the
-- secure header children (real units) and the test-mode preview (mock data):
--
--   UF.CreateVisual(b, key)  builds every texture on the button
--   readUnit(b) / mock       fill b.* data fields from the game or a mock table
--   render(b)                 paints the textures from b.*
--
-- The secure header owns creation/sizing/unit assignment; CreateVisual is
-- reached from its initialConfigFunction via CallMethod (no taint).

local UF = {}
N.UnitFrame = UF

local Abbrev = _G.AbbreviateNumbers or function(v)
    if v >= 1e6 then return string.format("%.1fM", v / 1e6) end
    if v >= 1e3 then return string.format("%.0fK", v / 1e3) end
    return tostring(v)
end

-- Custom Health Text / Power Text templates: {p}=percent, {v}=value,
-- {m}=max, {d}=deficit (max-value). The template is plain (typed) text, so
-- string.gsub on it is fine; the only secret-touching step is the single
-- fs:SetFormattedText(spec, ...) call at the end, which - like every other
-- SetFormattedText in this file - tolerates secret arguments. Building
-- spec/args token-by-token in ONE left-to-right gsub pass keeps their order
-- in sync (processing token types separately would desync them: the Nth arg
-- must line up with the Nth %d in spec, not with the Nth occurrence of its
-- own token type).
local function applyCustomFormat(fs, tmpl, val, valMax, pct)
    local args = {}
    local spec = (tmpl or ""):gsub("%%", "%%%%")
    spec = spec:gsub("{(%a)}", function(tok)
        -- A token whose value is unknown (nil) is dropped, not formatted: a
        -- "%d" with no matching argument would make SetFormattedText throw.
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

local UNIT_EVENTS = {
    "UNIT_HEALTH", "UNIT_MAXHEALTH",
    "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
    "UNIT_NAME_UPDATE", "UNIT_CONNECTION",
    "UNIT_THREAT_SITUATION_UPDATE",
    "UNIT_HEAL_PREDICTION", "UNIT_ABSORB_AMOUNT_CHANGED",
    "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
}

--------------------------------------------------------------------------------
-- Visual construction
--------------------------------------------------------------------------------

-- `v` UI units as a whole number of physical pixels at the frame's scale. Plain 1-unit
-- offsets land on different sub-pixels at the top-left and the bottom-right when the
-- UI scale is not 1, which made the frame's left and top edges look thicker.
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

    -- Incoming-heal / absorb / heal-absorb: real StatusBars sharing health's
    -- own [0, hpMax] scale, each anchored to health's RENDERED FILL TEXTURE
    -- (a region, not a computed offset) with a plain, non-secret pixel width
    -- (frame dimensions are never secret). Because the anchor and the scale
    -- both match health's, StatusBar:SetValue(amount) alone works out the
    -- correct on-screen fraction through the engine's own fill math - the
    -- addon never adds or divides a possibly-secret number. See
    -- Core/Secret.lua for the wider ruleset this follows.
    local overlayClip = CreateFrame("Frame", nil, b)
    overlayClip:SetAllPoints(health)
    overlayClip:SetClipsChildren(true)
    overlayClip:SetFrameLevel(health:GetFrameLevel() + 1)
    b.overlayClip = overlayClip

    local fillTex = health:GetStatusBarTexture()

    -- Texture/tiling/color are applied per Appearance > Shield settings in
    -- LayoutBars, not here - only the anchor geometry (which is what makes
    -- this secret-safe) is fixed at creation.
    local function overlayBar()
        local bar = CreateFrame("StatusBar", nil, overlayClip)
        bar:SetStatusBarTexture(M.flat)
        bar:SetPoint("TOPLEFT", fillTex, "TOPRIGHT", 0, 0)
        bar:SetPoint("BOTTOMLEFT", fillTex, "BOTTOMRIGHT", 0, 0)
        return bar
    end

    b.healPredict = overlayBar()

    -- Shield: anchored to the fill edge like healPredict, so it's bound to
    -- current health and grows into the missing-health room. Using the RAW
    -- absorb amount (not a computed "clamped" one) is fine here because
    -- overlayClip clips children to the health frame - if the amount would
    -- render past the bar's right edge, the engine just clips it there, with
    -- no addon arithmetic needed to find that limit.
    --
    -- There's deliberately no second "overflow" bar spilling onto the already
    -- -filled health once the shield is bigger than the missing-health room
    -- (what Ellesmere/Blizzard's own native compact frames show) - that needs
    -- knowing exact current health vs. max health, which Midnight keeps
    -- secret from addons. Ellesmere gets it for free because it reskins
    -- Blizzard's own CompactPartyFrameMember/CompactRaidFrame frames instead
    -- of drawing its own (see Integrations/Ping.lua, which hooks the same
    -- frames) - Blizzard's own code isn't addon-restricted. Cell draws its
    -- own frames like we do and has the identical limitation. overAbsorb
    -- below is the addon-safe substitute: a spark at the edge, not a
    -- precisely-sized overlap.
    b.absorb = overlayBar()

    -- The part of the shield that does not fit into the missing health (the whole
    -- shield at full health): a second bar growing from the bar's right edge towards
    -- the left, clipped to the filled part of the health. Where it reaches into the
    -- fill, the first bar's shield is already off the edge - so the two never overlap
    -- and nothing needs to be calculated from the (secret) health values.
    local fillClip = CreateFrame("Frame", nil, b)
    fillClip:SetPoint("TOPLEFT", health, "TOPLEFT")
    fillClip:SetPoint("BOTTOMRIGHT", fillTex, "BOTTOMRIGHT")
    fillClip:SetClipsChildren(true)
    fillClip:SetFrameLevel(health:GetFrameLevel() + 2)
    b.absorbFillClip = fillClip
    local absorbOver = CreateFrame("StatusBar", nil, fillClip)
    absorbOver:SetStatusBarTexture(M.flat)
    absorbOver:SetReverseFill(true)
    absorbOver:SetPoint("TOPRIGHT", health, "TOPRIGHT", 0, 0)
    absorbOver:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, 0)
    b.absorbOver = absorbOver

    -- Heal-absorb eats INTO the filled health instead of extending past it,
    -- so it fills backwards from the same edge.
    local healAbsorb = CreateFrame("StatusBar", nil, overlayClip)
    healAbsorb:SetStatusBarTexture(M.flat)
    healAbsorb:SetReverseFill(true)
    healAbsorb:SetPoint("TOPRIGHT", fillTex, "TOPRIGHT", 0, 0)
    healAbsorb:SetPoint("BOTTOMRIGHT", fillTex, "BOTTOMRIGHT", 0, 0)
    b.healAbsorb = healAbsorb

    -- Overshield spark: only shown when the heal-prediction calculator says
    -- the absorb overflows past missing health (see render()).
    local overAbsorb = overlayClip:CreateTexture(nil, "OVERLAY")
    overAbsorb:SetTexture(M.flat)
    overAbsorb:SetColorTexture(0.75, 0.90, 1.00, 0.9)
    overAbsorb:SetWidth(2)
    overAbsorb:SetPoint("TOP", health)
    overAbsorb:SetPoint("BOTTOM", health)
    overAbsorb:SetPoint("RIGHT", health, "RIGHT", 0, 0)
    overAbsorb:Hide()
    b.overAbsorb = overAbsorb

    -- Blizzard's addon-safe calculator: gives an absorb amount already
    -- clamped to missing health, plus a non-secret "did it overflow" flag,
    -- so the overshield spark works without the addon ever computing
    -- current-health-plus-absorb itself. The clamp mode is re-applied on
    -- every render() call, right before each GetDetailedHealPrediction -
    -- Cell's own Midnight shield code does the same, and it doesn't reliably
    -- stick across calls if only set once here at creation.
    if _G.CreateUnitHealPredictionCalculator then
        b.healCalc = CreateUnitHealPredictionCalculator()
    end

    -- Anchored for real in LayoutBars, which applies its configured X/Y offset;
    -- this is just a placeholder so the frame has a sane look before that runs.
    local power = CreateFrame("StatusBar", nil, b)
    power:SetPoint("BOTTOMLEFT", 1, 1)
    power:SetPoint("BOTTOMRIGHT", -1, 1)
    power:SetHeight(4)
    N.SkinBar(power)
    b.power = power

    -- Everything that must sit above the bars (text, edges, indicator icons)
    -- lives on this overlay frame - a child of the button drawn above the
    -- StatusBar child frames.
    local overlay = CreateFrame("Frame", nil, b)
    overlay:SetAllPoints(b)
    overlay:SetFrameLevel(math.max(health:GetFrameLevel(), power:GetFrameLevel()) + 4)
    b.overlay = overlay

    -- Status and Ready Check always sit above every other indicator.
    local top = CreateFrame("Frame", nil, b)
    top:SetAllPoints(b)
    top:SetFrameLevel(overlay:GetFrameLevel() + 50)
    b.topOverlay = top

    -- Target outline and mouseover outline, one draw-layer above the Aggro
    -- Border indicator (Indicators.lua) -
    -- separate texture sets so each can have its own color/thickness
    -- (Appearance > Border). Full geometry (points/size, not just color) is
    -- set in applyOutlineStyle/LayoutBars, since thickness lives there too -
    -- these are just the bare textures.
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
    -- General frame border (Appearance > Border): sits inside the frame edge,
    -- below the target / mouseover outlines.
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

-- Preview mask: a preview button carries button._previewOnly = <element name>;
-- everything whose name doesn't match is hidden so only that indicator shows.
local function pShow(b, name)
    -- The Actions preview shows a plain frame: just the name besides the mask.
    return (not b._previewOnly) or b._previewOnly == name
        or (b._previewOnly == "actions" and name == "name")
end

-- An element counts as on when enabled, or when it is the one the preview is editing.
local function pOn(b, name, enabled)
    return enabled or b._previewOnly == name or (b._previewOnly == "actions" and name == "name")
end

local function styleText(fs, o, dim)
    fs:SetFont(M.font, o.size or 11, "OUTLINE")
    local c = (dim and M.color.textDim) or o.color or M.color.text
    fs:SetTextColor(c[1], c[2], c[3])
end

-- 9-point text placement inside the health bar: { point, justifyH, justifyV,
-- inset x, inset y }. "center" has no inset; the edge spots keep 2px off the border.
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

-- o = the indicator's settings (position, x, y); dy = extra vertical shift
-- used when name and health text share the middle.
local function placeText(fs, host, o, dy)
    local a = ANCHORS[o.position or "center"] or ANCHORS.center
    fs:ClearAllPoints()
    fs:SetPoint(a[1], host, a[1], a[4] + (o.x or 0), a[5] + (o.y or 0) + (dy or 0))
    fs:SetJustifyH(a[2])
    fs:SetJustifyV(a[3])
end

UF.PlaceText = placeText -- shared with the icon-less text indicators in Indicators.lua

-- Shield/heal-absorb/heal-prediction overlay: texture + tiling (a real
-- pattern instead of a stretched smear) and its tint, from Appearance >
-- Shield. Color/opacity live here (not render()) since they're settings, not
-- per-update data - render() only ever touches SetValue on these bars.
local function applyShieldStyle(bar, cfg)
    local tex = M.shieldTextures[cfg.style] or M.flat
    bar:SetStatusBarTexture(tex)
    local fill = bar:GetStatusBarTexture()
    if fill then
        fill:SetDrawLayer("ARTWORK")
        if fill.SetHorizTile then fill:SetHorizTile(cfg.style == "striped") end
    end
    local c = cfg.color or { 1, 1, 1 }
    bar:SetStatusBarColor(c[1], c[2], c[3], cfg.opacity or 1)
end

-- Target/mouseover outline: color + thickness from Appearance > Border.
-- edges is the 4-texture set from CreateVisual's makeOutline(), in
-- TOP/BOTTOM/LEFT/RIGHT order. The border sits flush against the frame edge
-- and grows outward from there as it thickens (never eating into the bars).
-- TOP/BOTTOM span the FULL outer width, corners included; LEFT/RIGHT are
-- inset to fit exactly in the gap between them - so thickening the border
-- can't leave the small overlapping "nub" at each corner that came from
-- every side overhanging the corner by a fixed 1px regardless of thickness.
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

-- General frame border: four edges drawn inside the frame, on top of the bars.
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
    -- The panel's own 1px outline would double up (or show when disabled).
    N.SetPanelBorder(b, { 0, 0, 0, 0 })
end

-- Whether this unit's role is allowed to show a power bar (Indicators > Power
-- Bar > Show for ...). Unknown / secret roles are allowed.
function UF.PowerAllowed(b)
    local pb = N.db[b.groupKey].indicators.powerBar
    local role
    if b._mock then role = b._mock.role
    elseif b.unit then role = UnitGroupRolesAssigned(b.unit) end
    if role == nil or N.IsSecret(role) then return true end
    local class = b.class
    if class == nil or N.IsSecret(class) then return true end
    local byClass = pb.filter and pb.filter[class]
    return not (byClass and byClass[role] == false)
end

-- Height the shown power bar takes at the bottom of the frame: icons anchored to a
-- bottom point sit above it instead of on it.
function N.PowerInset(b)
    local pb = b.power
    if not (pb and pb:IsShown()) then return 0 end
    local o = N.db[b.groupKey].indicators.powerBar
    return (o.height or 4) + (o.y or 0)
end

-- Position + size the bars and name/health/status/power text for the current
-- indicator settings. Cheap; call whenever settings or frame size change.
function UF.LayoutBars(b)
    local ind = N.db[b.groupKey].indicators
    local appearance = N.db[b.groupKey].appearance
    local pb = ind.powerBar
    b._powerShown = UF.PowerAllowed(b)
    local ph = (pOn(b, "powerBar", pb.enabled) and b._powerShown and (pb.height or 4)) or 0

    -- Bar texture + loss color apply to both bars; SetStatusBarColor is
    -- re-applied by the next render() (changing texture resets the tint).
    N.SetBarTexture(b.health, appearance.barTexture)
    N.SetBarTexture(b.power, appearance.barTexture)
    N.SetBarLossColor(b.health, appearance.healthLossColor)
    N.SetBarLossColor(b.power, appearance.healthLossColor)

    applyShieldStyle(b.absorb, appearance.absorb)
    applyShieldStyle(b.absorbOver, appearance.absorb)
    applyShieldStyle(b.healAbsorb, appearance.healAbsorb)
    applyOutlineStyle(b.targetEdges, appearance.targetBorder)
    applyOutlineStyle(b.hoverEdges, appearance.hoverBorder)
    applyFrameBorder(b, appearance.frameBorder)
    applyShieldStyle(b.healPredict, { style = "flat", color = appearance.healPredict.color,
        opacity = appearance.healPredict.opacity })

    b.power:SetShown(pOn(b, "powerBar", pb.enabled) and b._powerShown and pShow(b, "powerBar"))
    b.power:SetHeight(pb.height or 4)
    b.power:ClearAllPoints()
    b.power:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", snap(b, 1) + (pb.x or 0), snap(b, 1) + (pb.y or 0))
    b.power:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", snap(b, -1) + (pb.x or 0), snap(b, 1) + (pb.y or 0))
    b.health:SetPoint("TOPLEFT", b, "TOPLEFT", snap(b, 1), snap(b, -1))
    b.health:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", snap(b, -1), snap(b, 1 + (ph > 0 and ph + 1 or 0)))

    -- Text width from the configured frame width (health width resolves late),
    -- so long names truncate instead of overflowing. A single anchor point +
    -- explicit width lets the X/Y offsets actually move the text.
    local textW = N.db[b.groupKey].width - 6
    local name, hp = ind.name, ind.healthText
    styleText(b.nameText, name)
    styleText(b.hpText, hp)
    b.nameText:SetWidth(textW)
    b.hpText:SetWidth(textW)
    -- Name and health text both sit in the middle by default and then stack
    -- (name above, health below); anywhere else they are placed independently.
    local stacked = pOn(b, "name", name.enabled) and pOn(b, "healthText", hp.enabled)
        and (name.position or "center") == "center" and (hp.position or "center") == "center"
    placeText(b.nameText, b.health, name, stacked and 6 or 0)
    placeText(b.hpText, b.health, hp, stacked and -6 or 0)

    -- Power text sits on the health bar like the other texts (a 4px-tall power
    -- bar is no place for a line of text), at one of the nine positions.
    b.powerText:SetFont(M.font, pb.textSize or 9, "OUTLINE")
    -- No fixed width: the anchor alone decides where a short text sits, so left /
    -- right positions can never depend on justification inside a wide box.
    b.powerText:SetWidth(0)
    placeText(b.powerText, b.health, { position = pb.textPosition, x = pb.textX, y = pb.textY })
    b.powerText:SetShown(pOn(b, "powerBar", pb.enabled) and b._powerShown and pb.text and pShow(b, "powerBar"))

    -- Overlay bars need an explicit pixel width (plain Lua number, never
    -- secret) since only one edge is anchored to health's fill texture.
    local hw = b.health:GetWidth() or 0
    b.healPredict:SetWidth(hw)
    b.absorb:SetWidth(hw)
    b.absorbOver:SetWidth(hw)
    b.healAbsorb:SetWidth(hw)

    -- Shield fill direction: normally it grows from the end of the health fill;
    -- "inverted" grows from the right edge of the bar instead.
    b.absorb:ClearAllPoints()
    if appearance.absorb.invertFill then
        b.absorb:SetReverseFill(true)
        b.absorb:SetPoint("TOPRIGHT", b.health, "TOPRIGHT", 0, 0)
        b.absorb:SetPoint("BOTTOMRIGHT", b.health, "BOTTOMRIGHT", 0, 0)
    else
        local fillTex = b.health:GetStatusBarTexture()
        b.absorb:SetReverseFill(false)
        b.absorb:SetPoint("TOPLEFT", fillTex, "TOPRIGHT", 0, 0)
        b.absorb:SetPoint("BOTTOMLEFT", fillTex, "BOTTOMRIGHT", 0, 0)
    end
    local oc = appearance.overshieldColor or { 0.75, 0.90, 1.00 }
    b.overAbsorb:SetColorTexture(oc[1], oc[2], oc[3], 0.9)

    if N.Auras then N.Auras.Layout(b) end
end

--------------------------------------------------------------------------------
-- Data
--------------------------------------------------------------------------------

local IsSecret, AnySecret = N.IsSecret, N.AnySecret

local function desecret(v, fallback)
    if IsSecret(v) then return fallback end
    if v == nil then return fallback end
    return v
end

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
    b.incHeal = UnitGetIncomingHeals and UnitGetIncomingHeals(u) or 0
    b.absorbAmt = UnitGetTotalAbsorbs and UnitGetTotalAbsorbs(u) or 0
    b.healAbsorbAmt = UnitGetTotalHealAbsorbs and UnitGetTotalHealAbsorbs(u) or 0
    local tgt = UnitExists("target") and UnitIsUnit(u, "target")
    b.isTarget = (not IsSecret(tgt)) and tgt == true
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

-- Class color, a fixed custom color, or a red->yellow->green health gradient.
-- The gradient only ever runs arithmetic on N.HealthFraction's result, which
-- is nil whenever the true fraction isn't safely known - never on hp/hpMax
-- directly, so it can't throw on a Midnight secret.
local function healthColor(b, appearance)
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

-- Text colour for the name / health text: the unit's class colour or the
-- configured custom colour.
local function textRGB(b, o, fallback)
    if o.colorMode == "class" then return N.ClassRGB(b.class) end
    local c = o.color or fallback
    return c[1], c[2], c[3]
end

-- "12.3K". AbbreviateNumbers accepts secret numbers (the result may itself be
-- secret), so the string is only ever handed to a FontString, never inspected.
local function shortNum(v)
    if v == nil then return nil end
    local ok, s = pcall(Abbrev, v)
    if ok then return s end
    return nil
end

-- Health as 0..100 (possibly secret), or nil when it can't be known.
local function hpPercent(b)
    local pct
    if b.unit then pct = N.HealthPercent(b.unit) end
    if pct == nil and not AnySecret(b.hp, b.hpMax) and b.hp and b.hpMax and b.hpMax > 0 then
        pct = b.hp / b.hpMax * 100
    end
    return pct
end

-- Missing health as "-12.3K", blank when nothing is missing. When the number is
-- secret, TruncateWhenZero (a secret-safe sink) blanks the zero case and the
-- text stays unreadable-but-showable.
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

-- All health-text formats. Secret numbers can't be read but CAN be formatted
-- into a FontString, so every mode still shows something on Midnight.
local function setHealthText(b, fs, o)
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
        fs:SetFormattedText("%d%%", pct) -- "percent", and the fallback for the rest
    else
        fs:SetText("")
    end
end

-- Power as 0..100 (possibly secret): UnitPowerPercent is the secret-safe route.
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

-- The colour of the unit's power type (mana blue, rage red, energy yellow, runic
-- power cyan, ...). Blizzard's PowerBarColor knows most tokens; the rest have a
-- fallback so no class ever ends up on the wrong colour.
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
    -- A hunter only ever has Focus: whatever the power type says, it gets Focus's amber
    -- (never the yellow of Energy). Pets keep their own type.
    if b.class == "HUNTER" and not (type(b.unit) == "string" and b.unit:find("pet")) then
        local fb = POWER_FALLBACK.FOCUS
        return fb[1], fb[2], fb[3]
    end
    local t = b.ppType
    if type(t) == "string" and not N.IsSecret(t) then
        -- Our table first: Focus (hunter) must be its orange, never an energy yellow.
        local fb = POWER_FALLBACK[t]
        if fb then return fb[1], fb[2], fb[3] end
        local pc = PowerBarColor[t]
        if pc then return pc.r, pc.g, pc.b end
    end
    local e = b.ppEnum
    if e == 2 then return 0.867, 0.573, 0.216 end -- Enum.PowerType.Focus
    if type(e) == "number" and not N.IsSecret(e) then
        local pc = PowerBarColor[e]
        if pc then return pc.r, pc.g, pc.b end
    end
    local pc = PowerBarColor[t or 0] or PowerBarColor[0]
    if pc then return pc.r, pc.g, pc.b end
    return 0, 0, 1
end

-- Power text colour: the power type's own colour, the class colour, or custom.
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

local function render(b)
    local appearance = N.db[b.groupKey].appearance

    -- Health bar: StatusBar:SetMinMaxValues / SetValue tolerate secret numbers.
    b.hpMax = b.hpMax or 1; b.hp = b.hp or 0
    b.health:SetMinMaxValues(0, b.hpMax)
    if b.connected then b.health:SetValue(b.hp) else b.health:SetValue(0) end
    b.health:SetStatusBarColor(healthColor(b, appearance))

    local ind = N.db[b.groupKey].indicators

    -- The power bar's visibility is re-checked on every paint (as Cell and Ellesmere do):
    -- a bar that is shown although it is switched off, or hidden although it is on, is
    -- put right here instead of waiting for the next layout pass.
    local wantPower = pOn(b, "powerBar", ind.powerBar.enabled) and b._powerShown and pShow(b, "powerBar")
    if (wantPower and true or false) ~= (b.power:IsShown() and true or false) then UF.LayoutBars(b) end

    -- Offline / Dead / ... is the Status indicator's own bar (Indicators.lua); it
    -- no longer takes over the name and health text.
    local statusMsg = nil

    -- name
    b.nameText:SetShown(pOn(b, "name", ind.name.enabled) and not statusMsg and pShow(b, "name"))
    if pOn(b, "name", ind.name.enabled) and not statusMsg then
        b.nameText:SetText(N.Translit(b.pName) or "")
        if (not b.connected) or b.dead then
            b.nameText:SetTextColor(M.color.textDim[1], M.color.textDim[2], M.color.textDim[3])
        else
            b.nameText:SetTextColor(textRGB(b, ind.name, { 0.92, 0.92, 0.94 }))
        end
    end

    -- health text (formats and secret handling: setHealthText above)
    b.hpText:SetShown(pOn(b, "healthText", ind.healthText.enabled) and not statusMsg and pShow(b, "healthText"))
    if pOn(b, "healthText", ind.healthText.enabled) and not statusMsg then
        setHealthText(b, b.hpText, ind.healthText)
        b.hpText:SetTextColor(textRGB(b, ind.healthText, { 0.85, 0.85, 0.87 }))
    end

    -- power
    if b.power:IsShown() then
        b.power:SetMinMaxValues(0, b.ppMax)
        if b.connected then b.power:SetValue(b.pp) else b.power:SetValue(0) end
        b.power:SetStatusBarColor(powerRGB(b))
    end

    -- power text (formats and secret handling: setPowerText above)
    if b.powerText:IsShown() then
        setPowerText(b, b.powerText, ind.powerBar)
    end

    -- heal prediction / absorb shield / heal-absorb: see CreateVisual for why
    -- these are StatusBars anchored to health's fill texture rather than
    -- Lua-computed pixel segments - it's what makes this secret-safe.
    if b._previewOnly or not b.connected then
        b.healPredict:Hide()
        b.absorb:Hide()
        b.absorbOver:Hide()
        b.healAbsorb:Hide()
        b.overAbsorb:Hide()
    else
        b.healPredict:SetMinMaxValues(0, b.hpMax)
        b.absorb:SetMinMaxValues(0, b.hpMax)
        b.absorbOver:SetMinMaxValues(0, b.hpMax)
        b.healAbsorb:SetMinMaxValues(0, b.hpMax)

        -- b.absorb uses the RAW total absorb amount (b.absorbAmt, straight
        -- from UnitGetTotalAbsorbs) - never anything we subtract or clamp
        -- ourselves. It's anchored to the fill edge, so overlayClip alone
        -- keeps it from ever rendering past the bar's right edge - no
        -- arithmetic needed to find that limit. The calculator below is only
        -- for the overshield spark's "did it overflow" flag (see
        -- CreateVisual for why there's no second bar spilling onto the
        -- already-filled health for the overflow itself).
        local absorbAmt, overshield = b.absorbAmt, false
        if b.healCalc and b.unit and _G.UnitGetDetailedHealPrediction then
            local ok, _, over = pcall(function()
                if b.healCalc.SetDamageAbsorbClampMode and Enum.UnitDamageAbsorbClampMode then
                    b.healCalc:SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MissingHealth)
                end
                UnitGetDetailedHealPrediction(b.unit, nil, b.healCalc)
                return b.healCalc:GetDamageAbsorbs()
            end)
            if ok then overshield = over end
        elseif b._mock then
            -- Mock data is always plain numbers, so a real comparison is fine here.
            local missing = (b.hpMax or 0) - (b.hp or 0)
            overshield = (absorbAmt or 0) > missing and missing >= 0
        end

        b._overshield = overshield -- read by the Shield Bar indicator

        local absorbShown = appearance.absorb.enabled ~= false

        b.healPredict:SetValue(b.incHeal or 0)
        b.healPredict:SetShown(appearance.healPredict.enabled ~= false)
        b.absorb:SetValue(absorbAmt or 0)
        b.absorb:SetShown(absorbShown)
        b.absorbOver:SetValue(absorbAmt or 0)
        b.absorbOver:SetShown(absorbShown and not appearance.absorb.invertFill)
        b.healAbsorb:SetValue(b.healAbsorbAmt or 0)
        b.healAbsorb:SetShown(appearance.healAbsorb.enabled ~= false)

        b.overAbsorb:SetShown(absorbShown and appearance.showOvershield ~= false
            and not IsSecret(overshield) and overshield == true)
    end

    -- target
    for i = 1, #b.targetEdges do b.targetEdges[i]:SetShown(b.isTarget and not b._previewOnly) end

    if N.Indicators then N.Indicators.UpdateAll(b) end
    if N.Auras then N.Auras.Update(b) end
end
UF.Render = render

local function fullUpdate(b)
    if not b.unit or not UnitExists(b.unit) then return end
    readUnit(b)
    -- The power bar can be limited to certain roles, and a unit's role can
    -- change (or only become known) after the frame was laid out.
    if b._powerShown ~= UF.PowerAllowed(b) then UF.LayoutBars(b) end
    render(b)
end
UF.FullUpdate = fullUpdate

-- Test mode feeds b.* from a mock table, then paints.
function UF.ApplyMock(b, m)
    b._mock = m
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
    b.incHeal = m.incHeal or 0
    b.absorbAmt = m.absorb or 0
    b.healAbsorbAmt = m.healAbsorb or 0
    b.isTarget = m.isTarget or false
    if b._powerShown ~= UF.PowerAllowed(b) then UF.LayoutBars(b) end
    render(b)
end

--------------------------------------------------------------------------------
-- Secure header wiring (real units)
--------------------------------------------------------------------------------

local function bindUnit(b)
    local unit = b:GetAttribute("unit")
    if unit == b.unit then return end
    b.unit = unit
    b:UnregisterAllEvents()
    if unit then
        for _, ev in ipairs(UNIT_EVENTS) do
            b:RegisterUnitEvent(ev, unit)
        end
        fullUpdate(b)
        -- Bar widths resolve a frame after anchoring; LayoutBars is what sets
        -- the overlay bars' pixel width, so it (not just render) has to run
        -- again once that's settled, or absorb/heal-predict stay pinned at
        -- their initial (zero) width until some later settings change happens
        -- to call LayoutBars for an unrelated reason.
        C_Timer.After(0, function()
            if b.unit == unit then
                UF.LayoutBars(b)
                render(b)
            end
        end)
    end
    if N.Auras and N.Auras.BindPrivate then N.Auras.BindPrivate(b) end
end

local function onEvent(b)
    fullUpdate(b)
end

local function onUpdate(b, elapsed)
    b.rangeElapsed = (b.rangeElapsed or 0) + elapsed
    if b.rangeElapsed < N.db.core.rangeUpdateInterval then return end
    b.rangeElapsed = 0
    if not b.unit or not UnitExists(b.unit) then return end

    local appearance = N.db[b.groupKey].appearance

    -- UnitInRange can return secret booleans under Midnight. A secret one cannot be
    -- tested, but the frame can take it straight into SetAlphaFromBoolean (in range:
    -- fully visible, out of range: the configured alpha).
    local alpha = 1
    -- Only the first return is used (as Ellesmere does): the second one ("was the
    -- range checked") can be missing, which would keep every frame at full alpha.
    -- You are never out of range of yourself (UnitInRange does not say so for "player").
    local inRange
    local me = UnitIsUnit(b.unit, "player")
    if me ~= nil and not N.IsSecret(me) and not me then me = UnitIsUnit(b.unit, "pet") end
    if me == nil or N.IsSecret(me) or not me then
        local checked
        inRange, checked = UnitInRange(b.unit)
        -- Pets: UnitInRange often says "false" for a pet whose range it did not check at
        -- all, so a pet only fades when the game says the range really was checked.
        if b.unit:find("pet") and not (checked ~= nil and not N.IsSecret(checked) and checked) then
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
        -- HealthFraction is nil whenever the true value isn't safely known
        -- (secret and no plain fallback) - fading just doesn't kick in then,
        -- same "degrade to no effect" rule as the health-gradient color mode.
        local frac = N.HealthFraction(b.unit)
        if frac and frac >= (appearance.healthFade.threshold or 1) then
            alpha = appearance.outOfRangeAlpha
        end
    end
    -- Set every pass (cheap): other code may have set the alpha in between.
    b.curAlpha = alpha
    b:SetAlpha(alpha)
end

function N.StyleUnitButton(name)
    local b = _G[name]
    if not b or b._nucStyled then return end
    b._nucStyled = true

    local parent = b:GetParent()
    UF.CreateVisual(b, (parent and parent.groupKey) or "party")

    -- A button only reacts to the mouse buttons it is registered for, and a
    -- plain Button knows the left one alone: without this, right / middle /
    -- extra-button click-casting (and the right-click menu) never fires.
    b:RegisterForClicks("AnyUp")

    -- Ping system: with this, the ping key pings the unit this frame shows
    -- instead of the ground behind it.
    if _G.PingableType_UnitFrameMixin then
        Mixin(b, _G.PingableType_UnitFrameMixin)
        function b:GetTargetPingGUID()
            local u = self.unit
            if not u then return nil end
            local guid = UnitGUID(u)
            if N.IsSecret(guid) then return nil end
            return guid
        end
        N.RunWhenSafe(function() b:SetAttribute("ping-receiver", true) end)
    end

    b:HookScript("OnAttributeChanged", function(self, attr)
        if attr == "unit" then bindUnit(self) end
    end)
    b:SetScript("OnEvent", onEvent)
    b:SetScript("OnUpdate", onUpdate)
    b:SetScript("OnShow", function(self) fullUpdate(self) end)
    b.NucleusBind = function(self) bindUnit(self or b) end
    b:SetScript("OnEnter", function(self)
        if not self.isTarget then
            for i = 1, #self.hoverEdges do self.hoverEdges[i]:Show() end
        end
    end)
    b:SetScript("OnLeave", function(self)
        for i = 1, #self.hoverEdges do self.hoverEdges[i]:Hide() end
    end)

    bindUnit(b)
end

-- Iterate every live header child.
local function forEachButton(fn)
    for _, header in pairs(N.headers or {}) do
        local i, child = 1, _G[header:GetName() .. "UnitButton1"]
        while child do
            if child._nucVisual then fn(child, header) end
            i = i + 1
            child = _G[header:GetName() .. "UnitButton" .. i]
        end
    end
end
UF.ForEachButton = forEachButton

function N.RefreshAllButtons()
    forEachButton(function(child)
        UF.LayoutBars(child)
        if child:IsShown() then fullUpdate(child) end
    end)
end

-- Bar texture / color-mode / loss-color changes: same refresh as an
-- indicator or aura setting, just keyed off .appearance. instead.
N:On("NUCLEUS_SETTING_CHANGED", function(_, section, path)
    if N.GROUP_KEYS[section] and path and path:find("%.appearance%.") then
        N.RefreshAllButtons()
    elseif path == "translitNames" then
        N.RefreshAllButtons()
    end
end)

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_TARGET_CHANGED")
watcher:RegisterEvent("PLAYER_FOCUS_CHANGED")
watcher:RegisterEvent("UNIT_TARGET")
watcher:SetScript("OnEvent", function(_, event, unit)
    -- Spotlight slots that show your target / focus / target's target follow it.
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
