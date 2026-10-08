local _, ns = ...
local N = ns.N
local IsSecret = N.IsSecret

-- Actions: a short animation on a group member's frame when they use a listed spell (potion,
-- Healthstone, trinket). The list, animation and color are settings (N.db.actions). The display is
-- global, not per party/raid, because it reacts to casts, not to unit state.
--
-- The cast comes from UNIT_SPELLCAST_SUCCEEDED, whose spell ID can be hidden on Midnight; a hidden
-- ID is ignored.
--
-- Animations (all clipped to the frame):
--   sweep  a colored band rises from the bottom to the top
--   wipe   a colored band moves from left to right
--   rise   the spell icon floats up from the middle and fades

local Actions = {}
N.Actions = Actions

Actions.ANIMATIONS = { "sweep", "wipe", "rise" }

local function config()
    return N.db and N.db.actions
end

local function speed()
    local s = (config() and config().speed) or 1
    return (s > 0.1) and s or 1
end

local STRIPS = 10

-- Lays the strips out along the band's travel direction, faintest first.
local function paintBand(set, c, vertical)
    local band = set.band
    for i, t in ipairs(set.strips) do
        t:SetColorTexture(c[1], c[2], c[3], 0.9 * i / STRIPS)
        t:ClearAllPoints()
        if vertical then
            local sh = band:GetHeight() / STRIPS
            t:SetPoint("BOTTOMLEFT", band, "BOTTOMLEFT", 0, (i - 1) * sh)
            t:SetPoint("BOTTOMRIGHT", band, "BOTTOMRIGHT", 0, (i - 1) * sh)
            t:SetHeight(sh)
        else
            local sw = band:GetWidth() / STRIPS
            t:SetPoint("TOPLEFT", band, "TOPLEFT", (i - 1) * sw, 0)
            t:SetPoint("BOTTOMLEFT", band, "BOTTOMLEFT", (i - 1) * sw, 0)
            t:SetWidth(sw)
        end
    end
end

local function build(b)
    local set = {}
    local clip = CreateFrame("Frame", nil, b.overlay or b)
    clip:SetAllPoints(b)
    clip:SetFrameLevel((b.overlay or b):GetFrameLevel() + 8)
    clip:SetClipsChildren(true)
    clip:Hide()
    set.clip = clip

    -- sweep / wipe: one band, re-anchored per play. Built from a few solid strips of rising
    -- opacity (soft leading edge) instead of a gradient texture, so the color stays exactly the
    -- chosen one.
    local band = CreateFrame("Frame", nil, clip)
    band:Hide()
    set.band = band
    set.strips = {}
    for i = 1, STRIPS do
        local t = band:CreateTexture(nil, "ARTWORK")
        t:SetTexture(N.Media.flat)
        set.strips[i] = t
    end
    local ag = band:CreateAnimationGroup()
    local move = ag:CreateAnimation("Translation")
    local fade = ag:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetStartDelay(0.15)
    ag:SetScript("OnFinished", function() clip:Hide() end)
    set.bandAG, set.bandMove, set.bandFade = ag, move, fade

    local icon = clip:CreateTexture(nil, "OVERLAY")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    set.icon = icon
    local iag = icon:CreateAnimationGroup()
    local imove = iag:CreateAnimation("Translation")
    local ifade = iag:CreateAnimation("Alpha")
    ifade:SetFromAlpha(1)
    ifade:SetToAlpha(0)
    ifade:SetStartDelay(0.25)
    iag:SetScript("OnFinished", function() clip:Hide() end)
    set.iconAG, set.iconMove, set.iconFade = iag, imove, ifade

    b._nucActions = set
    return set
end

local function play(b, entry)
    local set = b._nucActions or build(b)
    local w, h = b:GetWidth(), b:GetHeight()
    if not (w and h and w > 0 and h > 0) then return end
    local c = entry.color or { 1, 1, 1 }
    local sp = speed()
    local anim = entry.anim

    set.bandAG:Stop()
    set.iconAG:Stop()
    set.band:Hide()
    set.icon:Hide()
    set.clip:Show()

    if anim == "rise" then
        local size = math.max(14, math.min(w, h) * 0.5)
        set.icon:SetSize(size, size)
        set.icon:ClearAllPoints()
        set.icon:SetPoint("CENTER", set.clip, "CENTER", 0, -h * 0.15)
        local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(entry.spell)
        set.icon:SetTexture(tex or 134400)
        set.icon:SetVertexColor(1, 1, 1)
        set.iconMove:SetOffset(0, h * 0.4)
        set.iconMove:SetDuration(0.9 / sp)
        set.iconFade:SetDuration(0.65 / sp)
        set.iconFade:SetStartDelay(0.25 / sp)
        set.icon:Show()
        set.iconAG:Play()
    elseif anim == "wipe" then
        set.band:ClearAllPoints()
        set.band:SetPoint("TOPRIGHT", set.clip, "TOPLEFT", 0, 0)
        set.band:SetPoint("BOTTOMRIGHT", set.clip, "BOTTOMLEFT", 0, 0)
        set.band:SetWidth(math.max(12, w * 0.35))
        paintBand(set, c, false)
        set.bandMove:SetOffset(w + set.band:GetWidth(), 0)
        set.bandMove:SetDuration(0.7 / sp)
        set.bandFade:SetDuration(0.45 / sp)
        set.bandFade:SetStartDelay(0.25 / sp)
        set.band:Show()
        set.bandAG:Play()
    else
        set.band:ClearAllPoints()
        set.band:SetPoint("TOPLEFT", set.clip, "BOTTOMLEFT", 0, 0)
        set.band:SetPoint("TOPRIGHT", set.clip, "BOTTOMRIGHT", 0, 0)
        set.band:SetHeight(math.max(12, h * 0.4))
        paintBand(set, c, true)
        set.bandMove:SetOffset(0, h + set.band:GetHeight())
        set.bandMove:SetDuration(0.7 / sp)
        set.bandFade:SetDuration(0.45 / sp)
        set.bandFade:SetStartDelay(0.25 / sp)
        set.band:Show()
        set.bandAG:Play()
    end
end

local function buttonForUnit(unit)
    local found
    N.UnitFrame.ForEachButton(function(child)
        if not found and child.unit and child:IsShown() then
            local same = UnitIsUnit(child.unit, unit)
            if not IsSecret(same) and same then found = child end
        end
    end)
    return found
end

function Actions.Play(unit, entry)
    local b = buttonForUnit(unit)
    if b then play(b, entry) end
end

-- The options Test button: plays on the preview frame (always there) and on your own frame.
function Actions.Test(entry)
    if N.Preview and N.Preview.EachActionsPreview then
        N.Preview.EachActionsPreview(function(b) play(b, entry) end)
    end
    Actions.Play("player", entry)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
frame:SetScript("OnEvent", function(_, _, unit, _, spellID)
    local cfg = config()
    if not (cfg and cfg.enabled) or type(unit) ~= "string" then return end
    if not (unit == "player" or unit == "pet" or unit:find("^party%d") or unit:find("^raid%d")) then return end
    if spellID == nil or IsSecret(spellID) then return end
    for _, entry in ipairs(cfg.list or {}) do
        if entry.spell == spellID then
            Actions.Play(unit, entry)
            return
        end
    end
end)
