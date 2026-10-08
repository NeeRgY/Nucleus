local _, ns = ...
local N = ns.N
local M = N.Media
local L = N.L
local IsSecret = N.IsSecret

-- Targeted Spell Bars
--
-- One floating, movable stack of cast bars: one bar per enemy nameplate that is
-- currently casting. It never tries to work out WHICH of our frames a cast is
-- aimed at (a guess the Secret Values system makes unreliable). Instead the
-- bar reads the target through the dedicated, secret-safe Blizzard APIs built
-- for it - UnitShouldDisplaySpellTargetName / UnitSpellTargetName /
-- UnitSpellTargetClass - and only ever hands the (possibly secret) result
-- straight to SetText / SetTextColor.
--
-- Because it is not tied to a unit frame it is not an entry in
-- Indicators.Register; it owns one shared container, its own settings
-- (N.db.targetedSpellBars) and its own options page under Indicators.

local TSB = {}
N.TargetedSpellBars = TSB

local UnitCanAttack = UnitCanAttack
local UnitCastingInfo = UnitCastingInfo
local UnitChannelInfo = UnitChannelInfo
local UnitCastingDuration = UnitCastingDuration
local UnitChannelDuration = UnitChannelDuration
local UnitEmpoweredChannelDuration = UnitEmpoweredChannelDuration
local GetTime = GetTime
local C_Spell = C_Spell
local C_NamePlate = C_NamePlate
local C_ClassColor = C_ClassColor

-- At the instant a START event fires, UnitCastingInfo / UnitCastingDuration are
-- not populated yet (Blizzard fills them a few frames later). 0.2s is past
-- that and still imperceptible on a cast bar.
local PICKUP_DELAY = 0.2

local Enum_ = _G.Enum
local INTERP_IMMEDIATE = Enum_ and Enum_.StatusBarInterpolation and Enum_.StatusBarInterpolation.Immediate
local DIR_ELAPSED = Enum_ and Enum_.StatusBarTimerDirection and Enum_.StatusBarTimerDirection.ElapsedTime
local DIR_REMAINING = Enum_ and Enum_.StatusBarTimerDirection and Enum_.StatusBarTimerDirection.RemainingTime

local PREVIEW = "__preview"

--------------------------------------------------------------------------------
-- config
--------------------------------------------------------------------------------

local function GetConfig()
    return N.db and N.db.targetedSpellBars
end

local function IsEnabled(cfg)
    return cfg ~= nil and cfg.enabled == true
end

local function WhereAllows(cfg)
    local where = cfg.where or "both"
    if where == "raid" then
        return IsInRaid()
    elseif where == "party" then
        return IsInGroup() and not IsInRaid()
    end
    return true -- "both": raid, party, or solo
end

--------------------------------------------------------------------------------
-- state
--------------------------------------------------------------------------------

local container            -- built lazily
local bars = {}            -- frame pool
local shown = {}           -- active entries, in display order
local unitEntry = {}       -- unit -> entry
local plateUnits = {}      -- unit -> true while its nameplate exists
local active = false       -- events registered / display live
local previewOn = false
local castGen = {}         -- unit -> generation; invalidates a deferred ApplyCast if the cast already stopped

local function barSize(cfg)
    return cfg.width or 220, cfg.height or 22
end

--------------------------------------------------------------------------------
-- container + mover
--------------------------------------------------------------------------------

local function SavePosition()
    local cfg = GetConfig()
    if not (cfg and container) then return end
    local cx, cy = container:GetCenter()
    local ux, uy = UIParent:GetCenter()
    if not (cx and ux) then return end
    cfg.point = "CENTER"
    cfg.x = N.Round(cx - ux)
    cfg.y = N.Round(cy - uy)
end

local function LoadPosition(cfg)
    if not (container and cfg) then return end
    container:ClearAllPoints()
    container:SetPoint("CENTER", UIParent, "CENTER", cfg.x or 0, cfg.y or 120)
end

