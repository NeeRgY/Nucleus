local _, ns = ...
local N = ns.N
local IsSecret = N.IsSecret

-- Specializations of the group's members, for the Class / Spec Icon indicator.
-- Your own comes from the talent API; everyone else's is read with the game's
-- inspect call, one member at a time (it is throttled by the server), out of
-- combat, and only while an indicator wants it. The result is kept by GUID and
-- read again after a few minutes, since players can change specialization.

local GS = {}
N.GroupSpec = GS

local cache = {}   -- [guid] = { spec = specID, at = time }
local tried = {}   -- [guid] = time of the last inspect attempt
local pending      -- { guid, unit, at }

local STALE = 300    -- seconds until a known specialization is read again
local RETRY = 12     -- seconds between attempts on the same player
local TIMEOUT = 4    -- seconds to wait for the server's answer

-- Does any group profile show the specialization at all?
local function wanted()
    if not N.db then return false end
    for _, key in ipairs({ "party", "raid" }) do
        local sec = N.db[key]
        local o = sec and sec.indicators and sec.indicators.classSpec
        if o and o.enabled and o.mode ~= "class" then return true end
    end
    return false
end

local function playerSpec()
    return N.Profiles and N.Profiles.GetSpec and N.Profiles.GetSpec() or nil
end

-- The specialization ID of `unit`, or nil when not (yet) known.
function GS.Get(unit)
    if not unit then return nil end
    local guid = UnitGUID(unit)
    if not guid or IsSecret(guid) then return nil end
    if guid == UnitGUID("player") then return playerSpec() end
    local e = cache[guid]
    return e and e.spec or nil
end

-- A plausible specialization for sample frames (test mode, preview): the first one
-- of the class that fits the role.
local mockMemo = {}
function GS.MockSpec(class, role)
    local key = tostring(class) .. "/" .. tostring(role)
    if mockMemo[key] ~= nil then return mockMemo[key] or nil end
    local cells = N.Media.classSpecCells
    local ids = {}
    for id in pairs(cells.spec) do ids[#ids + 1] = id end
    table.sort(ids)
    local fallback
    for _, id in ipairs(ids) do
        local ok, _, _, _, _, specRole, classFile = pcall(GetSpecializationInfoByID, id)
        if ok and classFile == class then
            fallback = fallback or id
            if specRole == role then
                mockMemo[key] = id
                return id
            end
        end
    end
    mockMemo[key] = fallback or false
    return fallback
end

local function refreshAll()
    if not (N.UnitFrame and N.UnitFrame.ForEachButton and N.Indicators) then return end
    N.UnitFrame.ForEachButton(function(b) N.Indicators.UpdateOne(b, "classSpec") end)
end

-- The next group member worth inspecting: never read ones first, then the stale.
local function nextTarget()
    local raid = IsInRaid()
    local count = GetNumGroupMembers()
    local prefix = raid and "raid" or "party"
    local last = raid and count or (count - 1)
    local now = GetTime()
    local best, bestGuid, bestAge
    for i = 1, last do
        local unit = prefix .. i
        local guid = UnitGUID(unit)
        if guid and not IsSecret(guid) and UnitExists(unit) and UnitIsConnected(unit)
            and CanInspect(unit) and (not tried[guid] or now - tried[guid] > RETRY) then
            local e = cache[guid]
            local age = e and (now - e.at) or math.huge
            if age > STALE and (not bestAge or age > bestAge) then
                best, bestGuid, bestAge = unit, guid, age
            end
        end
    end
    return best, bestGuid
end

local function tick()
    if not wanted() or InCombatLockdown() then return end
    local now = GetTime()
    if pending then
        if now - pending.at < TIMEOUT then return end
        pending = nil
    end
    -- Leave the game's own inspect window alone.
    if _G.InspectFrame and _G.InspectFrame:IsShown() then return end
    local unit, guid = nextTarget()
    if not unit then return end
    tried[guid] = now
    pending = { guid = guid, unit = unit, at = now }
    NotifyInspect(unit)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("INSPECT_READY")
frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "INSPECT_READY" then
        if not (pending and pending.guid == arg1) then return end
        local unit = pending.unit
        pending = nil
        local spec = GetInspectSpecialization(unit)
        if type(spec) == "number" and spec > 0 then
            cache[arg1] = { spec = spec, at = GetTime() }
            refreshAll()
        end
        if ClearInspectPlayer then ClearInspectPlayer() end
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
        if arg1 == nil or arg1 == "player" then refreshAll() end
    else
        refreshAll()
    end
end)

C_Timer.NewTicker(1.5, tick)
