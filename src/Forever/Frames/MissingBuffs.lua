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

-- Whether a class is in the group (cached for a second), for the Buff Tracker's "all classes" mode.
local groupCache, groupStamp
local function groupHas(class)
    local now = GetTime()
    if not groupCache or now - (groupStamp or 0) >= 1 then
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
        groupCache, groupStamp = set, now
    end
    return groupCache[class] == true
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

-- Longest time left per buff; a permanent or hidden time counts as not expiring.
local function noteLeft(left, key, d)
    local exp, dur = d.expirationTime, d.duration
    if exp == nil or dur == nil or IsSecret(exp) or IsSecret(dur) or dur <= 0 or exp <= 0 then
        left[key] = math.huge
        return
    end
    local t = exp - GetTime()
    if not left[key] or t > left[key] then left[key] = t end
end

local function scan(u, o)
    local present, unknown = {}, false
    local warn, left = (o.warnMinutes or 0) * 60, {}
    if not (N.AuraCache and N.AuraCache.Each) then return nil end
    for _, d in ipairs(N.AuraCache.Each(u, "HELPFUL")) do
        local id = d.spellId
        if id == nil or IsSecret(id) then
            unknown = true
        else
            local key = idToKey[id]
            if key then
                present[key] = true
                if warn > 0 then noteLeft(left, key, d) end
            end
        end
        local name = d.name
        if type(name) == "string" and not IsSecret(name) then
            local key = names()[name]
            if key then
                present[key] = true
                if warn > 0 then noteLeft(left, key, d) end
            end
        end
    end
    if not (N.AuraCache.Scanned and N.AuraCache.Scanned(u)) then return nil end
    local function up(key)
        return present[key] and not (warn > 0 and left[key] and left[key] < warn)
    end
    local missing, soon = {}, {}
    for _, buff in ipairs(BUFFS) do
        if o.buffs and o.buffs[buff.key] ~= false then
            if buff.key == "blessing" then
                -- missing while none of the enabled blessings is on them (and the player can cast one)
                local wanted, have, can, expSub = false, false, false, false
                for _, sub in ipairs(BLESSINGS) do
                    if o.buffs[sub.key] ~= false then
                        wanted = true
                        if up(sub.key) then have = true elseif present[sub.key] then expSub = true end
                        if canCast(sub) or (o.trackAll and groupHas("PALADIN")) then can = true end
                    end
                end
                if wanted and can and not have then
                    missing[#missing + 1] = buff.key
                    if expSub then soon[buff.key] = true end
                end
            elseif (canCast(buff) or (o.trackAll and groupHas(buff.class))) and not up(buff.key) then
                missing[#missing + 1] = buff.key
                if present[buff.key] then soon[buff.key] = true end
            end
        end
    end
    -- Only trust "missing" when every aura was readable.
    if unknown and #missing > 0 then return nil end
    return missing, soon
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
        local missing, soon
        local u = b.unit
        if o and o.enabled and allowedFor(b, o) and u and UnitExists(u) and not (o.hideInCombat and N.InCombat()) then
            local connected, dead = UnitIsConnected(u), UnitIsDeadOrGhost(u)
            -- Out of sight: the client has no aura data for that member, so nothing is shown.
            local visible = UnitIsVisible(u)
            if not IsSecret(connected) and connected and not IsSecret(dead) and not dead
                and not IsSecret(visible) and visible then
                missing, soon = scan(u, o)
            end
        end
        missing = missing or {}
        local parts = {}
        for i, key in ipairs(missing) do parts[i] = (soon and soon[key]) and (key .. "*") or key end
        local sig = table.concat(parts, ",")
        if sig ~= b._mbSig then
            b._mbSig = sig
            b._mbMissing = missing
            b._mbSoon = soon or {}
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
    return scan(unit, { buffs = buffs, trackAll = trackAll })
end

function Indicators.BuffLabel(buff)
    return (buff.key ~= "blessing" and N.Classic.SpellName(buff.icon)) or N.L[buff.label] or buff.label
end

function Indicators.BuffTexture(buff) return buffTexture(buff) end

-- Whether the player can cast the buff (and has it ticked), so the tracker may follow it.
function Indicators.Trackable(buff, buffs, trackAll)
    if buffs and buffs[buff.key] == false then return false end
    if buff.key == "blessing" then
        for _, sub in ipairs(BLESSINGS) do
            if (not buffs or buffs[sub.key] ~= false) and (canCast(sub) or (trackAll and groupHas("PALADIN"))) then return true end
        end
        return false
    end
    return canCast(buff) or (trackAll and groupHas(buff.class)) or false
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

-- A buff runs out without an aura event, so the frames are judged again every 5 seconds while the warning is on.
local warnTicker
local function startWarnTicker()
    if warnTicker then return end
    warnTicker = C_Timer.NewTicker(5, function()
        local any = false
        N.UnitFrame.ForEachButton(function(b)
            local o = N.db[b.groupKey] and N.db[b.groupKey].indicators.missingBuffs
            if o and o.enabled and (o.warnMinutes or 0) > 0 then
                any = true
                refresh(b)
            end
        end)
        if not any then
            warnTicker:Cancel()
            warnTicker = nil
        end
    end)
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
        local soon = {}
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
            if (o.warnMinutes or 0) > 0 then startWarnTicker() end
            keys = b._mbMissing or {}
            soon = b._mbSoon or {}
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
                local hl, hc, th, dist, speed, len
                if soon[keys[i]] then
                    hl, hc = o.warnHighlight or "border", o.warnColor or { 1, 0.55, 0.1 }
                    th, dist, speed, len = o.warnThickness or 1, o.warnDistance or 0, o.warnSpeed or 0.3, o.warnLength or 4
                else
                    hl, hc = o.highlight or "none", o.highlightColor or { 1, 0.85, 0.1 }
                    th, dist, speed, len = o.highlightThickness or 1, o.highlightDistance or 0, o.highlightSpeed or 0.3, o.highlightLength or 4
                end
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
                if hl == "blink" then
                    if not ic._blink then
                        ic._blink = true
                        ic:SetScript("OnUpdate", function(self)
                            self:SetAlpha(0.3 + 0.7 * math.abs(1 - 2 * (GetTime() % 1)))
                        end)
                    end
                elseif ic._blink then
                    ic._blink = nil
                    ic:SetScript("OnUpdate", nil)
                    ic:SetAlpha(1)
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
