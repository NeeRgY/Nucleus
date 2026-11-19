local _, ns = ...
local N = ns.N
local M = N.Media
local Indicators = N.Indicators
local IsSecret = N.IsSecret

-- A hidden aura ID counts as unknown (nothing shown); the scan runs in a timer and is cached.

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

-- Retail buffs are all baseline spells, so the class decides what the player can cast.
local _, playerClass = UnitClass("player")
local function canCast(buff) return buff.class == playerClass end

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
    if not (N.AuraCache.Scanned and N.AuraCache.Scanned(u)) then return nil end
    local classes = groupClasses()
    local missing = {}
    for _, buff in ipairs(BUFFS) do
        if o.buffs and o.buffs[buff.key] ~= false and classes[buff.class] and (not o.castOnly or canCast(buff)) and not present[buff.key] then
            missing[#missing + 1] = buff.key
        end
    end
    -- Only trust "missing" when every aura was readable.
    if unknown and #missing > 0 then return nil end
    return missing
end

local function isOwnFrame(b)
    if b._mock then return b._mock.isSelf == true end
    local u = b.unit
    if not u then return false end
    local same = UnitIsUnit(u, "player")
    return (not IsSecret(same)) and same == true
end

-- "Show for": all frames, only the player's own frame or only the other players.
local function allowedFor(b, o)
    local showFor = o.showFor or "all"
    if showFor == "all" then return true end
    local mine = isOwnFrame(b)
    return (showFor == "self" and mine) or (showFor == "others" and not mine)
end

local function refresh(b)
    if b._mbPending then return end
    b._mbPending = true
    C_Timer.After(0, function()
        b._mbPending = nil
        local o = N.db and N.db[b.groupKey] and N.db[b.groupKey].indicators.missingBuffs
        local missing
        local u = b.unit
        if o and o.enabled and allowedFor(b, o) and u and UnitExists(u) and not (o.hideInCombat and N.InCombat()) then
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

-- Buff Tracker (Tools.lua): the missing buffs of one unit, nil when it cannot be judged.
function Indicators.MissingFor(unit, buffs, trackAll)
    if not (unit and UnitExists(unit)) then return nil end
    local connected, dead, visible = UnitIsConnected(unit), UnitIsDeadOrGhost(unit), UnitIsVisible(unit)
    if IsSecret(connected) or not connected or IsSecret(dead) or dead or IsSecret(visible) or not visible then
        return nil
    end
    return scan(unit, { buffs = buffs, castOnly = not trackAll })
end

function Indicators.BuffLabel(buff)
    return (buff.key ~= "blessing" and N.Classic.SpellName(buff.icon)) or N.L[buff.label] or buff.label
end

function Indicators.BuffTexture(buff) return buffTexture(buff) end

-- Whether the player can cast the buff (and has it ticked), so the tracker may follow it.
function Indicators.Trackable(buff, buffs, trackAll)
    if buffs and buffs[buff.key] == false then return false end
    return canCast(buff) or (trackAll and groupClasses()[buff.class]) or false
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

        if b._mock and not allowedFor(b, o) then keys = {} end

        local byKey = {}
        for _, buff in ipairs(BUFFS) do byKey[buff.key] = buff end

        local own = o.own and o.own.enabled and isOwnFrame(b) and o.own or nil
        local size, spacing = (own and own.size) or o.size or 13, o.spacing or 1
        local point = ((own and own.position) or o.position or "bottomright"):upper()
        local growth = (own and own.growth) or o.growth
        local offX, offY = (own and own.x) or o.x or 0, (own and own.y) or o.y or 0
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
                local hl = o.highlight or "none"
                local hc = o.highlightColor or { 1, 0.85, 0.1 }
                local th = o.highlightThickness or 1
                local dist, speed, len = o.highlightDistance or 0, o.highlightSpeed or 0.3, o.highlightLength or 4
                N.SetPanelBorder(ic, M.color.border)
                -- Border: colored strips along the inside of the icon edge.
                if hl == "border" then
                    local edges = ic._hlEdges
                    if not edges then
                        edges = {}
                        for k = 1, 4 do edges[k] = ic:CreateTexture(nil, "OVERLAY", nil, 6) end
                        ic._hlEdges = edges
                    end
                    local t = N.Snap(ic, th)
                    for k = 1, 4 do
                        edges[k]:SetColorTexture(hc[1], hc[2], hc[3], 1)
                        edges[k]:ClearAllPoints()
                        edges[k]:Show()
                    end
                    edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(t)
                    edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(t)
                    edges[3]:SetPoint("TOPLEFT", 0, -t); edges[3]:SetPoint("BOTTOMLEFT", 0, t); edges[3]:SetWidth(t)
                    edges[4]:SetPoint("TOPRIGHT", 0, -t); edges[4]:SetPoint("BOTTOMRIGHT", 0, t); edges[4]:SetWidth(t)
                elseif ic._hlEdges then
                    for k = 1, 4 do ic._hlEdges[k]:Hide() end
                end
                if hl == "pixel" or hl == "halo" or hl == "pulse" then
                    local newGlow = (N.AuraEngine and N.AuraEngine.NewGlow) or N.NewGlow
                    if newGlow then
                        ic.glow = ic.glow or newGlow(ic, ic)
                        local sig = table.concat({ hl, size, hc[1], hc[2], hc[3], th, dist, speed, len }, "|")
                        if ic._glowSig ~= sig then
                            ic._glowSig = sig
                            ic.glow:Show(hl, hc[1], hc[2], hc[3], dist, th, speed, len)
                        end
                    end
                elseif ic.glow and ic._glowSig then
                    ic._glowSig = nil
                    ic.glow:Hide()
                end
                local off = (i - 1) * (size + spacing)
                local dx, dy = 0, 0
                if growth == "RIGHT" then dx = off
                elseif growth == "UP" then dy = off
                elseif growth == "DOWN" then dy = -off
                else dx = -off end
                ic:ClearAllPoints()
                ic:SetPoint(point, b, point, ax + dx + offX, ay + dy + offY)
                ic:Show()
            elseif ic then
                ic:Hide()
            end
        end
    end,
})
