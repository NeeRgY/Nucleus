local _, ns = ...
local N = ns.N

-- Secret values: on Midnight, combat-sensitive unit info comes back as a secret value when the
-- caller is tainted. Secrets can go to a few APIs (StatusBar:SetValue, SetMinMaxValues, ...), but
-- any arithmetic, comparison or string.format on one errors. This file guards against that.

local issecret  = _G.issecretvalue
local anysecret = _G.hasanysecretvalues

N.MIDNIGHT = select(4, GetBuildInfo()) >= 120000

function N.IsSecret(v)
    return (issecret and issecret(v)) or false
end

function N.AnySecret(...)
    if anysecret then return anysecret(...) end
    if issecret then
        for i = 1, select("#", ...) do
            if issecret((select(i, ...))) then return true end
        end
    end
    return false
end

-- Health as a 0..1 fraction. Uses UnitHealthPercent when available, otherwise divides the raw
-- values if they are not secret. nil if neither works.
local UnitHealthPercent = _G.UnitHealthPercent
local ScaleTo100 = _G.CurveConstants and _G.CurveConstants.ScaleTo100

-- Health percent 0..100. May be secret: fine for SetFormattedText, never for math.
function N.HealthPercent(unit)
    if UnitHealthPercent then
        if ScaleTo100 then
            local ok, p = pcall(UnitHealthPercent, unit, true, ScaleTo100)
            if ok then
                if N.IsSecret(p) then return p end
                if type(p) == "number" then return p end
            end
        end
        local function tryPercent(...)
            local ok, p = pcall(UnitHealthPercent, ...)
            if not ok then return end
            if N.IsSecret(p) then return p end
            if type(p) == "number" then return (p > 1) and p or (p * 100) end
        end
        local r = tryPercent(unit, true)
        if r ~= nil then return r end
        r = tryPercent(unit)
        if r ~= nil then return r end
    end
    local hp, hpMax = UnitHealth(unit), UnitHealthMax(unit)
    if not N.AnySecret(hp, hpMax) and hpMax and hpMax > 0 then
        return hp / hpMax * 100
    end
    return nil
end

function N.HealthFraction(unit)
    if UnitHealthPercent then
        local ok, p
        if ScaleTo100 then
            ok, p = pcall(UnitHealthPercent, unit, true, ScaleTo100)
            if ok and p and not N.IsSecret(p) then return p / 100 end
        else
            ok, p = pcall(UnitHealthPercent, unit, true)
            if ok and p and not N.IsSecret(p) then
                return p > 1 and p / 100 or p
            end
        end
    end
    local hp, hpMax = UnitHealth(unit), UnitHealthMax(unit)
    if not N.AnySecret(hp, hpMax) and hpMax and hpMax > 0 then
        return hp / hpMax
    end
    return nil
end
