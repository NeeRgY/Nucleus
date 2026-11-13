local _, ns = ...
local N = ns.N
local M = N.Media

-- Hidden fields: cooldowns run from the duration object, spell IDs are checked with IsSecret.

local A = {}
N.Auras = A

local C_UnitAuras = _G.C_UnitAuras
local DebuffTypeColor = _G.DebuffTypeColor or {}
local IsSecret, AnySecret = N.IsSecret, N.AnySecret

local ROWS = {
    { kind = "buff",      cfg = "buffs",         filter = "HELPFUL" },
    { kind = "debuff",    cfg = "debuffs",       filter = "HARMFUL" },
    { kind = "debuff",    cfg = "debuffs2",      filter = "HARMFUL" },
    { kind = "debuff",    cfg = "debuffs3",      filter = "HARMFUL" },
    { kind = "debuff",    cfg = "debuffs4",      filter = "HARMFUL" },
    { kind = "dispel",    cfg = "dispels",       filter = "HARMFUL", dispellableOnly = true },
    { kind = "defensive", cfg = "defensives",    filter = "HELPFUL", cooldown = true,
      blizz = "HELPFUL|BIG_DEFENSIVE" },
    { kind = "external",  cfg = "externals",     filter = "HELPFUL", cooldown = true,
      blizz = "HELPFUL|EXTERNAL_DEFENSIVE" },
    { kind = "defext",    cfg = "defext",        filter = "HELPFUL", cooldown = true,
      blizz = { "HELPFUL|BIG_DEFENSIVE", "HELPFUL|EXTERNAL_DEFENSIVE|!BIG_DEFENSIVE" } },
    { kind = "offensive", cfg = "offensives",    filter = "HELPFUL", cooldown = true },
    { kind = "crowd",     cfg = "crowdControls", filter = "HARMFUL|CROWD_CONTROL", crowd = true },
}
A.ROWS = ROWS

-- In combat a live scan is refused but lookups by instance ID work: cache from scan + UNIT_AURA.

local AC = {}
N.AuraCache = AC

local cache = {}     -- cache[unit] = { auras = { [auraInstanceID] = auraData }, scanned = bool }
local listeners = {} -- called with (unit) after a unit's cache changed