local function EnsureContainer()
    if container then return container end
    container = CreateFrame("Frame", "NucleusTargetedSpellBarsFrame", UIParent)
    container:SetSize(220, 22)
    container:SetFrameStrata("MEDIUM")
    container:SetClampedToScreen(true)
    container:SetMovable(true)
    container:EnableMouse(false)
    container:Hide()

    -- Drag handle floating above the stack: its own drag scripts move the
    -- container, so grabbing the label (not just the bars) works.
    local handle = CreateFrame("Frame", nil, container)
    handle:SetPoint("BOTTOM", container, "TOP", 0, 4)
    handle:SetSize(150, 20)
    handle:SetFrameStrata("HIGH")
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function() container:StartMoving() end)
    handle:SetScript("OnDragStop", function()
        container:StopMovingOrSizing()
        SavePosition()
    end)
    N.SkinRound(handle, M.color.card, M.color.accent, true)
    local label = N.FontString(handle, 11)
    label:SetPoint("CENTER")
    label:SetTextColor(M.color.accentBright[1], M.color.accentBright[2], M.color.accentBright[3])
    label:SetText(L["Targeted Spell Bars"])
    handle:SetWidth(label:GetStringWidth() + 24)
    handle:Hide()
    container.handle = handle

    N.OnRecolor(function()
        N.SetPanelBorder(handle, M.color.accent)
        label:SetTextColor(M.color.accentBright[1], M.color.accentBright[2], M.color.accentBright[3])
    end)
    return container
end

local function ResizeContainer(cfg)
    local c = EnsureContainer()
    c:SetSize(barSize(cfg))
end

-- Handle is draggable while frames are unlocked or the preview is running.
local function SyncMover()
    if not container then return end
    local cfg = GetConfig()
    local want = cfg and IsEnabled(cfg) and (previewOn or not N.db.locked)
    if previewOn then want = true end
    container.handle:SetShown(want and true or false)
    if want then container:Show() end
    if not want and not active and not previewOn then container:Hide() end
end

--------------------------------------------------------------------------------
-- bar pool
--------------------------------------------------------------------------------

local function BuildBar()
    local c = EnsureContainer()
    local holder = CreateFrame("Frame", nil, c)
    holder:Hide()

    -- Spell icon on a small rounded plate.
    holder.iconFrame = CreateFrame("Frame", nil, holder)
    N.SkinRound(holder.iconFrame, M.color.segment, M.color.line, true)
    holder.icon = holder.iconFrame:CreateTexture(nil, "ARTWORK")
    holder.icon:SetPoint("TOPLEFT", 2, -2)
    holder.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    holder.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- NO BackdropTemplate anywhere in this bar's frame subtree (not on the
    -- StatusBar, not as its parent): a StatusBar driven by :SetTimerDuration()
    -- with a secret-tainted duration object crashes Backdrop.lua's corner
    -- redraw if any BackdropTemplate frame sits in the same chain. The rounded
    -- plate and rim are plain textures (SkinRound), never SetBackdrop.
    holder.barFrame = CreateFrame("Frame", nil, holder)
    N.SkinRound(holder.barFrame, M.color.segment, M.color.line, true)

    holder.bar = CreateFrame("StatusBar", nil, holder.barFrame)
    holder.bar:SetPoint("TOPLEFT", holder.barFrame, "TOPLEFT", 2, -2)
    holder.bar:SetPoint("BOTTOMRIGHT", holder.barFrame, "BOTTOMRIGHT", -2, 2)
    holder.bar:SetStatusBarTexture(M.barTextures.nucleus2) -- flat white: configured colour lands exactly
    holder.bar:SetStatusBarColor(1, 1, 1, 1)
    holder.bar:SetMinMaxValues(0, 1)
    holder.bar:SetValue(0)
    holder.bar:EnableMouse(false)

    holder.name = N.FontString(holder.bar, 11)
    holder.name:SetJustifyH("LEFT")
    holder.name:SetWordWrap(false)

    holder.target = N.FontString(holder.bar, 11)
    holder.target:SetJustifyH("RIGHT")
    holder.target:SetWordWrap(false)

    holder.timer = N.FontString(holder.bar, 11)
    holder.timer:SetJustifyH("RIGHT")
    holder.timer:SetWordWrap(false)

    return holder
