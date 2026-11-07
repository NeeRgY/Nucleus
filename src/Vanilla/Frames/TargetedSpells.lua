local _, ns = ...
local N = ns.N
local M = N.Media
local Indicators = N.Indicators

-- Casters are the units the client lets us read; the target is their "target", compared by GUID.

local TS = {}
N.TargetedSpells = TS

local MAX_ICONS = 4
local CAST_SETTLE_DELAY = 0.05

local casts = {} -- casts[casterUnit] = { icon, startTime, endTime, name, spellId, guid }

local function isCasterToken(unit)
    if type(unit) ~= "string" then return false end
    return unit == "target" or unit == "focus" or unit:find("^nameplate%d+$") ~= nil
        or unit:find("^boss%d+$") ~= nil or unit:find("^arena%d+$") ~= nil
end

local function hostile(unit)
    if not UnitExists(unit) then return false end
    local can = UnitCanAttack("player", unit)
    return can == true or can == 1
end

local function refreshAll()
    if not (N.UnitFrame and N.UnitFrame.ForEachButton) then return end
    N.UnitFrame.ForEachButton(function(b)
        if b:IsShown() then Indicators.UpdateOne(b, "targetedSpells") end
    end)
end

local function readCast(unit)
    if not hostile(unit) then
        if casts[unit] then casts[unit] = nil; refreshAll() end
        return
    end
    local name, _, texture, startMS, endMS, _, _, _, spellId = UnitCastingInfo(unit)
    local channel = false
    if not name then
        name, _, texture, startMS, endMS, _, _, spellId = UnitChannelInfo(unit)
        channel = true
    end
    local guid = name and UnitExists(unit .. "target") and UnitGUID(unit .. "target") or nil
    if not (name and guid and startMS and endMS) then
        if casts[unit] then casts[unit] = nil; refreshAll() end
        return
    end
    casts[unit] = {
        icon = texture, name = name, spellId = spellId, channel = channel, guid = guid,
        startTime = startMS / 1000, endTime = endMS / 1000,
    }
    refreshAll()
end

local function later(unit)
    C_Timer.After(CAST_SETTLE_DELAY, function() readCast(unit) end)
end

local function clear(unit)
    if casts[unit] then
        casts[unit] = nil
        refreshAll()
    end
end

local watcher = CreateFrame("Frame")
local EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_CHANNEL_STOP",
    "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED", "UNIT_TARGET",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "PLAYER_REGEN_ENABLED",
    "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE",
}
for _, ev in ipairs(EVENTS) do N.SafeRegister(watcher, ev) end

watcher:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_ENTERING_WORLD"
        or event == "GROUP_ROSTER_UPDATE" then
        if next(casts) then wipe(casts); refreshAll() end
        return
    end
    if event == "NAME_PLATE_UNIT_REMOVED" then clear(unit) return end
    if not isCasterToken(unit) then return end

    if event == "NAME_PLATE_UNIT_ADDED" then
        if UnitCastingInfo(unit) or UnitChannelInfo(unit) then later(unit) end
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP"
        or event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        clear(unit)
    elseif event == "UNIT_TARGET" then
        if casts[unit] then later(unit) end
    else
        later(unit)
    end
end)

-- A cast that never got its stop event (the caster went out of range) is dropped when it ends.
local acc = 0
watcher:SetScript("OnUpdate", function(_, dt)
    acc = acc + dt
    if acc < 0.25 or not next(casts) then return end
    acc = 0
    local now, dropped = GetTime(), false
    for unit, c in pairs(casts) do
        if c.endTime < now then casts[unit] = nil; dropped = true end
    end
    if dropped then refreshAll() end
end)

-- Names and IDs of the "only these spells" list.
local listCache = {}
local function parseList(str)
    if not str or str == "" then return nil end
    local set = listCache[str]
    if not set then
        set = {}
        for tok in str:gmatch("%d+") do
            local id = tonumber(tok)
            set[id] = true
            local name = N.Compat.Spell.GetSpellName(id)
            if name then set[name] = true end
        end
        listCache[str] = set
    end
    return set
end