function AC.OnChange(fn) listeners[#listeners + 1] = fn end

local function scanUnit(unit, e)
    if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
    local found = {}
    for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
        for i = 1, 60 do
            local ok, d = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
            if not ok then return end -- scanning is refused right now
            if not d then break end
            local id = d.auraInstanceID
            if id ~= nil and not IsSecret(id) then found[id] = d end
        end
    end
    e.auras, e.scanned = found, true
end

local function entry(unit)
    local e = cache[unit]
    if not e then
        e = { auras = {}, scanned = false }
        cache[unit] = e
    end
    if not e.scanned and not e.refused then
        scanUnit(unit, e)
        if not e.scanned then e.refused = true end -- try again after combat
    end
    return e
end

-- Auras of `unit` that pass `filter` ("HELPFUL|PLAYER", ...), oldest first.
function AC.Each(unit, filter)
    local out = {}
    if not (unit and C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID) then return out end
    local ids = {}
    for id in pairs(entry(unit).auras) do ids[#ids + 1] = id end
    table.sort(ids)
    local auras = cache[unit].auras
    for _, id in ipairs(ids) do
        local ok, hidden = pcall(C_UnitAuras.IsAuraFilteredOutByInstanceID, unit, id, filter)
        if ok and not hidden then out[#out + 1] = auras[id] end
    end
    return out
end

-- False while the unit's auras could not be read (a refused scan leaves the cache empty).
function AC.Scanned(unit)
    local e = cache[unit]
    return e ~= nil and e.scanned == true
end

local function notify(unit)
    for _, fn in ipairs(listeners) do fn(unit) end
end

local acFrame = CreateFrame("Frame")
acFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
acFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
acFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
-- After combat only units with sealed or incomplete data are rescanned, a few per frame.
local regenQueue = {}
local regenDriver = CreateFrame("Frame")
regenDriver:Hide()
regenDriver:SetScript("OnUpdate", function(self)
    if InCombatLockdown() then
        wipe(regenQueue)
        self:Hide()
        return
    end
    local deadline = debugprofilestop() + 5
    while #regenQueue > 0 do
        local u = table.remove(regenQueue, 1)
        local e = cache[u]
        if e and (e.stale or e.refused or not e.scanned) then
            e.auras, e.scanned, e.refused, e.stale = {}, false, false, nil
            entry(u)
            notify(u)
        end
        if debugprofilestop() > deadline then break end
    end
    if #regenQueue == 0 then self:Hide() end
end)

acFrame:SetScript("OnEvent", function(_, event, unit, info)
    if event == "PLAYER_REGEN_ENABLED" then
        wipe(regenQueue)
        for u, e in pairs(cache) do
            if e.stale or e.refused or not e.scanned then regenQueue[#regenQueue + 1] = u end
        end
        if #regenQueue > 0 then regenDriver:Show() end
        return
    end
    if event ~= "UNIT_AURA" then
        for u, e in pairs(cache) do
            e.auras, e.scanned, e.refused = {}, false, false
            if not InCombatLockdown() then entry(u) end
            notify(u)
        end
        return
    end
    local e = cache[unit]
    if not e then return end
    -- Secret payload in combat: rescan when allowed; a refused scan keeps the cache.
    local sealed = info ~= nil and (IsSecret(info) or IsSecret(info.isFullUpdate)
        or IsSecret(info.addedAuras) or IsSecret(info.updatedAuraInstanceIDs)
        or IsSecret(info.removedAuraInstanceIDs))
    if sealed then
        if InCombatLockdown() then e.stale = true else scanUnit(unit, e) end
    elseif info == nil or info.isFullUpdate then
        e.auras, e.scanned, e.refused = {}, false, false
        entry(unit)
    else
        local inCombat = InCombatLockdown()
        for _, raw in ipairs(info.addedAuras or {}) do
            local id = raw and raw.auraInstanceID
            if id ~= nil and not IsSecret(id) then
                local d = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, id)
                if d then e.auras[id] = d end
            end
            if inCombat then e.stale = true end -- data read in combat may stay sealed
        end
        for _, id in ipairs(info.updatedAuraInstanceIDs or {}) do
            if not IsSecret(id) then
                local d = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, id)
                if d then e.auras[id] = d else e.auras[id] = nil end
            end
            if inCombat then e.stale = true end
        end
        for _, id in ipairs(info.removedAuraInstanceIDs or {}) do
            if not IsSecret(id) then e.auras[id] = nil else e.stale = true end
        end
    end
    notify(unit)
end)

-- Per unit with a frame; the cache of a unit that loses its frame is dropped.
local auraFrames = {}
local function auraWatch(unit)
    local f = auraFrames[unit]
    if not f then
        f = CreateFrame("Frame")
        f:SetScript("OnEvent", acFrame:GetScript("OnEvent"))
        auraFrames[unit] = f
    end
    pcall(f.RegisterUnitEvent, f, "UNIT_AURA", unit)
end
local function auraUnwatch(unit)
    local f = auraFrames[unit]
    if f then f:UnregisterAllEvents() end
    cache[unit] = nil
end
N:On("NUCLEUS_DB_READY", function()
    if CreateFrame("Frame").RegisterUnitEvent and N.UnitFrame and N.UnitFrame.WatchUnits then
        N.UnitFrame.WatchUnits(auraWatch, auraUnwatch)
    else
        acFrame:RegisterEvent("UNIT_AURA")
    end
end)

-- Class dispel capability; class level only, spec nuance is ignored.

local DISPEL_BY_CLASS = N.Classic.DISPEL
local dispelSet
local function dispelTypes()
    if not dispelSet then
        dispelSet = DISPEL_BY_CLASS[select(2, UnitClass("player"))] or {}
    end
    return dispelSet
end

local wlCache = {}
local function parseList(str)
    if not str or str == "" then return nil end
    local set = wlCache[str]
    if not set then
        set = {}
        for tok in str:gmatch("%d+") do set[tonumber(tok)] = true end
        wlCache[str] = set
    end
    return set
end


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

local function makeIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:Hide()

    N.SkinPanel(f, M.color.frameBg, M.color.border, true)

    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", snap(f, 1), snap(f, -1))
    tex:SetPoint("BOTTOMRIGHT", snap(f, -1), snap(f, 1))
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.tex = tex

    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetPoint("TOPLEFT", f, "TOPLEFT", snap(f, 1), snap(f, -1))
    cd:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", snap(f, -1), snap(f, 1))
    cd:SetDrawEdge(false)
    cd:SetHideCountdownNumbers(true)
    cd:SetReverse(true)
    if cd.SetSwipeColor then cd:SetSwipeColor(0, 0, 0, 0.6) end
    f.cd = cd

    local mask = CreateFrame("StatusBar", nil, f)
    mask:SetPoint("TOPLEFT", f, "TOPLEFT", snap(f, 1), snap(f, -1))
    mask:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", snap(f, -1), snap(f, 1))
    mask:SetFrameLevel(cd:GetFrameLevel())
    mask:SetStatusBarTexture(M.flat)
    mask:SetStatusBarColor(0, 0, 0, 0.6)
    mask:SetOrientation("VERTICAL")
    mask:SetReverseFill(true)
    mask:Hide()
    f.mask = mask

    local ov = CreateFrame("Frame", nil, f)
    ov:SetAllPoints(f)
    ov:SetFrameLevel(cd:GetFrameLevel() + 1)
    local count = N.FontString(ov, 10)
    count:SetPoint("BOTTOMRIGHT", 1, -1)
    count:SetJustifyH("RIGHT")
    f.count = count

    return f
end


-- Asks the game's aura filter, so it works even when every aura field is secret.
local function passesFilter(unit, d, filter)
    local fn = C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID
    if not (fn and d.auraInstanceID) then return false end
    local ok, out = pcall(fn, unit, d.auraInstanceID, filter)
    return ok and type(out) == "boolean" and out == false
end

local function isTrue(v) return v ~= nil and not IsSecret(v) and v == true end
local DISPEL_TYPED = { Magic = true, Curse = true, Disease = true, Poison = true, Bleed = true }
local DEBUFF_FILTERS = {
    { key = "nonplayer", test = function(unit, d)
        local v = d.isFromPlayerOrPlayerPet
        if v ~= nil and not IsSecret(v) then return v == false end
        return not passesFilter(unit, d, "HARMFUL|PLAYER")
    end },
    { key = "priority", test = function(_, d) return isTrue(d.isPriorityAura) end },
    { key = "cc", test = function(unit, d) return passesFilter(unit, d, "HARMFUL|CROWD_CONTROL") end },
    { key = "bossaura", test = function(_, d) return isTrue(d.isBossAura) end },
    { key = "roleaura", test = function(_, d) return isTrue(d.isRoleAura) end },
    { key = "raid", test = function(unit, d) return passesFilter(unit, d, "HARMFUL|RAID") end },
    { key = "raidcombat", test = function(unit, d) return passesFilter(unit, d, "HARMFUL|RAID_IN_COMBAT") end },
    { key = "dispellable", test = function(unit, d) return passesFilter(unit, d, "HARMFUL|RAID_PLAYER_DISPELLABLE") end },
    { key = "dispeltyped", test = function(_, d)
        local dn = d.dispelName
        return dn ~= nil and not IsSecret(dn) and DISPEL_TYPED[dn] == true
    end },
}
A.DEBUFF_FILTERS = DEBUFF_FILTERS

-- Hidden on Debuffs rows: rested bonus, and Bloodlust exhaustion unless showSated.
local HIDDEN_ALWAYS = { [1229451] = true }
local HIDDEN_DEBUFFS = {
    [57723] = true, [57724] = true, [80354] = true, [95809] = true,
    [160455] = true, [264689] = true, [390435] = true, [1229451] = true,
}
local function hiddenFor(cfg) return cfg.showSated and HIDDEN_ALWAYS or HIDDEN_DEBUFFS end

-- Who may have cast a debuff on the Debuffs row: "all", "npc", "me" or "others".
local function debuffCastBy(cfg)
    if cfg.castBy then return cfg.castBy end
    return (cfg.onlyNonPlayer ~= false) and "npc" or "all"
end
A.DebuffCastBy = debuffCastBy

local function debuffPasses(unit, d, cfg)
    local sid = d.spellId
    if sid ~= nil and not IsSecret(sid) and hiddenFor(cfg)[sid] then return false end
    local by = debuffCastBy(cfg)
    if (by == "all" or by == "me") and cfg.hideSelf ~= false and UnitIsUnit(unit, "player") then
        local mine = d.isFromPlayerOrPlayerPet
        if mine ~= nil and not IsSecret(mine) and mine == true then return false end
    end
    if by == "npc" then
        if not DEBUFF_FILTERS[1].test(unit, d) then return false end
    elseif by == "me" then
        if not passesFilter(unit, d, "HARMFUL|PLAYER") then return false end
    elseif by == "others" then
        if passesFilter(unit, d, "HARMFUL|PLAYER") then return false end
    end
    if cfg.showAll ~= false then return true end
    local f = cfg.filters
    if type(f) ~= "table" then return false end
    local any, all = false, true
    local picked = 0
    for _, flt in ipairs(DEBUFF_FILTERS) do
        if f[flt.key] then
            picked = picked + 1
            if flt.test(unit, d) then any = true else all = false end
        end
    end
    if picked == 0 then return false end
    if cfg.match == "all" then return all end
    return any
end

local function accept(unit, d, row, cfg, excl)
    if row.kind == "debuff" then return debuffPasses(unit, d, cfg) end
    if excl and row.kind == "buff" then
        local sid = d.spellId
        if sid ~= nil and not IsSecret(sid) and excl[sid] then return false end
    end
    if row.dispellableOnly then
        local dn = d.dispelName
        local mineOnly = cfg.dispellableOnly ~= false
        if dn == nil or IsSecret(dn) then
            return passesFilter(unit, d, mineOnly and "HARMFUL|RAID_PLAYER_DISPELLABLE" or "HARMFUL")
        end
        if not mineOnly then return dn ~= "" end
        return dispelTypes()[dn] == true
    end
    if row.crowd and cfg.dispellableOnly then
        local dn = d.dispelName
        if dn == nil or IsSecret(dn) then return false end
        return dispelTypes()[dn] == true
    end
    if row.cooldown then
        local id = d.spellId
        if id ~= nil and not IsSecret(id) then
            local set = parseList(cfg.list)
            return set ~= nil and set[id] == true
        end
        -- Hidden: Blizzard's own classification, if this row has one and it is on.
        if row.blizz and cfg.useFilter == true then
            if type(row.blizz) == "table" then
                for _, f in ipairs(row.blizz) do
                    if passesFilter(unit, d, f) then return true end
                end
                return false
            end
            return passesFilter(unit, d, row.blizz)
        end
        return false
    end
    if row.kind == "buff" and cfg.useList then
        local id = d.spellId
        if id ~= nil and not IsSecret(id) then
            local set = parseList(cfg.list)
            return set ~= nil and set[id] == true
        end
        -- Hidden ID with "only my auras": the game already limited the list to the player's buffs.
        return cfg.onlyMine == true
    end
    return true
end

local function collect(unit, row, cfg, out, groupKey)
    if not C_UnitAuras then return end
    local filter = row.filter
    if row.kind == "buff" and cfg.onlyMine then filter = filter .. "|PLAYER" end
    local excl = (row.kind == "buff" and groupKey and N.CustomIndicators)
        and N.CustomIndicators.BuffExclusions(groupKey) or nil
    for _, d in ipairs(AC.Each(unit, filter)) do
        if accept(unit, d, row, cfg, excl) then
            out[#out + 1] = d
            if #out >= cfg.max then break end
        end
    end
end

local MOCK_SOURCE = {
    buff = "buffs", dispel = "dispels", debuff = "debuffs", defensive = "defensives",
    external = "externals", offensive = "offensives", crowd = "crowd",
}

local function mockCollect(mock, row, cfg, out)
    local src = mock[MOCK_SOURCE[row.kind] or "debuffs"]
    if row.kind == "defext" then
        src = {}
        for _, key in ipairs({ "defensives", "externals" }) do
            for _, d in ipairs(mock[key] or {}) do src[#src + 1] = d end
        end
    end
    if not src then return end
    local limit = (row.kind == "crowd" or row.kind == "offensive") and 1 or cfg.max
    for i = 1, math.min(#src, limit) do out[#out + 1] = src[i] end
end


local GOLD  = { 1.00, 0.85, 0.00 }
local MINE  = { 0.00, 0.80, 0.00 }
local CROWD = { 0.90, 0.20, 0.20 }

-- Time text: warning color below N seconds, tenths below M; hidden timing uses step curves.
local TEXT_WHITE = { 1, 1, 1 }
local function placeText(fs, icon, point, x, y)
    fs:ClearAllPoints()
    fs:SetPoint(point, icon, point, x, y)
    fs:SetJustifyH(point:find("LEFT") and "LEFT" or point:find("RIGHT") and "RIGHT" or "CENTER")
end

local tracked = setmetatable({}, { __mode = "k" })
local tcCurves = {}

local function curveOf(key, build)
    local cv = tcCurves[key]
    if cv ~= nil then return cv or nil end
    tcCurves[key] = false
    if C_CurveUtil and C_CurveUtil.CreateColorCurve and Enum and Enum.LuaCurveType and CreateColor then
        cv = C_CurveUtil.CreateColorCurve()
        cv:SetType(Enum.LuaCurveType.Step)
        build(cv)
        tcCurves[key] = cv
        return cv
    end
end

local function warnCurve(sec, c, base)
    base = base or TEXT_WHITE
    local key = ("w|%d|%.2f|%.2f|%.2f|%.2f|%.2f|%.2f"):format(sec, c[1], c[2], c[3], base[1], base[2], base[3])
    return curveOf(key, function(cv)
        cv:AddPoint(0, CreateColor(c[1], c[2], c[3], 1))
        cv:AddPoint(sec, CreateColor(base[1], base[2], base[3], 1))
    end)
end

-- alpha 1 below `sec` (the tenths text) or, inverted, alpha 1 above (Blizzard's text)
local function decCurve(sec, invert)
    return curveOf(("d|%.1f|%s"):format(sec, tostring(invert)), function(cv)
        cv:AddPoint(0, CreateColor(1, 1, 1, invert and 0 or 1))
        cv:AddPoint(sec, CreateColor(1, 1, 1, invert and 1 or 0))
    end)
end

local function rgba(color)
    if color and color.GetRGBA then
        local ok, r, g, b, a = pcall(color.GetRGBA, color)
        if ok then return r, g, b, a end
    end
end

local function tickTime(icon)
    local fs = icon._timeFS
    if not fs then return end
    local dfs = icon._decFS
    local dec = icon._tcDec or 0
    local c = icon._tcColor

    if icon._tcExp then
        local left = icon._tcExp - GetTime()
        local base = icon._tcBase or TEXT_WHITE
        local r, g, b = base[1], base[2], base[3]
        if icon._tcOn and left > 0 and left < icon._tcSec then r, g, b = c[1], c[2], c[3] end
        if dec > 0 and dfs and left > 0 and left < dec then
            dfs:SetFormattedText("%.1f", left)
            dfs:SetTextColor(r, g, b, 1)
            dfs:Show()
            fs:SetAlpha(0)
        else
            if dfs then dfs:Hide() end
            fs:SetAlpha(1)
            fs:SetTextColor(r, g, b, 1)
        end
    elseif icon._tcDur then
        local dur = icon._tcDur
        local base = icon._tcBase or TEXT_WHITE
        local r, g, b = base[1], base[2], base[3]
        if icon._tcOn and icon._tcCurve then
            local ok, col = pcall(dur.EvaluateRemainingDuration, dur, icon._tcCurve)
            local rr, gg, bb = rgba(ok and col)
            if rr then r, g, b = rr, gg, bb end
        end
        if dec > 0 and dfs and icon._decOn and icon._decOff and dur.GetRemainingDuration then
            local okA, colA = pcall(dur.EvaluateRemainingDuration, dur, icon._decOn)
            local okB, colB = pcall(dur.EvaluateRemainingDuration, dur, icon._decOff)
            local _, _, _, aOn = rgba(okA and colA)
            local _, _, _, aOff = rgba(okB and colB)
            local okR, rem = pcall(dur.GetRemainingDuration, dur)
            if okR and aOn and aOff then
                dfs:SetFormattedText("%.1f", rem)
                dfs:SetTextColor(r, g, b, aOn)
                dfs:Show()
                fs:SetTextColor(r, g, b, aOff)
                return
            end
        end
        if dfs then dfs:Hide() end
        fs:SetAlpha(1)
        fs:SetTextColor(r, g, b, 1)
    end
end

local tcDriver = CreateFrame("Frame")
local tcAcc = 0
tcDriver:SetScript("OnUpdate", function(_, dt)
    tcAcc = tcAcc + dt
    if tcAcc < 0.1 then return end
    tcAcc = 0
    for icon in pairs(tracked) do
        if icon:IsShown() then
            tickTime(icon)
        else
            tracked[icon] = nil
            if icon._timeFS then
                local bc = icon._tcBase or TEXT_WHITE
                icon._timeFS:SetTextColor(bc[1], bc[2], bc[3], 1)
                icon._timeFS:SetAlpha(1)
            end
            if icon._decFS then icon._decFS:Hide() end
        end
    end
end)

local function groupOf(icon)
    if icon._gk then return icon._gk end
    local p = icon:GetParent()
    p = p and p:GetParent()
    return p and p.groupKey
end

local function untrackTime(icon)
    if not tracked[icon] then return end
    tracked[icon] = nil
    if icon._timeFS then
                local bc = icon._tcBase or TEXT_WHITE
                icon._timeFS:SetTextColor(bc[1], bc[2], bc[3], 1)
                icon._timeFS:SetAlpha(1)
            end
    if icon._decFS then icon._decFS:Hide() end
end

local function setupTimeColor(icon, d, cfg, unit)
    local gk = groupOf(icon)
    local tc = gk and N.db[gk] and N.db[gk].appearance and N.db[gk].appearance.timeColor
    local dec = tc and tc.decimals or 0
    if not (tc and (tc.enabled or dec > 0) and cfg.showTime and icon._timeFS) then
        untrackTime(icon)
        return
    end
    local sec = tc.seconds or 3
    icon._tcOn, icon._tcSec, icon._tcDec = tc.enabled and true or false, sec, dec
    icon._tcColor = tc.color or { 1, 0.15, 0.15 }
    icon._tcExp, icon._tcDur, icon._tcCurve, icon._decOn, icon._decOff = nil, nil, nil, nil, nil

    if dec > 0 then
        if not icon._decFS then
            local host = CreateFrame("Frame", nil, icon)
            host:SetAllPoints(icon)
            host:SetFrameLevel(icon:GetFrameLevel() + 7)
            icon._decFS = N.FontString(host, 10)
            icon._decFS:Hide()
        end
        icon._decFS:SetFont(M.font, cfg.timeSize or 10, "OUTLINE")
        placeText(icon._decFS, icon, cfg.timePoint or "CENTER", cfg.timeX or 0, cfg.timeY or 0)
    elseif icon._decFS then
        icon._decFS:Hide()
    end

    if d.duration and not AnySecret(d.duration, d.expirationTime)
        and d.duration > 0 and d.expirationTime and d.expirationTime > 0 then
        icon._tcExp = d.expirationTime
    elseif unit and d.auraInstanceID and C_UnitAuras and C_UnitAuras.GetAuraDuration then
        local ok, obj = pcall(C_UnitAuras.GetAuraDuration, unit, d.auraInstanceID)
        if ok and obj then
            icon._tcDur = obj
            if tc.enabled then icon._tcCurve = warnCurve(sec, icon._tcColor, icon._tcBase) end
            if dec > 0 then
                icon._decOn = decCurve(dec, false)
                icon._decOff = decCurve(dec, true)
            end
        end
    end
    tracked[icon] = true
    tickTime(icon)
end
-- Font size / position of stacks and countdown (the cooldown's FontString is found among its regions).
local function styleTexts(icon, cfg)
    icon.count:SetFont(M.font, cfg.stackSize or 10, "OUTLINE")
    placeText(icon.count, icon, cfg.stackPoint or "BOTTOMRIGHT", cfg.stackX or 1, cfg.stackY or -1)
    local stackColor = cfg.stackColor or TEXT_WHITE
    icon.count:SetTextColor(stackColor[1], stackColor[2], stackColor[3], 1)
    icon._tcBase = cfg.timeBaseColor or TEXT_WHITE
    if icon._timeFS == nil then
        icon._timeFS = false
        for _, r in ipairs({ icon.cd:GetRegions() }) do
            if r.GetObjectType and r:GetObjectType() == "FontString" then icon._timeFS = r break end
        end
    end
    local fs = icon._timeFS
    if fs then
        fs:SetFont(M.font, cfg.timeSize or 10, "OUTLINE")
        placeText(fs, icon, cfg.timePoint or "CENTER", cfg.timeX or 0, cfg.timeY or 0)
        fs:SetTextColor(icon._tcBase[1], icon._tcBase[2], icon._tcBase[3], 1)
    end
end

local function apply(icon, d, cfg, row, unit)
    styleTexts(icon, cfg)
    icon.tex:SetTexture(d.icon)

    -- Cooldown: numbers when readable, the duration object when hidden.
    local style = N.CooldownStyle(icon._gk, cfg.cdStyle)
    local wantAnim, wantTime = cfg.showCooldown, cfg.showTime
    local active = false
    local mask = icon.mask
    mask:Hide()
    mask:SetScript("OnUpdate", nil)
    if wantAnim or wantTime then
        local readable = d.duration and not AnySecret(d.duration, d.expirationTime)
            and d.duration > 0 and d.expirationTime and d.expirationTime > 0
        local dur
        if readable then
            icon.cd:SetCooldown(d.expirationTime - d.duration, d.duration)
            active = true
        elseif unit and d.auraInstanceID and C_UnitAuras and C_UnitAuras.GetAuraDuration
            and icon.cd.SetCooldownFromDurationObject then
            local ok, obj = pcall(C_UnitAuras.GetAuraDuration, unit, d.auraInstanceID)
            if ok and obj then
                dur = obj
                icon.cd:SetCooldownFromDurationObject(obj)
                active = true
            end
        end
        if active then
            icon.cd:SetDrawSwipe((wantAnim and style == "spiral") and true or false)
            icon.cd:SetHideCountdownNumbers(not wantTime)
            if wantAnim and style == "vertical" then
                if readable then
                    local start, total = d.expirationTime - d.duration, d.duration
                    mask:SetMinMaxValues(0, total)
                    mask:SetValue(math.min(total, math.max(0, GetTime() - start)))
                    mask:SetScript("OnUpdate", function(m)
                        m:SetValue(math.min(total, math.max(0, GetTime() - start)))
                    end)
                    mask:Show()
                elseif dur and mask.SetTimerDuration then
                    local interp = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
                    local dir = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.ElapsedTime
                    if pcall(mask.SetTimerDuration, mask, dur, interp, dir) then mask:Show() end
                end
            end
        end
    end
    if active then
        icon.cd:Show()
    else
        if icon.cd.Clear then icon.cd:Clear() end
        icon.cd:Hide()
    end

    local c = d.applications
    if not cfg.showStacks then
        icon.count:SetText("")
    elseif IsSecret(c) then
        icon.count:SetFormattedText("%d", c)
    elseif type(c) == "number" and c > 1 then
        icon.count:SetText(c)
    else
        icon.count:SetText("")
    end

    if row.cooldown then
        local mine
        local src = d.sourceUnit
        if src ~= nil and not IsSecret(src) then
            mine = (src == "player" or src == "pet")
        else
            mine = unit and passesFilter(unit, d, "HELPFUL|PLAYER")
        end
        local col = mine and MINE or GOLD
        N.SetPanelBorder(icon, { col[1], col[2], col[3], 1 })
    elseif row.crowd then
        local dn = d.dispelName
        local col = (dn ~= nil and dn ~= "" and not IsSecret(dn)) and DebuffTypeColor[dn] or nil
        if col then
            N.SetPanelBorder(icon, { col.r, col.g, col.b, 1 })
        else
            N.SetPanelBorder(icon, { CROWD[1], CROWD[2], CROWD[3], 1 })
        end
    else
        local colorByType = row.kind ~= "buff" and cfg.dispelBorder ~= false
            and (cfg.dispelBorder or row.kind == "dispel")
        if colorByType then
            local dn = d.dispelName
            local col = (dn ~= nil and dn ~= "" and not IsSecret(dn)) and DebuffTypeColor[dn] or nil
            if col then
                N.SetPanelBorder(icon, { col.r, col.g, col.b, 1 })
            else
                N.SetPanelBorder(icon, M.color.border)
            end
        else
            N.SetPanelBorder(icon, M.color.border)
        end
    end

    setupTimeColor(icon, d, cfg, unit)

    icon:Show()
end

local function edgeSign(point)
    local ax = point:find("LEFT") and 1 or point:find("RIGHT") and -1 or 0
    local ay = point:find("BOTTOM") and 1 or point:find("TOP") and -1 or 0
    return ax, ay
end


local DISPEL_ATLAS = {
    Magic = "RaidFrame-Icon-DebuffMagic", Curse = "RaidFrame-Icon-DebuffCurse",
    Disease = "RaidFrame-Icon-DebuffDisease", Poison = "RaidFrame-Icon-DebuffPoison",
    Bleed = "RaidFrame-Icon-DebuffBleed",
}
local TYPE_IDX = { Magic = 1, Curse = 2, Disease = 3, Poison = 4, Bleed = 11 }
local TYPE_FALLBACK = { Magic = { 0.2, 0.6, 1 }, Curse = { 0.6, 0, 1 }, Disease = { 0.6, 0.4, 0 },
                        Poison = { 0, 0.6, 0 }, Bleed = { 1, 0.2, 0.6 } }

local colorCurve
local function typeCurve()
    if colorCurve == nil then
        colorCurve = false
        if C_CurveUtil and C_CurveUtil.CreateColorCurve and Enum and Enum.LuaCurveType then
            local c = C_CurveUtil.CreateColorCurve()
            c:SetType(Enum.LuaCurveType.Step)
            c:AddPoint(0, CreateColor(1, 1, 1, 1))
            for name, idx in pairs(TYPE_IDX) do
                local col = DebuffTypeColor[name]
                local rgb = col and { col.r, col.g, col.b } or TYPE_FALLBACK[name]
                c:AddPoint(idx, CreateColor(rgb[1], rgb[2], rgb[3], 1))
            end
            colorCurve = c
        end
    end
    return colorCurve
end

local function typeColorOf(cfg, name)
    local own = cfg and type(cfg.typeColors) == "table" and cfg.typeColors[name]
    if type(own) == "table" and own[1] then return own end
    local col = DebuffTypeColor[name]
    return col and { col.r, col.g, col.b } or TYPE_FALLBACK[name]
end

local function typeRGB(unit, d, cfg)
    local dn = d.dispelName
    if dn ~= nil and dn ~= "" and not IsSecret(dn) then
        local own = typeColorOf(cfg, dn)
        if own then return own[1], own[2], own[3] end
        local col = DebuffTypeColor[dn]
        if col then return col.r, col.g, col.b end
        local fb = TYPE_FALLBACK[dn]
        if fb then return fb[1], fb[2], fb[3] end
        return 1, 1, 1
    end
    local curve = typeCurve()
    if curve and unit and d.auraInstanceID and C_UnitAuras.GetAuraDispelTypeColor then
        local ok, c = pcall(C_UnitAuras.GetAuraDispelTypeColor, unit, d.auraInstanceID, curve)
        if ok and c then return c:GetRGBA() end
    end
    return 1, 1, 1
end

local function buildFX(b)
    local fx = { icons = {}, bord = {} }
    local ov = b.overlay
    fx.hl = ov:CreateTexture(nil, "ARTWORK", nil, 6)
    fx.hl:SetTexture(M.flat)
    fx.edge = ov:CreateTexture(nil, "ARTWORK", nil, 6)
    fx.edge:SetTexture(M.flat)
    for i = 1, 4 do
        local t = ov:CreateTexture(nil, "ARTWORK", nil, 7)
        t:SetTexture(M.flat)
        fx.bord[i] = t
    end
    for i = 1, 5 do
        local t = ov:CreateTexture(nil, "OVERLAY", nil, 3)
        t:Hide()
        fx.icons[i] = t
    end
    b._nucDispelFX = fx
    return fx
end

local function hideFX(b)
    local fx = b._nucDispelFX
    if not fx then return end
    fx.hl:Hide()
    fx.edge:Hide()
    for _, t in ipairs(fx.bord) do t:Hide() end
    for _, t in ipairs(fx.icons) do t:Hide() end
end

local function updateFX(b, cfg, list, unit)
    if not b.overlay or not b.health then return end
    if not (cfg.enabled or b._previewOnly == "dispels") or #list == 0 then hideFX(b) return end
    local fx = b._nucDispelFX or buildFX(b)
    local r, g, bl = typeRGB(unit, list[1], cfg)
    local health = b.health

    local ht = cfg.highlightType or "edge-bottom"
    local op = (cfg.highlightOpacity or 50) / 100
    fx.hl:Hide()
    fx.edge:Hide()
    if ht == "edge-top" or ht == "edge-bottom" then
        fx.edge:ClearAllPoints()
        if ht == "edge-top" then
            fx.edge:SetPoint("TOPLEFT", health, "TOPLEFT")
            fx.edge:SetPoint("BOTTOMRIGHT", health, "RIGHT")
        else
            fx.edge:SetPoint("TOPLEFT", health, "LEFT")
            fx.edge:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT")
        end
        fx.edge:SetVertexColor(1, 1, 1, 1)
        local strong, none = CreateColor(r, g, bl, 0.8), CreateColor(r, g, bl, 0)
        local ok
        if ht == "edge-top" then
            ok = pcall(fx.edge.SetGradient, fx.edge, "VERTICAL", none, strong)
        else
            ok = pcall(fx.edge.SetGradient, fx.edge, "VERTICAL", strong, none)
        end
        if ok then fx.edge:Show() end
    elseif ht == "fill" or ht == "full" then
        fx.hl:ClearAllPoints()
        if ht == "fill" then
            fx.hl:SetPoint("TOPLEFT", health, "TOPLEFT")
            fx.hl:SetPoint("BOTTOMRIGHT", health:GetStatusBarTexture() or health, "BOTTOMRIGHT")
        else
            fx.hl:SetAllPoints(b)
            op = math.max(op, 0.1)
        end
        fx.hl:SetVertexColor(r, g, bl, op)
        fx.hl:Show()
    end

    local th = N.Snap(b, cfg.frameBorderThickness or 2)
    local top, bottom, left, right = fx.bord[1], fx.bord[2], fx.bord[3], fx.bord[4]
    if cfg.frameBorder then
        for i = 1, 4 do fx.bord[i]:SetVertexColor(r, g, bl, 1) fx.bord[i]:Show() end
        top:ClearAllPoints()
        top:SetPoint("TOPLEFT", health, "TOPLEFT")
        top:SetPoint("TOPRIGHT", health, "TOPRIGHT")
        top:SetHeight(th)
        bottom:ClearAllPoints()
        bottom:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT")
        bottom:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT")
        bottom:SetHeight(th)
        left:ClearAllPoints()
        left:SetPoint("TOPLEFT", health, "TOPLEFT", 0, -th)
        left:SetPoint("BOTTOMLEFT", health, "BOTTOMLEFT", 0, th)
        left:SetWidth(th)
        right:ClearAllPoints()
        right:SetPoint("TOPRIGHT", health, "TOPRIGHT", 0, -th)
        right:SetPoint("BOTTOMRIGHT", health, "BOTTOMRIGHT", 0, th)
        right:SetWidth(th)
    else
        for i = 1, 4 do fx.bord[i]:Hide() end
    end

    -- One dispel icon per readable type, or one tinted square when the type is hidden.
    for _, t in ipairs(fx.icons) do t:Hide() end
    if cfg.typeIcons ~= false then
        local shown, seen = 0, {}
        local size = cfg.typeIconSize or 12
        local point = cfg.typeIconPoint or "BOTTOMRIGHT"
        local ax, ay = edgeSign(point)
        if point:find("BOTTOM") then ay = ay + N.PowerInset(b) end
        local growth = cfg.typeIconGrowth or "LEFT"
        local function place(t)
            shown = shown + 1
            local off = (shown - 1) * (size + 1)
            local dx, dy = 0, 0
            if growth == "RIGHT" then dx = off elseif growth == "LEFT" then dx = -off
            elseif growth == "UP" then dy = off else dy = -off end
            t:SetSize(size, size)
            t:ClearAllPoints()
            t:SetPoint(point, b, point, ax + dx + (cfg.typeIconX or 0), ay + dy + (cfg.typeIconY or 4))
            t:Show()
        end
        for _, d in ipairs(list) do
            local dn = d.dispelName
            if shown >= 5 then break end
            local t = fx.icons[shown + 1]
            if dn ~= nil and dn ~= "" and not IsSecret(dn) then
                if not seen[dn] then
                    seen[dn] = true
                    local atlas = DISPEL_ATLAS[dn]
                    t:SetTexCoord(0, 1, 0, 1)
                    if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
                        t:SetAtlas(atlas)
                        t:SetVertexColor(1, 1, 1, 1)
                    elseif dn == "Bleed" then
                        -- No dispel-type symbol exists for bleeds, so Rupture's icon stands in.
                        t:SetTexture(132302)
                        t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                        t:SetVertexColor(1, 1, 1, 1)
                    else
                        local cr, cg, cb = typeRGB(unit, d, cfg)
                        t:SetTexture(M.flat)
                        t:SetVertexColor(cr, cg, cb, 1)
                    end
                    place(t)
                end
            elseif not seen._hidden then
                seen._hidden = true
                local cr, cg, cb = typeRGB(unit, d, cfg)
                t:SetTexture(M.flat)
                t:SetVertexColor(cr, cg, cb, 1)
                place(t)
            end
        end
    end
end

-- Engine rows: each row is one game aura container (AuraEngine.lua); this part says what it shows.

local DEBUFF_CLASSES = {
    { key = "nonplayer",   cand = { isFromPlayerOrPlayerPet = false } },
    { key = "priority",    cand = { isPriorityAura = true } },
    { key = "cc",          token = "CROWD_CONTROL" },
    { key = "bossaura",    cand = { isBossAura = true } },
    { key = "roleaura",    cand = { isRoleAura = true } },
    { key = "raid",        token = "RAID" },
    { key = "raidcombat",  token = "RAID_IN_COMBAT" },
    { key = "dispellable", token = "RAID_PLAYER_DISPELLABLE" },
    { key = "dispeltyped", cand = { includeDispelTypes = { Magic = true, Curse = true, Disease = true, Poison = true, Bleed = true } } },
}

local function copy(t)
    local o = {}
    for k, v in pairs(t or {}) do o[k] = v end
    return o
end

-- Debuff groups: one for everything; "any" one per ticked filter, "all" one satisfying all.
local function debuffGroupsRaw(cfg, exclude)
    local function cand(extra)
        local c = copy(extra)
        if debuffCastBy(cfg) == "npc" then c.isFromPlayerOrPlayerPet = false end
        if exclude then c.excludeSpellIDs = exclude end
        return next(c) and c or nil
    end
    if cfg.showAll ~= false then
        return { { key = "deb", filter = "HARMFUL", candidate = cand(), max = cfg.max, border = false } }
    end
    local f = cfg.filters or {}
    local active = {}
    for _, cl in ipairs(DEBUFF_CLASSES) do
        if f[cl.key] then active[#active + 1] = cl end
    end
    if #active == 0 then return {} end
    if cfg.match == "all" then
        local tokens, extra = { "HARMFUL" }, {}
        for _, cl in ipairs(active) do
            if cl.token then tokens[#tokens + 1] = cl.token end
            for k, v in pairs(cl.cand or {}) do extra[k] = v end
        end
        return { { key = "deb_all", filter = table.concat(tokens, "|"), candidate = cand(extra), max = cfg.max } }
    end
    local groups, negTokens, negCand = {}, {}, nil
    for _, cl in ipairs(active) do
        local extra = copy(negCand)
        if cl.token then
            local tokens = { "HARMFUL", cl.token }
            for _, t in ipairs(negTokens) do tokens[#tokens + 1] = t end
            groups[#groups + 1] = { key = "deb_" .. cl.key, filter = table.concat(tokens, "|"), candidate = cand(extra), max = cfg.max }
            negTokens[#negTokens + 1] = "!" .. cl.token
        else
            for k, v in pairs(cl.cand) do extra[k] = v end
            groups[#groups + 1] = { key = "deb_" .. cl.key, filter = "HARMFUL", candidate = cand(extra), max = cfg.max }
            negCand = negCand or {}
            if cl.cand.includeDispelTypes then negCand.excludeDispelTypes = cl.cand.includeDispelTypes
            else
                for k, v in pairs(cl.cand) do
                    if type(v) == "boolean" then negCand[k] = not v end
                end
            end
        end
    end
    return groups
end

local DISPEL_ORDER = { "Magic", "Curse", "Disease", "Poison", "Bleed" }

local function debuffGroups(cfg, exclude, hideSelf)
    local by = debuffCastBy(cfg)
    -- On your own frame with Cast by: Me every debuff is yours, so the row stays empty.
    if hideSelf and by == "me" then return {} end
    local groups = debuffGroupsRaw(cfg, exclude)
    local token = (by == "me" and "PLAYER") or (by == "others" and "!PLAYER")
        or (hideSelf and by == "all" and "!PLAYER") or nil
    if token then
        for _, g in ipairs(groups) do g.filter = g.filter .. "|" .. token end
    end
    return groups
end

local function isSelfFrame(b)
    if not b.unit then return false end
    local same = UnitIsUnit(b.unit, "player")
    return not IsSecret(same) and same == true
end

local function rowSpec(b, row, cfg)
    if not cfg.enabled then return nil end
    local appearance = N.db[b.groupKey].appearance
    local spec = {
        shape = "icon", size = cfg.size, spacing = cfg.spacing, point = cfg.point, x = cfg.x, y = cfg.y,
        growth = cfg.growth, max = cfg.max, perRow = cfg.perRow, lineSpacing = cfg.lineSpacing,
        cd = cfg.showCooldown and N.CooldownStyle(b.groupKey, cfg.cdStyle) or "none",
        stacks = cfg.showStacks, time = cfg.showTime,
        timeSize = cfg.timeSize, timeX = cfg.timeX, timeY = cfg.timeY,
        stackSize = cfg.stackSize, stackX = cfg.stackX, stackY = cfg.stackY,
        stackPoint = cfg.stackPoint, stackColor = cfg.stackColor,
        timePoint = cfg.timePoint, timeBaseColor = cfg.timeBaseColor,
        timeColor = appearance and appearance.timeColor,
        groups = {},
    }
    local excl = (row.kind == "buff" and N.CustomIndicators) and N.CustomIndicators.BuffExclusions(b.groupKey) or nil

    if row.kind == "buff" then
        local filter = cfg.onlyMine and "HELPFUL|PLAYER" or "HELPFUL"
        local cand = {}
        if cfg.useList then
            local set = parseList(cfg.list)
            if not (set and next(set)) then return nil end
            cand.includeSpellIDs = set
        end
        if excl then cand.excludeSpellIDs = excl end
        spec.groups[1] = { key = "buff", filter = filter, candidate = cand, max = cfg.max }
    elseif row.kind == "debuff" then
        spec.dispelBorder = cfg.dispelBorder ~= false
        spec.groups = debuffGroups(cfg, hiddenFor(cfg), cfg.hideSelf ~= false and isSelfFrame(b))
    elseif row.kind == "crowd" then
        spec.dispelBorder = false
        spec.groups[1] = { key = "cc", filter = "HARMFUL|CROWD_CONTROL", max = cfg.max, border = CROWD }
    elseif row.kind == "dispel" then
        spec.shape = "dispel"
        local showIcons = cfg.showIcons ~= false and cfg.showIcons == true
        spec.dispel = {
            highlight = cfg.highlightType or "edge-bottom", opacity = cfg.highlightOpacity or 50,
            frameBorder = cfg.frameBorder, frameBorderThickness = cfg.frameBorderThickness or 2,
            showIcons = showIcons, typeIcons = cfg.typeIcons ~= false, typeIconSize = cfg.typeIconSize or 12,
        }
        if not showIcons then
            spec.size, spec.spacing = cfg.typeIconSize or 12, 1
            spec.point, spec.x, spec.y = cfg.typeIconPoint or "BOTTOMRIGHT", cfg.typeIconX or 0, cfg.typeIconY or 4
            spec.growth = cfg.typeIconGrowth or "LEFT"
        end
        spec.max = #DISPEL_ORDER
        local mineOnly = cfg.dispellableOnly ~= false
        local filter = mineOnly and "HARMFUL|RAID_PLAYER_DISPELLABLE" or "HARMFUL"
        for _, token in ipairs(DISPEL_ORDER) do
            if not mineOnly or dispelTypes()[token] then
                local rgb = typeColorOf(cfg, token)
                spec.groups[#spec.groups + 1] = {
                    key = "dis_" .. token:lower() .. (mineOnly and "" or "_all"), filter = filter,
                    candidate = { includeDispelTypes = { [token] = true } }, max = 1, token = token,
                    rgb = rgb, atlas = DISPEL_ATLAS[token],
                }
            end
        end
        if #spec.groups == 0 then return nil end
    else
        local set = parseList(cfg.list)
        local hasList = set and next(set)
        local function pair(key, filter, cand)
            spec.groups[#spec.groups + 1] = { key = key .. "_me", filter = filter .. "|PLAYER", candidate = cand, max = cfg.max, border = MINE }
            spec.groups[#spec.groups + 1] = { key = key .. "_ot", filter = filter .. "|!PLAYER", candidate = cand, max = cfg.max, border = GOLD }
        end
        if hasList then pair("list", "HELPFUL", { includeSpellIDs = set }) end
        if row.blizz and cfg.useFilter ~= false then
            local filters = type(row.blizz) == "table" and row.blizz or { row.blizz }
            for i, f in ipairs(filters) do
                pair(i == 1 and "blizz" or ("blizz" .. i), f, hasList and { excludeSpellIDs = set } or nil)
            end
        end
    end
    if #spec.groups == 0 then return nil end
    if cfg.glow == "icon" and spec.shape == "icon" then
        spec.iconGlow = { style = cfg.glowStyle or "pixel", color = cfg.glowColor or { 1, 0.85, 0.2 },
            speed = cfg.glowSpeed or 0.15, length = cfg.glowLength or 6, thickness = cfg.glowThickness or 2,
            offset = cfg.glowOffset or 0 }
    end
    return spec
end

-- Around the unit frame: the same groups as a frame-wide glow.
local function frameGlowSpec(spec, cfg)
    local groups = {}
    for i, g in ipairs(spec.groups) do
        groups[i] = { key = g.key, filter = g.filter, candidate = g.candidate, max = 1 }
    end
    return {
        shape = "glow", point = "CENTER", x = 0, y = 0, size = 1, spacing = 0, max = 1,
        color = cfg.glowColor or { 1, 0.85, 0.2 }, glow = cfg.glowStyle or "pixel",
        offset = cfg.glowOffset or 0, thickness = cfg.glowThickness or 2, speed = cfg.glowSpeed or 0.15,
        length = cfg.glowLength or 6, cd = "none", groups = groups,
    }
end

local function engineOn(b)
    if b._mock or not N.AuraEngine then return false end
    return N.AuraEngine.Supported()
end

local function syncEngine(b)
    local E = N.AuraEngine
    local live = b.unit and UnitExists(b.unit)
    for _, row in ipairs(ROWS) do
        local cfg = N.db[b.groupKey].auras[row.cfg]
        local spec
        if live and not (b._previewOnly and b._previewOnly ~= row.cfg) then spec = rowSpec(b, row, cfg) end
        E.Apply(b, "row:" .. row.cfg, spec)
        E.Apply(b, "row:" .. row.cfg .. "#glow", (spec and cfg.glow == "frame") and frameGlowSpec(spec, cfg) or nil)
    end
    b._engineSynced = true
    b._engineLive = live and true or false
    b._engineSelf = isSelfFrame(b)
end

local function placeSlot(b, cfg, ic, i, n)
    local ax, ay = edgeSign(cfg.point)
    if cfg.point:find("BOTTOM") then ay = ay + N.PowerInset(b) end
    local dx, dy = A.SlotOffset(i, cfg.size, cfg.spacing, cfg.lineSpacing, cfg.perRow, cfg.growth, cfg.point, n)
    ic:ClearAllPoints()
    ic:SetPoint(cfg.point, b, cfg.point, ax + dx + (cfg.x or 0), ay + dy + (cfg.y or 0))
end

function A.Layout(b)
    if not b._nucAuras then return end
    if engineOn(b) then
        syncEngine(b)
        A.BindPrivate(b)
        return
    end
    for _, row in ipairs(ROWS) do
        local cfg = N.db[b.groupKey].auras[row.cfg]
        local pool = b._nucAuras[row.cfg]
        if not pool then pool = {}; b._nucAuras[row.cfg] = pool end
        pool._cenN = nil
        for i = 1, cfg.max do
            local ic = pool[i]
            if not ic then
                ic = makeIcon(b.overlay)
                pool[i] = ic
            end
            ic:SetSize(cfg.size, cfg.size)
            styleTexts(ic, cfg)
            placeSlot(b, cfg, ic, i, cfg.max)
        end
        for i = cfg.max + 1, #pool do pool[i]:Hide() end
    end
    A.BindPrivate(b)
    A.Update(b)
end

function A.Update(b)
    if not b._nucAuras then return end
    if engineOn(b) then
        local live = (b.unit and UnitExists(b.unit)) and true or false
        if not b._engineSynced or b._engineLive ~= live or b._engineSelf ~= isSelfFrame(b) then syncEngine(b) else N.AuraEngine.Rebind(b) end
        return
    end
    local live = b._mock or (b.unit and UnitExists(b.unit))

    for _, row in ipairs(ROWS) do
        local cfg = N.db[b.groupKey].auras[row.cfg]
        local pool = b._nucAuras[row.cfg] or {}

        if (b._previewOnly and b._previewOnly ~= row.cfg) or not live or not (cfg.enabled or b._previewOnly == row.cfg) then
            for _, ic in ipairs(pool) do ic:Hide() end
            if row.kind == "dispel" then hideFX(b) end
        else
            local list = {}
            if b._mock then
                mockCollect(b._mock, row, cfg, list)
            else
                collect(b.unit, row, cfg, list, b.groupKey)
            end
            if cfg.growth == "CENTER" then
                local n = math.min(#list, cfg.max)
                if pool._cenN ~= n then
                    pool._cenN = n
                    for i = 1, cfg.max do
                        if pool[i] then placeSlot(b, cfg, pool[i], i, n) end
                    end
                end
            end
            local iconsOn = not (row.kind == "dispel" and cfg.showIcons == false)
            for i = 1, cfg.max do
                local ic = pool[i]
                if ic then
                    if iconsOn and list[i] then ic._gk = b.groupKey; apply(ic, list[i], cfg, row, b.unit) else ic:Hide() end
                end
            end
            if row.kind == "dispel" then updateFX(b, cfg, list, b.unit) end
        end
    end
end

A.MakeIcon = makeIcon
A.ApplyAura = apply
function A.SlotOffset(i, size, spacing, lineSpacing, perRow, growth, point, count)
    local idx = i - 1
    if growth == "CENTER" then
        local per = math.max(1, math.floor(perRow or 99))
        local col, line = idx % per, math.floor(idx / per)
        local inLine = math.max(1, math.min(per, (count or per) - line * per))
        local dx = (col - (inLine - 1) / 2) * (size + spacing)
        local dy = line * (size + (lineSpacing or spacing))
        if not (point and point:find("BOTTOM")) then dy = -dy end
        return dx, dy
    end
    if growth == "UP" then return 0, idx * (size + spacing) end
    if growth == "DOWN" then return 0, -idx * (size + spacing) end
    local per = math.max(1, math.floor(perRow or 99))
    local col, line = idx % per, math.floor(idx / per)
    local dx = col * (size + spacing)
    if growth == "LEFT" then dx = -dx end
    local dy = line * (size + (lineSpacing or spacing))
    if not (point and point:find("BOTTOM")) then dy = -dy end
    return dx, dy
end

A.EdgeSign = edgeSign

-- Feeds a status bar from an aura's timing (remaining or elapsed); returns true while it runs.
function A.TimerBar(bar, d, unit, remaining)
    bar:SetScript("OnUpdate", nil)
    local readable = d.duration and not AnySecret(d.duration, d.expirationTime)
        and d.duration > 0 and d.expirationTime and d.expirationTime > 0
    if readable then
        local start, total = d.expirationTime - d.duration, d.duration
        bar:SetMinMaxValues(0, total)
        local function set(m)
            local el = math.min(total, math.max(0, GetTime() - start))
            m:SetValue(remaining and (total - el) or el)
        end
        set(bar)
        bar:SetScript("OnUpdate", set)
        return true
    end
    if unit and d.auraInstanceID and C_UnitAuras and C_UnitAuras.GetAuraDuration and bar.SetTimerDuration then
        local ok, obj = pcall(C_UnitAuras.GetAuraDuration, unit, d.auraInstanceID)
        if ok and obj then
            local interp = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate
            local dirs = Enum and Enum.StatusBarTimerDirection
            local dir = dirs and (remaining and dirs.RemainingTime or dirs.ElapsedTime)
            return pcall(bar.SetTimerDuration, bar, obj, interp, dir) and true or false
        end
    end
    return false
end

function A.Create(b)
    if b._nucAuras then return end
    b._nucAuras = {}
    for _, row in ipairs(ROWS) do b._nucAuras[row.cfg] = {} end
end

-- Private auras: up to 5 Blizzard anchors, re-created on roster / zone / settings changes.

local addAnchor = C_UnitAuras and C_UnitAuras.AddPrivateAuraAnchor
local removeAnchor = C_UnitAuras and C_UnitAuras.RemovePrivateAuraAnchor
local PRIVATE_MAX = 5

local function clearPrivate(b)
    if not (b._privHolders and removeAnchor) then return end
    for _, h in ipairs(b._privHolders) do
        if h.anchorID then
            pcall(removeAnchor, h.anchorID)
            h.anchorID = nil
        end
    end
end

local function placePrivateHolders(b, o)
    b._privHolders = b._privHolders or {}
    local num = math.max(1, math.min(PRIVATE_MAX, math.floor((o.num or 1) + 0.5)))
    local size = o.size or 18
    local spacing = o.spacing or 1
    local point = (o.position or "top"):upper()
    local ax, ay = edgeSign(point)
    if point:find("BOTTOM") then ay = ay + N.PowerInset(b) end
    if not (point:find("LEFT") or point:find("RIGHT")) and (o.growth == "LEFT" or o.growth == "RIGHT" or o.growth == nil) then
        local half = (num - 1) * (size + spacing) / 2
        ax = ax + ((o.growth == "LEFT") and half or -half)
    end
    for i = 1, PRIVATE_MAX do
        local h = b._privHolders[i]
        if not h then
            h = CreateFrame("Frame", nil, b.overlay)
            h:SetFrameLevel(b.overlay:GetFrameLevel() + 6)
            b._privHolders[i] = h
        end
        if i <= num then
            h:SetSize(size, size)
            h:ClearAllPoints()
            local off = (i - 1) * (size + spacing)
            local dx, dy = 0, 0
            if o.growth == "LEFT" then dx = -off
            elseif o.growth == "UP" then dy = off
            elseif o.growth == "DOWN" then dy = -off
            else dx = off end
            h:SetPoint(point, b, point, ax + dx + (o.x or 0), ay + dy + (o.y or 0))
            h:Show()
        else
            h:Hide()
        end
    end
    return num, size
end

local privateGen = 0
local function registerPrivate(b)
    if not addAnchor then return end
    local o = N.db[b.groupKey].indicators.privateAura
    clearPrivate(b)
    if not o or not o.enabled or b._mock or not b.unit or not b.overlay then
        if b._privHolders then for _, h in ipairs(b._privHolders) do h:Hide() end end
        return
    end
    local num, size = placePrivateHolders(b, o)
    for i = 1, num do
        local h = b._privHolders[i]
        local ok, id = pcall(addAnchor, {
            unitToken = b.unit,
            auraIndex = i,
            parent = h,
            isContainer = false,
            showCountdownFrame = o.showCountdownFrame ~= false,
            showCooldownFrame = o.showCountdownFrame ~= false,
            showCountdownNumbers = o.showCountdownNumbers == true,
            iconInfo = {
                iconWidth = size,
                iconHeight = size,
                borderScale = (size / 16) * (o.borderScale or 1),
                iconAnchor = {
                    point = "CENTER", relativeTo = h, relativePoint = "CENTER",
                    offsetX = 0, offsetY = 0,
                },
            },
        })
        if ok then h.anchorID = id end
    end
end

local pendingCombat = {}
local combatFrame = CreateFrame("Frame")
combatFrame:SetScript("OnEvent", function()
    combatFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    for b in pairs(pendingCombat) do
        pendingCombat[b] = nil
        registerPrivate(b)
    end
end)

function A.BindPrivate(b)
    if not addAnchor then return end
    privateGen = privateGen + 1
    local gen = privateGen
    b._privGen = gen
    C_Timer.After(0, function()
        if b._privGen ~= gen then return end
        if InCombatLockdown() then
            pendingCombat[b] = true
            combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
        registerPrivate(b)
    end)
end


-- Aura changes arrive for every unit all the time: only the frames of that unit are looked up.
AC.OnChange(function(unit)
    if not N.db or not N.UnitFrame then return end
    local set = N.UnitFrame.ButtonsOfUnit(unit)
    if not set then return end
    for child in pairs(set) do
        if child:IsShown() then A.Update(child) end
    end
end)

-- Roster / zone changes: the engine may have dropped the private-aura anchors.
local rosterFrame = CreateFrame("Frame")
for _, ev in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
    rosterFrame:RegisterEvent(ev)
end
rosterFrame:SetScript("OnEvent", function()
    if not N.db or not N.UnitFrame then return end
    C_Timer.After(0.3, function()
        N.UnitFrame.ForEachButton(function(child)
            if child.unit and child:IsShown() then A.BindPrivate(child) end
        end)
    end)
end)

N:On("PLAYER_LOGIN", function() dispelSet = nil end)
N:On("PLAYER_SPECIALIZATION_CHANGED", function() dispelSet = nil end)

N:On("NUCLEUS_SETTING_CHANGED", function(_, _, path)
    if not (path and (path:find("%.auras%.") or path:find("%.indicators%.privateAura") or path:find("%.customIndicators"))) then return end
    if N.UnitFrame then
        N.UnitFrame.ForEachButton(function(child) A.Layout(child) end)
    end
end)

-- /nucauras [unit]: the unit's auras as the client reports them (default: target, else yourself).
SLASH_NUCLEUSAURAS1 = "/nucauras"
SlashCmdList.NUCLEUSAURAS = function(msg)
    local unit = strtrim(msg or "")
    if unit == "" then unit = UnitExists("target") and "target" or "player" end
    if not UnitExists(unit) then N:Print("no such unit:", unit) return end
    local function show(v)
        if v == nil then return "-" end
        if IsSecret(v) then return "secret" end
        return tostring(v)
    end
    -- The secrecy level decides whether an aura filter can match the ID at all.
    local function secrecy(id)
        if id == nil or IsSecret(id) or not (C_Secrets and C_Secrets.GetSpellAuraSecrecy) then return "-" end
        local ok, level = pcall(C_Secrets.GetSpellAuraSecrecy, id)
        if not ok then return "?" end
        for name, value in pairs(Enum.SecrecyLevel or {}) do
            if value == level then return name end
        end
        return tostring(level)
    end
    local function flag(d, token)
        return passesFilter(unit, d, token) and "yes" or "no"
    end
    N:Print("auras on", unit)
    for _, base in ipairs({ "HELPFUL", "HARMFUL" }) do
        for _, d in ipairs(AC.Each(unit, base)) do
            N:Print(base:sub(1, 1), show(d.name), "id", show(d.spellId), "from", show(d.sourceUnit),
                "mine", show(d.isFromPlayerOrPlayerPet), "secrecy", secrecy(d.spellId))
            if base == "HARMFUL" then
                N:Print("   raid", flag(d, "HARMFUL|RAID"), "raidCombat", flag(d, "HARMFUL|RAID_IN_COMBAT"),
                    "dispellable", flag(d, "HARMFUL|RAID_PLAYER_DISPELLABLE"), "cc", flag(d, "HARMFUL|CROWD_CONTROL"),
                    "type", show(d.dispelName), "boss", show(d.isBossAura), "priority", show(d.isPriorityAura),
                    "role", show(d.isRoleAura))
            end
        end
    end
end