end

local function AcquireBar()
    for i = 1, #bars do
        if not bars[i]._inUse then
            bars[i]._inUse = true
            return bars[i]
        end
    end
    local b = BuildBar()
    bars[#bars + 1] = b
    b._inUse = true
    return b
end

--------------------------------------------------------------------------------
-- style / layout
--------------------------------------------------------------------------------

local function StyleBar(holder, cfg)
    local w, h = barSize(cfg)
    holder:SetSize(w, h)

    holder.iconFrame:ClearAllPoints()
    holder.barFrame:ClearAllPoints()
    if cfg.showIcon ~= false then
        holder.iconFrame:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
        holder.iconFrame:SetSize(h, h)
        holder.iconFrame:Show()
        holder.barFrame:SetPoint("TOPLEFT", holder.iconFrame, "TOPRIGHT", 3, 0)
        holder.barFrame:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
    else
        holder.iconFrame:Hide()
        holder.barFrame:SetAllPoints(holder)
    end

    -- The base colour stays neutral white here: the visible colour (normal vs
    -- important) is applied per cast through the fill texture's vertex colour,
    -- because "important" can be a secret boolean that only a native
    -- colour-from-boolean sink can act on safely.
    holder.bar:SetStatusBarColor(1, 1, 1, 1)

    holder.name:ClearAllPoints()
    holder.name:SetPoint("LEFT", holder.bar, "LEFT", 6, 0)
    holder.timer:ClearAllPoints()
    holder.timer:SetPoint("RIGHT", holder.bar, "RIGHT", -6, 0)
    holder.target:ClearAllPoints()

    if cfg.showTargetText ~= false then
        holder.target:SetPoint("RIGHT", holder.timer, "LEFT", -8, 0)
        holder.name:SetWidth(math.max(1, w * 0.42))
        holder.target:SetWidth(math.max(1, w * 0.28))
    else
        holder.name:SetWidth(math.max(1, w - h - 40))
        holder.target:SetWidth(1)
    end
end

local SPACING = 3

local function PositionBar(holder, slot, cfg)
    holder:ClearAllPoints()
    local w, h = barSize(cfg)
    local orientation = cfg.orientation or "top-to-bottom"
    if orientation == "bottom-to-top" then
        holder:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, (slot - 1) * (h + SPACING))
    elseif orientation == "left-to-right" then
        holder:SetPoint("TOPLEFT", container, "TOPLEFT", (slot - 1) * (w + SPACING), 0)
    elseif orientation == "right-to-left" then
        holder:SetPoint("TOPRIGHT", container, "TOPRIGHT", -(slot - 1) * (w + SPACING), 0)
    else
        holder:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -(slot - 1) * (h + SPACING))
    end
end

local function Reflow(cfg)
    for i = 1, #shown do
        PositionBar(shown[i].bar, i, cfg)
    end
end

--------------------------------------------------------------------------------
-- important-cast colour marking
--------------------------------------------------------------------------------

-- `important` can be a secret boolean (spellId is normally secret for an enemy
-- nameplate cast), so it must never be truth-tested. The colour is applied
-- through the native colour-from-boolean sink built to accept a secret bool.
local function ApplyImportantVisual(holder, cfg, important)
    local normal = cfg.color or { 0.62, 0.42, 0.95 }
    local imp = cfg.importantColor or { 1.00, 0.80, 0.20 }
    local tex = holder.bar.GetStatusBarTexture and holder.bar:GetStatusBarTexture()
    if tex and tex.SetVertexColorFromBoolean then
        local flag = important
        if flag == nil then flag = false end
        tex:SetVertexColorFromBoolean(flag,
            { r = imp[1], g = imp[2], b = imp[3], a = 1 },
            { r = normal[1], g = normal[2], b = normal[3], a = 1 })
    elseif not IsSecret(important) then
        local c = (important == true) and imp or normal
        holder.bar:SetStatusBarColor(c[1], c[2], c[3], 1)
    end