-- The casts aimed at the unit of button b, earliest first. Honours the "only these spells" list.
function TS.CastsOn(b, o)
    local out = {}
    if not (b.unit and UnitExists(b.unit)) then return out end
    local guid = UnitGUID(b.unit)
    local now = GetTime()
    local set = (o and o.showAll == false) and parseList(o.list) or nil
    local onlyListed = o and o.showAll == false
    for _, c in pairs(casts) do
        if c.guid == guid and c.endTime >= now then
            local pass = true
            if onlyListed then
                pass = set ~= nil and (set[c.spellId] or set[c.name]) == true
            end
            if pass then out[#out + 1] = c end
        end
    end
    table.sort(out, function(a, c) return a.startTime < c.startTime end)
    return out
end

-- Sample casts for the test mode and the preview.
local function sampleCasts()
    local now = GetTime()
    local tex = (N.Compat.Spell.GetSpellTexture(133)) or 134400 -- Fireball
    return {
        { icon = tex, name = "", startTime = now - 0.5, endTime = now + 2.5 },
        { icon = (N.Compat.Spell.GetSpellTexture(116)) or 134400, name = "", startTime = now - 0.2, endTime = now + 3 },
    }
end

local function makeIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:Hide()
    N.SkinPanel(f, M.color.frameBg, M.color.border, true)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetPoint("TOPLEFT", N.Snap(f, 1), N.Snap(f, -1))
    f.tex:SetPoint("BOTTOMRIGHT", N.Snap(f, -1), N.Snap(f, 1))
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetPoint("TOPLEFT", N.Snap(f, 1), N.Snap(f, -1))
    f.cd:SetPoint("BOTTOMRIGHT", N.Snap(f, -1), N.Snap(f, 1))
    f.cd:SetDrawEdge(false)
    f.cd:SetHideCountdownNumbers(true)
    return f
end

Indicators.Register("targetedSpells", {
    events = {},
    create = function(b)
        local obj = { icons = {} }
        obj.frame = CreateFrame("Frame", nil, b)
        obj.frame:SetFrameLevel(math.max(0, b.overlay:GetFrameLevel() - 1))
        obj.frame:SetAllPoints(b)
        obj.frame:Hide()
        obj.glow = N.NewGlow(obj.frame, b)
        function obj:Hide()
            for _, ic in ipairs(self.icons) do ic:Hide() end
            self.sig = nil
            self.glow:Hide()
            self.frame:Hide()
        end
        return obj
    end,
    update = function(b, obj)
        local o = N.db[b.groupKey].indicators.targetedSpells
        local list = b._mock and sampleCasts() or TS.CastsOn(b, o)
        local display = o.display or "both"
        local showIcons = display ~= "glow"
        local showGlow = display ~= "icons"

        local n = (showIcons and math.min(#list, o.num or 2, MAX_ICONS)) or 0
        local size, point = o.size or 18, (o.position or "center"):upper()
        local ax = point:find("LEFT") and 1 or point:find("RIGHT") and -1 or 0
        local ay = point:find("BOTTOM") and 1 or point:find("TOP") and -1 or 0
        for i = 1, MAX_ICONS do
            local ic = obj.icons[i]
            local c = list[i]
            if i <= n and c then
                if not ic then
                    ic = makeIcon(b.overlay or b)
                    obj.icons[i] = ic
                end
                ic:SetSize(size, size)
                ic:ClearAllPoints()
                local off = (i - 1) * (size + 1)
                ic:SetPoint(point, b, point, ax + off + (o.x or 0), ay + (o.y or 0))
                ic.tex:SetTexture(c.icon or 134400)
                ic.cd:SetReverse(c.channel == true)
                ic.cd:SetCooldown(c.startTime, math.max(0.1, c.endTime - c.startTime))
                ic:Show()
            elseif ic then
                ic:Hide()
            end
        end

        if showGlow and #list > 0 then
            local col = o.color or { 0.95, 0.95, 0.32 }
            local style = o.glow or "pixel"
            local sig = table.concat({ style, col[1], col[2], col[3], o.offset or 0, o.thickness or 2,
                o.speed or 0.1, o.length or 8, math.floor(b:GetWidth() or 0), math.floor(b:GetHeight() or 0) }, "|")
            if obj.sig ~= sig or not obj.frame:IsShown() then
                obj.sig = sig
                obj.frame:Show()
                obj.glow:Show(style, col[1], col[2], col[3], o.offset or 0, o.thickness or 2,
                    o.speed or 0.1, o.length or 8)
            end
        else
            obj.sig = nil
            obj.glow:Hide()
            obj.frame:Hide()
        end
    end,
})
