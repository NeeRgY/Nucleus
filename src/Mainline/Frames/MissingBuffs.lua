local _, ns = ...
local N = ns.N
local M = N.Media
local Indicators = N.Indicators
local IsSecret = N.IsSecret

-- Missing Buffs: an icon on a unit's frame for every raid buff it lacks. Standalone, reads the
-- unit's auras itself. A buff only counts as expected when someone in the group can provide it,
-- and only buffs enabled in the settings are checked.
--
-- Midnight can hide spell IDs on other units. If any aura on the unit has a hidden ID the answer
-- is unknown and nothing is shown (better silent than a false "missing"). The scan runs in a
-- timer, never inside the secure header's update, and the result is cached on the button.

local BUFFS = {
    { key = "fortitude", label = "Power Word: Fortitude", class = "PRIEST",  ids = { 21562 } },
    { key = "intellect", label = "Arcane Intellect",      class = "MAGE",    ids = { 1459, 432778 } },
    { key = "wild",      label = "Mark of the Wild",      class = "DRUID",   ids = { 1126, 432661 } },
    { key = "shout",     label = "Battle Shout",          class = "WARRIOR", ids = { 6673 } },
    { key = "skyfury",   label = "Skyfury",               class = "SHAMAN",  ids = { 462854 } },
    { key = "bronze",    label = "Blessing of the Bronze", class = "EVOKER",
      ids = { 381732, 381741, 381746, 381748, 381749, 381750, 381751, 381752, 381753,
              381754, 381756, 381757, 381758 } },
}
Indicators.missingBuffs = BUFFS

local idToKey = {}
for _, buff in ipairs(BUFFS) do
    for _, id in ipairs(buff.ids) do idToKey[id] = buff.key end
end

local MAX_ICONS = #BUFFS

local classCache, classStamp
local function groupClasses()
    local now = GetTime()
    if classCache and classStamp and now - classStamp < 1 then return classCache end
    local set = {}
    local function add(unit)
        if UnitExists(unit) then
            local _, token = UnitClass(unit)
            if token and not IsSecret(token) then set[token] = true end
        end
    end
    add("player")
    if IsInRaid() then
        for i = 1, 40 do add("raid" .. i) end
    elseif IsInGroup() then
        for i = 1, 4 do add("party" .. i) end
    end
    classCache, classStamp = set, now
    return set
end

local textureCache = {}
local function buffTexture(buff)
    local t = textureCache[buff.key]
    if not t then
        t = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(buff.ids[1])
        if t then textureCache[buff.key] = t end
    end
    return t or 134400
end

local function scan(u, o)
    local present, unknown = {}, false
    if not (N.AuraCache and N.AuraCache.Each) then return nil end
    for _, d in ipairs(N.AuraCache.Each(u, "HELPFUL")) do
        local id = d.spellId
        if id == nil or IsSecret(id) then
            unknown = true
        else
            local key = idToKey[id]
            if key then present[key] = true end
        end
    end
    local classes = groupClasses()
    local missing = {}
    for _, buff in ipairs(BUFFS) do
        if o.buffs and o.buffs[buff.key] ~= false and classes[buff.class] and not present[buff.key] then
            missing[#missing + 1] = buff.key
        end
    end
    -- Only trust "missing" when every aura was readable.
    if unknown and #missing > 0 then return nil end
    return missing
end

local function refresh(b)
    if b._mbPending then return end
    b._mbPending = true
    C_Timer.After(0, function()
        b._mbPending = nil
        local o = N.db and N.db[b.groupKey] and N.db[b.groupKey].indicators.missingBuffs
        local missing
        local u = b.unit
        if o and o.enabled and u and UnitExists(u) and not (o.hideInCombat and InCombatLockdown()) then
            local connected, dead = UnitIsConnected(u), UnitIsDeadOrGhost(u)
            if not IsSecret(connected) and connected and not IsSecret(dead) and not dead then
                missing = scan(u, o)
            end
        end
        missing = missing or {}
        local sig = table.concat(missing, ",")
        if sig ~= b._mbSig then
            b._mbSig = sig
            b._mbMissing = missing
            Indicators.UpdateAll(b)
        end
    end)
end

local function makeIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:Hide()
    N.SkinPanel(f, M.color.frameBg, M.color.border, true)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetPoint("TOPLEFT", N.Snap(f, 1), N.Snap(f, -1))
    f.tex:SetPoint("BOTTOMRIGHT", N.Snap(f, -1), N.Snap(f, 1))
    f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return f
end

Indicators.Register("missingBuffs", {
    events = {
        "UNIT_AURA", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED",
        "UNIT_CONNECTION",
    },
    create = function(b)
        local obj = { icons = {} }
        function obj:Hide()
            for _, ic in ipairs(self.icons) do ic:Hide() end
        end
        return obj
    end,
    update = function(b, obj)
        local o = N.db[b.groupKey].indicators.missingBuffs
        local keys
        if b._mock then
            keys = {}
            for _, buff in ipairs(BUFFS) do
                if o.buffs and o.buffs[buff.key] ~= false then keys[#keys + 1] = buff.key end
            end
        else
            refresh(b)
            keys = b._mbMissing or {}
        end

        local byKey = {}
        for _, buff in ipairs(BUFFS) do byKey[buff.key] = buff end

        local size, spacing = o.size or 13, o.spacing or 1
        local point = (o.position or "bottomright"):upper()
        local ax = point:find("LEFT") and 1 or point:find("RIGHT") and -1 or 0
        local ay = point:find("BOTTOM") and 1 or point:find("TOP") and -1 or 0
        for i = 1, MAX_ICONS do
            local ic = obj.icons[i]
            local buff = byKey[keys[i]]
            if buff then
                if not ic then
                    ic = makeIcon(b.overlay or b)
                    obj.icons[i] = ic
                end
                ic:SetSize(size, size)
                ic.tex:SetTexture(buffTexture(buff))
                local off = (i - 1) * (size + spacing)
                local dx, dy = 0, 0
                if o.growth == "RIGHT" then dx = off
                elseif o.growth == "UP" then dy = off
                elseif o.growth == "DOWN" then dy = -off
                else dx = -off end
                ic:ClearAllPoints()
                ic:SetPoint(point, b, point, ax + dx + (o.x or 0), ay + dy + (o.y or 0))
                ic:Show()
            elseif ic then
                ic:Hide()
            end
        end
    end,
})