end

--------------------------------------------------------------------------------
-- release
--------------------------------------------------------------------------------

local function Release(unit, cfg)
    castGen[unit] = (castGen[unit] or 0) + 1 -- invalidates any deferred ApplyCast still pending
    local e = unitEntry[unit]
    if not e then return end
    unitEntry[unit] = nil
    for i = 1, #shown do
        if shown[i] == e then
            table.remove(shown, i)
            break
        end
    end
    local holder = e.bar
    holder:SetScript("OnUpdate", nil)
    holder._inUse = nil
    holder:Hide()
    Reflow(cfg or GetConfig() or {})
end

local function ReleaseAll()
    local cfg = GetConfig() or {}
    for i = #shown, 1, -1 do
        local e = shown[i]
        castGen[e.unit] = (castGen[e.unit] or 0) + 1
        unitEntry[e.unit] = nil
        e.bar:SetScript("OnUpdate", nil)
        e.bar._inUse = nil
        e.bar:Hide()
        shown[i] = nil
    end
    Reflow(cfg)
end

local function SortShown()
    table.sort(shown, function(a, b) return a.startTime < b.startTime end)
end

--------------------------------------------------------------------------------
-- per-cast tick
--------------------------------------------------------------------------------

-- Only the synthetic preview entry computes a fraction by hand (fake times, so
-- plain-number math is always safe). Real casts are driven natively by
-- :SetTimerDuration() in ApplyCast.
local function BarOnUpdate(holder)
    local e = holder._entry
    if not e then return end

    if e.unit == PREVIEW then
        local remain = e.endTime - GetTime()
        if remain <= 0 then
            e.startTime = GetTime()
            e.endTime = GetTime() + 3
            remain = 3
        end
        holder.bar:SetValue(1 - (remain / (e.endTime - e.startTime)))
        holder.timer:SetFormattedText("%.1f", remain)
        return
    end

    -- Only the countdown text is refreshed here, through the duration object's
    -- own accessor - never a raw secret start/end time. GetRemainingDuration()
    -- can itself be secret, but SetFormattedText is a secret-safe sink; what is
    -- NOT safe is branching on it, so there is exactly one fixed format.
    local remaining
    if e.duration and e.duration.GetRemainingDuration then
        remaining = e.duration:GetRemainingDuration()
    end
    if type(remaining) ~= "number" and not IsSecret(remaining) then
        holder.timer:SetText("")
        return
    end
    holder.timer:SetFormattedText("%.1f", remaining)
end

local function PaintTarget(holder, unit, cfg)
    if cfg.showTargetText == false then
        holder.target:SetText("")
        return
    end
    if UnitShouldDisplaySpellTargetName and UnitShouldDisplaySpellTargetName(unit) then
        local targetName = UnitSpellTargetName and UnitSpellTargetName(unit)
        if type(targetName) ~= "nil" then
            holder.target:SetText(targetName) -- may be a secret string; SetText takes it directly

            -- UnitSpellTargetClass is the secret-safe counterpart for the
            -- target's class token, and C_ClassColor.GetClassColor() is a
            -- documented-safe sink for it (the colour object is never secret).
            local color
            if UnitSpellTargetClass and C_ClassColor and C_ClassColor.GetClassColor then
                color = C_ClassColor.GetClassColor(UnitSpellTargetClass(unit))
            end
            if color then
                holder.target:SetTextColor(color.r, color.g, color.b, 1)
            else
                holder.target:SetTextColor(1, 1, 1, 1)
            end
            return
        end
    end
    holder.target:SetText("")
end

