local _, ns = ...
local N = ns.N

-- A default table counts as a list (kept whole, never merged key by key) when
-- it has entries, or is flagged `_list = true` (an empty list of user entries).
local function isArray(t) return type(t) == "table" and (t[1] ~= nil or t._list == true) end

-- Deep copy of plain data (tables, numbers, strings, booleans).
function N.DeepCopy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = N.DeepCopy(x) end
    return out
end

-- Deep-merge defaults into a saved table without overwriting existing keys.
-- A default that is a LIST (e.g. the click-cast bindings) is treated as one
-- value: it seeds a missing list but never re-adds entries the user removed.
-- Returns the target table.
function N.MergeDefaults(target, defaults)
    if type(target) ~= "table" then target = {} end
    for k, v in pairs(defaults) do
        if isArray(v) then
            if target[k] == nil then target[k] = N.DeepCopy(v) end
        elseif type(v) == "table" then
            target[k] = N.MergeDefaults(target[k], v)
        elseif target[k] == nil then
            target[k] = v
        end
    end
    return target
end

-- Remove keys from tbl that no longer exist in defaults so stale settings do
-- not accumulate in SavedVariables across versions. Lists are left alone
-- (their length is the user's, not the defaults').
function N.PruneStale(tbl, defaults)
    if type(tbl) ~= "table" or type(defaults) ~= "table" then return end
    for k, v in pairs(tbl) do
        if defaults[k] == nil then
            tbl[k] = nil
        elseif type(v) == "table" and not isArray(defaults[k]) then
            N.PruneStale(v, defaults[k])
        end
    end
end

-- Combat-safe task queue. Frame layout / secure attribute changes are illegal
-- during combat lockdown; callers hand them here and they run on the next
-- PLAYER_REGEN_ENABLED.
local queue = {}
local queueFrame = CreateFrame("Frame")
queueFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
queueFrame:SetScript("OnEvent", function()
    local run = queue
    queue = {}
    for i = 1, #run do
        local ok, err = pcall(run[i].fn)
        if not ok then geterrorhandler()(err) end
    end
end)

-- Run fn now if out of combat, otherwise defer it. Optional key deduplicates
-- repeated deferrals of the same logical action.
function N.RunWhenSafe(fn, key)
    if not InCombatLockdown() then
        fn()
        return
    end
    if key then
        for i = 1, #queue do
            if queue[i].key == key then
                queue[i].fn = fn -- the newer closure replaces the waiting one
                return
            end
        end
    end
    queue[#queue + 1] = { fn = fn, key = key }
end

-- Round to a pixel-aligned value for the current UI scale.
function N.Round(v)
    return floor(v + 0.5)
end

-- `v` UI units as a whole number of physical pixels at `frame`'s scale. Plain 1-unit
-- insets and edge thicknesses land on different sub-pixels at the top-left and the
-- bottom-right when the UI scale is not 1, so two sides of a frame or icon look
-- thicker than the other two. Use this for every 1px border / inset.
function N.Snap(frame, v)
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
