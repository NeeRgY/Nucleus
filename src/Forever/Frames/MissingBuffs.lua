local _, ns = ...
local N = ns.N
local M = N.Media
local Indicators = N.Indicators
local IsSecret = N.IsSecret

-- A hidden aura ID counts as unknown (nothing shown); the scan runs in a timer and is cached.

local BUFFS = N.Classic.BUFFS
Indicators.missingBuffs = BUFFS

-- The single blessings come after the entries, so their IDs map to the blessing, not to "blessing".
local BLESSINGS = N.Classic.BLESSINGS
local ALL = {}
for _, buff in ipairs(BUFFS) do ALL[#ALL + 1] = buff end
for _, sub in ipairs(BLESSINGS) do ALL[#ALL + 1] = sub end

local idToKey = {}
for _, buff in ipairs(ALL) do
    for _, id in ipairs(buff.ids) do idToKey[id] = buff.key end
end

local MAX_ICONS = #BUFFS

-- Only buffs the player can cast (class matches, spellbook has a rank); cached a few seconds.
local _, playerClass = UnitClass("player")
local castCache, castStamp = {}, 0
local function isKnown(id)
    return (_G.IsPlayerSpell and IsPlayerSpell(id))
        or (_G.IsSpellKnown and IsSpellKnown(id))
        or (C_SpellBook and C_SpellBook.IsSpellKnown and C_SpellBook.IsSpellKnown(id))
        or false
end
local function canCast(buff)
    if buff.class ~= playerClass then return false end
    local now = GetTime()
    if now - castStamp > 5 then wipe(castCache); castStamp = now end
    local v = castCache[buff.key]
    if v == nil then
        v = false
        for _, id in ipairs(buff.cast or buff.ids) do
            if isKnown(id) then v = true break end
        end
        castCache[buff.key] = v
    end
    return v
end

-- Names of every rank, so a rank missing from the ID list still counts; built on first use.
local nameToKey
local function names()
    if nameToKey then return nameToKey end
    nameToKey = {}
    for _, buff in ipairs(ALL) do
        for _, id in ipairs(buff.ids) do
            local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
            if name then nameToKey[name] = buff.key end
        end
    end
    return nameToKey
end
local textureCache = {}
local function buffTexture(buff)
    local t = textureCache[buff.key]
    if not t then
        t = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(buff.icon or buff.ids[1])
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
        local name = d.name
        if type(name) == "string" and not IsSecret(name) then
            local key = names()[name]
            if key then present[key] = true end
        end
    end
    if not (N.AuraCache.Scanned and N.AuraCache.Scanned(u)) then return nil end
    local missing = {}
    for _, buff in ipairs(BUFFS) do
        if o.buffs and o.buffs[buff.key] ~= false then
            if buff.key == "blessing" then
                -- missing while none of the enabled blessings is on them (and the player can cast one)
                local wanted, have, can = false, false, false
                for _, sub in ipairs(BLESSINGS) do
                    if o.buffs[sub.key] ~= false then
                        wanted = true
                        if present[sub.key] then have = true end
                        if canCast(sub) then can = true end
                    end
                end
                if wanted and can and not have then missing[#missing + 1] = buff.key end
            elseif canCast(buff) and not present[buff.key] then
                missing[#missing + 1] = buff.key
            end
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
        if o and o.enabled and u and UnitExists(u) and not (o.hideInCombat and N.InCombat()) then
            local connected, dead = UnitIsConnected(u), UnitIsDeadOrGhost(u)
            -- Out of sight: the client has no aura data for that member, so nothing is shown.
            local visible = UnitIsVisible(u)
            if not IsSecret(connected) and connected and not IsSecret(dead) and not dead
                and not IsSecret(visible) and visible then
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
                local on = o.buffs and o.buffs[buff.key] ~= false
                if on and buff.key == "blessing" then
                    on = false
                    for _, sub in ipairs(BLESSINGS) do
                        if o.buffs[sub.key] ~= false then on = true break end
                    end
                end
                if on then keys[#keys + 1] = buff.key end
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