-- spellId is normally secret for an enemy nameplate cast; IsSpellImportant still
-- accepts a secret spellId (only inspecting its result is restricted), so the
-- raw return is passed on and fed straight into the colour sink.
local function ClassifyCast(spellId)
    local important
    if spellId ~= nil and C_Spell and C_Spell.IsSpellImportant then
        local ok, imp = pcall(C_Spell.IsSpellImportant, spellId)
        if ok then important = imp end
    end
    return important
end

--------------------------------------------------------------------------------
-- cast lifecycle
--
-- Never do Lua arithmetic on UnitCastingInfo/UnitChannelInfo start/end times:
-- on an enemy nameplate they can be secret-tainted. Progress comes from
-- UnitCastingDuration / UnitChannelDuration / UnitEmpoweredChannelDuration -
-- an opaque duration object handed to the StatusBar's native
-- :SetTimerDuration(). Name and icon are fetched at render time through
-- C_Spell.GetSpellName / GetSpellTexture and passed straight to
-- SetText / SetTexture, which accept secret values. CreateFrame (AcquireBar)
-- and SetSize (StyleBar) are deferred a tick with C_Timer.After so they never
-- run in the same execution as any of those reads.
--------------------------------------------------------------------------------

local function ResolveDuration(unit)
    local duration, isEmpowered
    if UnitEmpoweredChannelDuration then
        duration = UnitEmpoweredChannelDuration(unit, true)
        if duration then isEmpowered = true end
    end
    if not duration and UnitChannelDuration then
        duration = UnitChannelDuration(unit)
    end
    if not duration and UnitCastingDuration then
        duration = UnitCastingDuration(unit)
    end
    return duration, isEmpowered
end

local function ApplyCast(unit, cfg, myGen, isChannel, isEmpowered, important, duration, spellId)
    if castGen[unit] ~= myGen then return end
    if not (active and cfg) then return end

    local e = unitEntry[unit]
    if not e then
        if #shown >= (cfg.num or 5) then return end
        e = { unit = unit, bar = AcquireBar() }
        e.bar._entry = e
        unitEntry[unit] = e
        shown[#shown + 1] = e
    end
    e.important = important
    e.startTime = GetTime() -- clean local timestamp for sort order only
    e.duration = duration

    StyleBar(e.bar, cfg)
    -- spellId ~= nil, never `spellId and ...`: it can be a secret number, and a
    -- truthiness test on one is exactly what the secret-value system blocks.
    if cfg.showIcon ~= false and spellId ~= nil and C_Spell and C_Spell.GetSpellTexture then
        e.bar.icon:SetTexture(C_Spell.GetSpellTexture(spellId))
    end
    if cfg.showSpellName ~= false and spellId ~= nil and C_Spell and C_Spell.GetSpellName then
        e.bar.name:SetText(C_Spell.GetSpellName(spellId))
    else
        e.bar.name:SetText("")
    end
    PaintTarget(e.bar, unit, cfg)

    if duration and e.bar.bar.SetTimerDuration then
        local direction
        if isEmpowered then
            direction = DIR_ELAPSED   -- empowered stages fill forward
        elseif isChannel then
            direction = DIR_REMAINING -- channels drain
        else
            direction = DIR_ELAPSED   -- casts fill up
        end
        e.bar.bar:SetTimerDuration(duration, INTERP_IMMEDIATE, direction)
    else
        e.bar.bar:SetValue(0)
    end
    e.bar:SetScript("OnUpdate", BarOnUpdate)
    e.bar:Show()

    ApplyImportantVisual(e.bar, cfg, important)
    SortShown()
    Reflow(cfg)
end

local function StartCast(unit, cfg, eventSpellId)
    if not (active and cfg) then return end
    if not UnitCanAttack("player", unit) then return end -- unit-vs-unit relationship, never secret

    castGen[unit] = (castGen[unit] or 0) + 1
    local myGen = castGen[unit]

    C_Timer.After(PICKUP_DELAY, function()
        if castGen[unit] ~= myGen then return end
        if not (active and cfg) then return end

        -- type(x) == "nil", never `x ~= nil`: these can return a secret string
        -- and even a nil-comparison on one is a disallowed equality compare.
        -- The extra parens force exactly one value: an inactive unit's
        -- UnitCastingInfo can return ZERO values, and type() with no argument
        -- is an error.
        local isChannel, exists
        if type((UnitCastingInfo(unit))) ~= "nil" then
            isChannel, exists = false, true
        elseif type((UnitChannelInfo(unit))) ~= "nil" then
            isChannel, exists = true, true
        end
        if not exists then
            Release(unit, cfg)
            return
        end

        local spellId = eventSpellId
        if spellId == nil then
            -- No event payload (adopted from an already-casting nameplate):
            -- read it positionally, never combined with name/texture reads.
            if isChannel then
                spellId = select(8, UnitChannelInfo(unit))
            else
                spellId = select(9, UnitCastingInfo(unit))
            end
        end

        local important = ClassifyCast(spellId)
        local duration, isEmpowered = ResolveDuration(unit)

        -- ApplyCast does the actual frame work; it runs on its own clean tick,
        -- never in the execution that just read the cast info above.
        C_Timer.After(0, function()
            if castGen[unit] ~= myGen then return end
            ApplyCast(unit, cfg, myGen, isChannel, isEmpowered, important, duration, spellId)
        end)
    end)
end

--------------------------------------------------------------------------------
-- events
--------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:Hide()

local START_EVENTS = {
    UNIT_SPELLCAST_START = true,
    UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_EMPOWER_START = true,
}
local STOP_EVENTS = {
    UNIT_SPELLCAST_STOP = true,
    UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_FAILED_QUIET = true,
    UNIT_SPELLCAST_INTERRUPTED = true,
    UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_EMPOWER_STOP = true,
}
local UPDATE_EVENTS = {
    UNIT_SPELLCAST_DELAYED = true,
    UNIT_SPELLCAST_CHANNEL_UPDATE = true,
    UNIT_SPELLCAST_EMPOWER_UPDATE = true,
}

local function AdoptPlateCast(unit, cfg)
    local name = UnitCastingInfo(unit)
    if type(name) == "nil" then
        name = UnitChannelInfo(unit)
    end
    if type(name) ~= "nil" then
        StartCast(unit, cfg)
    end
end

eventFrame:SetScript("OnEvent", function(_, event, unit, ...)
    if event == "PLAYER_REGEN_ENABLED" or event == "ENCOUNTER_END" then
        ReleaseAll()
        return
    end

    if not active then return end
    local cfg = GetConfig()
    if not cfg then return end

    if event == "NAME_PLATE_UNIT_ADDED" then
        if type(unit) == "string" then
            plateUnits[unit] = true
            AdoptPlateCast(unit, cfg)
        end
        return
    end
    if event == "NAME_PLATE_UNIT_REMOVED" then
        if type(unit) == "string" then
            plateUnits[unit] = nil
            Release(unit, cfg)
        end
        return
    end

    if not (unit and plateUnits[unit]) then return end

    if START_EVENTS[event] then
        -- Payload after `unit`: (castGUID, spellId, ...) - spellId only.
        local _, spellId = ...
        StartCast(unit, cfg, spellId)
    elseif STOP_EVENTS[event] then
        Release(unit, cfg)
    elseif UPDATE_EVENTS[event] then
        if unitEntry[unit] then
            local _, spellId = ...
            StartCast(unit, cfg, spellId)
        end
    end
end)

local PLATE_EVENTS = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }
local CAST_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_EMPOWER_START",
    "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_EMPOWER_UPDATE",
    "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_FAILED_QUIET",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_EMPOWER_STOP",
}

local function SeedFromLivePlates(cfg)
    wipe(plateUnits)
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local ok, plates = pcall(C_NamePlate.GetNamePlates)
        if ok and type(plates) == "table" then
            for i = 1, #plates do
                local u = plates[i] and plates[i].namePlateUnitToken
                if u then plateUnits[u] = true end
            end
        end
    end
    for unit in pairs(plateUnits) do
        AdoptPlateCast(unit, cfg)
    end
end

local function Activate()
    if active then return end
    local cfg = GetConfig()
    if not cfg then return end
    active = true
    EnsureContainer():Show()
    ResizeContainer(cfg)
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("ENCOUNTER_END")
    for i = 1, #PLATE_EVENTS do eventFrame:RegisterEvent(PLATE_EVENTS[i]) end
    for i = 1, #CAST_EVENTS do eventFrame:RegisterEvent(CAST_EVENTS[i]) end
    SeedFromLivePlates(cfg)
end

local function Deactivate()
    if not active then return end
    active = false
    eventFrame:UnregisterAllEvents()
    ReleaseAll()
    wipe(plateUnits)
    if container and not previewOn and not container.handle:IsShown() then
        container:Hide()
    end
end

local function SyncActive()
    local cfg = GetConfig()
    if not IsEnabled(cfg) then
        Deactivate()
    else
        EnsureContainer()
        ResizeContainer(cfg)
        LoadPosition(cfg)
        if WhereAllows(cfg) then
            if not active then Activate() end
        else
            Deactivate()
        end
    end
    SyncMover()
end

--------------------------------------------------------------------------------
-- settings entry points
--------------------------------------------------------------------------------

function TSB.Refresh()
    SyncActive()
    local cfg = GetConfig()
    if not cfg then return end
    ResizeContainer(cfg)
    for i = 1, #shown do
        StyleBar(shown[i].bar, cfg)
        if shown[i].unit ~= PREVIEW then
            PaintTarget(shown[i].bar, shown[i].unit, cfg)
        end
        ApplyImportantVisual(shown[i].bar, cfg, shown[i].important)
    end
    SortShown()
    Reflow(cfg)
end

-- Settings-page "Preview" button: one fake looping bar plus the drag handle,
-- shown even while the indicator itself is disabled.
function TSB.SetPreview(show)
    local cfg = GetConfig()
    if not cfg then return end
    local c = EnsureContainer()

    if show then
        previewOn = true
        LoadPosition(cfg)
        ResizeContainer(cfg)
        c:Show()

        local e = unitEntry[PREVIEW]
        if not e then
            e = { unit = PREVIEW, bar = AcquireBar() }
            e.bar._entry = e
            unitEntry[PREVIEW] = e
            shown[#shown + 1] = e
        end
        e.important = true
        e.startTime = GetTime()
        e.endTime = GetTime() + 3

        StyleBar(e.bar, cfg)
        if cfg.showIcon ~= false then
            e.bar.icon:SetTexture(134400) -- generic question-mark icon
        end
        e.bar.name:SetText(cfg.showSpellName ~= false and L["Example Cast"] or "")
        if cfg.showTargetText ~= false then
            e.bar.target:SetText(UnitName("player") or "Target")
            e.bar.target:SetTextColor(1, 1, 1, 1)
        else
            e.bar.target:SetText("")
        end
        e.bar.bar:SetMinMaxValues(0, 1)
        e.bar:SetScript("OnUpdate", BarOnUpdate)
        e.bar:Show()
        ApplyImportantVisual(e.bar, cfg, true)
        SortShown()
        Reflow(cfg)
    else
        previewOn = false
        if unitEntry[PREVIEW] then Release(PREVIEW, cfg) end
    end
    SyncActive()
    N:Fire("NUCLEUS_TSB_PREVIEW", previewOn)
end

function TSB.IsPreviewing() return previewOn end

--------------------------------------------------------------------------------
-- wiring
--------------------------------------------------------------------------------

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("GROUP_ROSTER_UPDATE")
watcher:RegisterEvent("PLAYER_ENTERING_WORLD")
watcher:SetScript("OnEvent", function()
    if N.db then SyncActive() end
end)

N:On("NUCLEUS_SETTING_CHANGED", function(_, section, path)
    if section == "targetedSpellBars" or path == "locked" then
        TSB.Refresh()
    end
end)

function TSB.Init()
    SyncActive()
end
