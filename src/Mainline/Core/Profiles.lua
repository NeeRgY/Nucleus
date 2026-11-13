local _, ns = ...
local N = ns.N


local P = {}
N.Profiles = P

local LibSerialize = LibStub and LibStub:GetLibrary("LibSerialize", true)
local LibDeflate = LibStub and LibStub:GetLibrary("LibDeflate", true)

P.KEYS = { "party", "raid", "tooltip", "core", "ping", "clickCasting", "targetedSpellBars", "actions", "auraSounds", "tools", "ownPet", "groupPets", "npc", "spotlight" }
local KEYSET = {}
for _, k in ipairs(P.KEYS) do KEYSET[k] = true end
P.KEYSET = KEYSET

-- Areas that can be shared by every profile instead of stored in each, with their profile keys.
P.SCOPE_AREAS = {
    { id = "tooltip",      keys = { "tooltip" } },
    { id = "clickCasting", keys = { "clickCasting" } },
    { id = "utilities",    keys = { "tools", "actions", "auraSounds" } },
    { id = "spotlight",    keys = { "spotlight" } },
}
local SCOPE_OF = {} -- profile key -> area id
for _, a in ipairs(P.SCOPE_AREAS) do
    for _, k in ipairs(a.keys) do SCOPE_OF[k] = a.id end
end

local DEFAULT_NAME = "Default"
local HIDE = "__hide" -- auto-switch target: hide the frames
P.HIDE = HIDE
local MAX_BACKUPS = 5
local PREFIX = "!NUC:"

P.SITUATIONS = {
    { key = "solo",           label = "Solo" },
    { key = "party",          label = "Party" },
    { key = "raid_outdoor",   label = "Raid (Outdoor)" },
    { key = "raid_instance",  label = "Raid (Instance)" },
    { key = "raid_mythic",    label = "Raid (Mythic)" },
    { key = "arena",          label = "Arena" },
    { key = "battleground10", label = "Battleground (10)" },
    { key = "battleground15", label = "Battleground (15)" },
    { key = "battleground40", label = "Battleground (40)" },
}

-- autoSwitch.bySize: profile by raid size; a size without one falls back to the situation.
P.SIZE_SITUATIONS = {
    { key = "raidsize10", label = "Raid (up to 10 players)" },
    { key = "raidsize20", label = "Raid (11 to 20 players)" },
    { key = "raidsize40", label = "Raid (21 to 40 players)" },
}

local raw      -- the SavedVariables table
local active   -- the active profile's table
local activeName
local profileDefaults


local function buildDefaults()
    profileDefaults = {}
    for _, k in ipairs(P.KEYS) do profileDefaults[k] = N.Defaults[k] end
end

-- The parts of the Group's settings the Raid can share.
P.LINK_CATEGORIES = { "appearance", "indicators", "auras", "customIndicators" }

local function linkGroups(tbl)
    local raid, party = tbl.raid, tbl.party
    if type(raid) ~= "table" or type(party) ~= "table" or type(raid.link) ~= "table" then return end
    for _, cat in ipairs(P.LINK_CATEGORIES) do
        if raid.link[cat] == true and type(party[cat]) == "table" then raid[cat] = party[cat] end
    end
end

local function normalizeProfile(tbl)
    N.PruneStale(tbl, profileDefaults)
    local out = N.MergeDefaults(tbl, profileDefaults)
    linkGroups(out or tbl)
    return out
end

function P.Setup(saved)
    raw = saved
    buildDefaults()

    -- Older saves kept the profile keys flat at the root: fold them into the first profile.
    if type(raw.profiles) ~= "table" then
        local first = {}
        for _, k in ipairs(P.KEYS) do
            first[k] = raw[k]
            raw[k] = nil
        end
        raw.profiles = { [DEFAULT_NAME] = first }
        raw.currentProfile = DEFAULT_NAME
    end

    -- Account-wide keys: pruned/merged against the defaults, the profile machinery is left alone.
    local globalDef = {}
    for k, v in pairs(N.Defaults) do
        if not KEYSET[k] then globalDef[k] = v end
    end
    local stash = { profiles = raw.profiles, backups = raw.backups, autoSwitch = raw.autoSwitch,
                    currentProfile = raw.currentProfile, sharedData = raw.sharedData }
    raw.profiles, raw.backups, raw.autoSwitch, raw.currentProfile, raw.sharedData = nil, nil, nil, nil, nil
    N.PruneStale(raw, globalDef)
    N.MergeDefaults(raw, globalDef)
    raw.profiles, raw.backups, raw.autoSwitch, raw.currentProfile, raw.sharedData =
        stash.profiles, stash.backups, stash.autoSwitch, stash.currentProfile, stash.sharedData

    if type(raw.backups) ~= "table" then raw.backups = {} end
    if type(raw.autoSwitch) ~= "table" then raw.autoSwitch = {} end
    local a = raw.autoSwitch
    if a.enabled == nil then a.enabled = true end
    if a.bySize == nil then a.bySize = false end
    if type(a.role) ~= "table" then a.role = {} end
    if type(a.spec) ~= "table" then a.spec = {} end
    for _, role in ipairs({ "TANK", "HEALER", "DAMAGER" }) do
        if type(a.role[role]) ~= "table" then a.role[role] = {} end
    end

    local count = 0
    for name, tbl in pairs(raw.profiles) do
        if type(tbl) == "table" then
            if P.PreNormalize then P.PreNormalize(tbl) end
            normalizeProfile(tbl)
            count = count + 1
        else
            raw.profiles[name] = nil
        end
    end
    if count == 0 then raw.profiles[DEFAULT_NAME] = normalizeProfile({}) end

    if not raw.profiles[raw.currentProfile or ""] then
        raw.currentProfile = raw.profiles[DEFAULT_NAME] and DEFAULT_NAME or P.List()[1]
    end
    active = raw.profiles[raw.currentProfile]
    activeName = raw.currentProfile

    if type(raw.sharedData) ~= "table" then raw.sharedData = {} end
    if type(raw.profileScope) ~= "table" then raw.profileScope = {} end
    local sharedDefaults = {}
    for k in pairs(SCOPE_OF) do sharedDefaults[k] = profileDefaults[k] end
    N.PruneStale(raw.sharedData, sharedDefaults)
    N.MergeDefaults(raw.sharedData, sharedDefaults)

    -- The table a profile key lives in right now: the active profile, or the shared copy.
    local function holder(k)
        local area = SCOPE_OF[k]
        if area and raw.profileScope[area] == "global" then return raw.sharedData end
        return active
    end
    N.db = setmetatable({}, {
        __index = function(_, k)
            if KEYSET[k] then return holder(k)[k] end
            return raw[k]
        end,
        __newindex = function(_, k, v)
            if KEYSET[k] then holder(k)[k] = v else raw[k] = v end
        end,
    })
end


function P.List()
    local out = {}
    for name in pairs(raw.profiles) do out[#out + 1] = name end
    table.sort(out, function(a, b) return a:lower() < b:lower() end)
    return out
end

function P.Current() return activeName end
function P.Exists(name) return name ~= nil and raw.profiles[name] ~= nil end
function P.AutoSwitch() return raw.autoSwitch end
function P.Backups() return raw.backups end

local function cleanName(name)
    name = (name or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil end
    return name:sub(1, 32)
end
P.CleanName = cleanName

function P.UniqueName(name)
    name = cleanName(name) or "Profile"
    if not raw.profiles[name] then return name end
    local i = 2
    while raw.profiles[name .. " (" .. i .. ")"] do i = i + 1 end
    return name .. " (" .. i .. ")"
end


-- Generation rises when a profile's tables are replaced; cached options pages follow it.
local gens = {}
function P.Generation(name) return gens[name] or 0 end
local function bumpGeneration(name)
    if name then
        gens[name] = (gens[name] or 0) + 1
    else
        for n in pairs(raw.profiles) do gens[n] = (gens[n] or 0) + 1 end
    end
end
P.BumpGeneration = bumpGeneration

-- Replays settings events so every module re-reads the active profile.
local function reapply()
    for _, sec in ipairs({ "party", "raid", "ownPet", "groupPets", "npc", "spotlight" }) do
        N:Fire("NUCLEUS_SETTING_CHANGED", sec, sec .. ".enabled", N.db[sec].enabled)
        N:Fire("NUCLEUS_SETTING_CHANGED", sec, sec .. ".width", N.db[sec].width)
        N:Fire("NUCLEUS_SETTING_CHANGED", sec, sec .. ".hideBlizzard", N.db[sec].hideBlizzard)
        N:Fire("NUCLEUS_SETTING_CHANGED", sec, sec .. ".indicators.name.enabled")
        N:Fire("NUCLEUS_SETTING_CHANGED", sec, sec .. ".auras.buffs.enabled")
        N:Fire("NUCLEUS_SETTING_CHANGED", sec, sec .. ".appearance.barTexture")
    end
    N:Fire("NUCLEUS_SETTING_CHANGED", "clickCasting", "clickCasting.bindings")
    N:Fire("NUCLEUS_SETTING_CHANGED", "targetedSpellBars", "targetedSpellBars.enabled")
    N:Fire("NUCLEUS_SETTING_CHANGED", "actions", "actions.enabled")
    N:Fire("NUCLEUS_SETTING_CHANGED", "auraSounds", "auraSounds.enabled")
    N:Fire("NUCLEUS_SETTING_CHANGED", "tools", "tools.readyPull.enabled")
    N:Fire("NUCLEUS_SETTING_CHANGED", "ping", "ping.enabled", N.db.ping.enabled)
    N:Fire("NUCLEUS_SETTING_CHANGED", "tooltip", "tooltip.enabled")
end

-- Makes name the active profile; frame work is queued by the modules, so this is safe in combat.
function P.Switch(name)
    if not raw.profiles[name] or name == activeName then return false end
    active = raw.profiles[name]
    activeName = name
    raw.currentProfile = name
    reapply()
    N:Fire("NUCLEUS_PROFILE_CHANGED", name)
    return true
end

-- Starting points for new profiles: only keys the profile already has are set.
P.TEMPLATES = {
    { id = "healer", label = "TPL_healer", data = {
        party = { width = 104, height = 48, spacing = 3,
            indicators = { powerBar = { enabled = true }, role = { enabled = true }, leader = { enabled = true },
                           raidMarker = { enabled = true } },
            auras = { buffs = { enabled = true, max = 4 }, debuffs = { enabled = true, max = 3 },
                      dispels = { enabled = true }, defensives = { enabled = true }, externals = { enabled = true } } },
        raid = { width = 80, height = 40, spacing = 2, columnSpacing = 2, unitsPerColumn = 5,
            indicators = { role = { enabled = true }, leader = { enabled = true }, raidMarker = { enabled = true } },
            auras = { buffs = { enabled = true, max = 3 }, debuffs = { enabled = true, max = 3 },
                      dispels = { enabled = true }, defensives = { enabled = true, max = 2 },
                      externals = { enabled = true, max = 2 } } },
    } },
    { id = "tankdps", label = "TPL_tankdps", data = {
        party = { width = 96, height = 38, spacing = 2,
            indicators = { powerBar = { enabled = false }, healthText = { enabled = false }, role = { enabled = true } },
            auras = { buffs = { enabled = false }, debuffs = { enabled = true, max = 3 }, dispels = { enabled = true },
                      defensives = { enabled = false }, externals = { enabled = false } } },
        raid = { width = 70, height = 30, spacing = 1, columnSpacing = 2,
            indicators = { powerBar = { enabled = false }, healthText = { enabled = false }, role = { enabled = false } },
            auras = { buffs = { enabled = false }, debuffs = { enabled = true, max = 3 }, dispels = { enabled = true },
                      defensives = { enabled = false }, externals = { enabled = false } } },
    } },
    { id = "party", label = "TPL_party", data = {
        party = { width = 120, height = 56, spacing = 4,
            indicators = { powerBar = { enabled = true }, healthText = { enabled = true }, role = { enabled = true },
                           leader = { enabled = true }, readyCheck = { enabled = true }, raidMarker = { enabled = true } },
            auras = { buffs = { enabled = true, max = 4 }, debuffs = { enabled = true, max = 4, size = 22 },
                      dispels = { enabled = true }, defensives = { enabled = true }, externals = { enabled = true },
                      crowdControls = { enabled = true, max = 2 } } },
    } },
    { id = "large", label = "TPL_large", data = {
        raid = { width = 56, height = 26, spacing = 1, columnSpacing = 2, unitsPerColumn = 5,
            groupsPerRow = 4, rowSpacing = 2,
            indicators = { powerBar = { enabled = false }, healthText = { enabled = false },
                           role = { enabled = true, size = 9 }, leader = { enabled = true, size = 8 },
                           name = { size = 9 } },
            auras = { buffs = { enabled = false }, debuffs = { enabled = true, max = 2, size = 14 },
                      dispels = { enabled = true }, defensives = { enabled = false }, externals = { enabled = false },
                      crowdControls = { enabled = false } } },
    } },
}

local function overlay(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) == "table" then overlay(dst[k], v) end
        elseif dst[k] ~= nil then
            dst[k] = v
        end
    end
end

function P.ApplyTemplate(profile, id)
    for _, t in ipairs(P.TEMPLATES) do
        if t.id == id then
            for key, data in pairs(t.data) do
                if type(profile[key]) == "table" then overlay(profile[key], data) end
            end
            return true
        end
    end
    return false
end

function P.Create(name, copyFrom, template)
    name = cleanName(name)
    if not name or raw.profiles[name] then return nil end
    local src = copyFrom and raw.profiles[copyFrom]
    raw.profiles[name] = normalizeProfile(src and N.DeepCopy(src) or {})
    if not src and template then P.ApplyTemplate(raw.profiles[name], template) end
    N:Fire("NUCLEUS_PROFILES_CHANGED")
    return name
end

-- Master profile: edits while it is active are copied into the linked profiles, in the ticked parts.
local SYNC_FIELDS = {
    size     = { "width", "height", "spacing", "columnSpacing" },
    layout   = { "orientation", "reverse", "groupBy", "sortMethod", "unitsPerColumn", "maxColumns",
                 "attachEnabled", "attachSide", "attachGap", "attachShift", "ordering" },
    position = { "point", "x", "y", "hostEnabled", "hostSide", "hostGap", "hostShift",
                 "raidHostEnabled", "raidHostSide", "raidHostGap", "raidHostShift" },
}
local SYNC_TABLES = { appearance = "appearance", indicators = "indicators", auras = "auras", custom = "customIndicators" }
P.SYNC_GROUP_PARTS = { "size", "layout", "position", "appearance", "indicators", "auras", "custom" }
P.SYNC_WHOLE = { "ownPet", "groupPets", "npc", "spotlight", "tooltip", "clickCasting", "targetedSpellBars",
                 "actions", "auraSounds", "tools", "ping" }

function P.SyncConfig() return raw and raw.profileSync end

function P.SyncSlaves()
    local out, s = {}, raw and raw.profileSync
    if type(s) ~= "table" then return out end
    for _, name in ipairs(s.slaves or {}) do
        if name ~= s.master and raw.profiles[name] then out[#out + 1] = name end
    end
    return out
end

function P.SyncActive()
    local s = raw and raw.profileSync
    return s and s.master ~= "" and s.master == activeName and #P.SyncSlaves() > 0 or false
end

function P.SyncNow()
    local s = raw and raw.profileSync
    local src = s and s.master ~= "" and raw.profiles[s.master]
    if not src then return 0 end
    local count, touchedActive = 0, false
    for _, name in ipairs(P.SyncSlaves()) do
        local dst = raw.profiles[name]
        for _, g in ipairs({ "party", "raid" }) do
            local from, to = src[g], dst[g]
            if type(from) == "table" and type(to) == "table" then
                for _, part in ipairs(P.SYNC_GROUP_PARTS) do
                    if s.parts[g .. "." .. part] == true then
                        if SYNC_FIELDS[part] then
                            for _, k in ipairs(SYNC_FIELDS[part]) do
                                if from[k] ~= nil then to[k] = N.DeepCopy(from[k]) end
                            end
                        else
                            local k = SYNC_TABLES[part]
                            if from[k] ~= nil then to[k] = N.DeepCopy(from[k]) end
                        end
                    end
                end
            end
        end
        for _, k in ipairs(P.SYNC_WHOLE) do
            local area = SCOPE_OF[k]
            local shared = area and raw.profileScope and raw.profileScope[area] == "global"
            if KEYSET[k] and s.parts[k] == true and not shared and src[k] ~= nil then
                dst[k] = N.DeepCopy(src[k])
            end
        end
        linkGroups(dst)
        bumpGeneration(name)
        count = count + 1
        if name == activeName then touchedActive = true end
    end
    if touchedActive then
        reapply()
        N:Fire("NUCLEUS_PROFILE_CHANGED", activeName)
    end
    return count
end

local syncPending
local function queueSync()
    if syncPending then return end
    syncPending = true
    C_Timer.After(1, function()
        syncPending = false
        if P.SyncActive() then P.SyncNow() end
    end)
end
N:On("NUCLEUS_SETTING_CHANGED", function(_, section)
    if raw and KEYSET[section] and P.SyncActive() then queueSync() end
end)
N:On("NUCLEUS_FRAME_MOVED", function()
    if raw and P.SyncActive() then queueSync() end
end)
local syncLogout = CreateFrame("Frame")
syncLogout:RegisterEvent("PLAYER_LOGOUT")
syncLogout:SetScript("OnEvent", function()
    if raw and P.SyncActive() then P.SyncNow() end
end)

local function syncRename(old, new)
    local s = raw.profileSync
    if type(s) ~= "table" then return end
    if s.master == old then s.master = new end
    for i, name in ipairs(s.slaves or {}) do
        if name == old then s.slaves[i] = new end
    end
end

local function syncForget(name)
    local s = raw.profileSync
    if type(s) ~= "table" then return end
    if s.master == name then s.master = "" end
    for i = #(s.slaves or {}), 1, -1 do
        if s.slaves[i] == name then table.remove(s.slaves, i) end
    end
end

local function renameInAutoSwitch(old, new)
    local function walk(t)
        for sit, target in pairs(t) do
            if target == old then t[sit] = new end
        end
    end
    for _, t in pairs(raw.autoSwitch.role) do walk(t) end
    for _, t in pairs(raw.autoSwitch.spec) do walk(t) end
end

function P.Rename(old, new)
    new = cleanName(new)
    if not new or not raw.profiles[old] or raw.profiles[new] then return false end
    raw.profiles[new] = raw.profiles[old]
    raw.profiles[old] = nil
    if activeName == old then activeName = new; raw.currentProfile = new end
    renameInAutoSwitch(old, new)
    syncRename(old, new)
    N:Fire("NUCLEUS_PROFILES_CHANGED")
    return true
end

function P.Delete(name)
    if not raw.profiles[name] then return false end
    local list = P.List()
    if #list <= 1 then return false end
    local fallback
    for _, n in ipairs(list) do if n ~= name then fallback = n; break end end
    if activeName == name then P.Switch(fallback) end
    raw.profiles[name] = nil
    -- Nothing may point at the deleted profile any more.
    local function clear(t)
        for sit, target in pairs(t) do
            if target == name then t[sit] = nil end
        end
    end
    for _, t in pairs(raw.autoSwitch.role) do clear(t) end
    for _, t in pairs(raw.autoSwitch.spec) do clear(t) end
    syncForget(name)
    N:Fire("NUCLEUS_PROFILES_CHANGED")
    return true
end


-- A profile's data for export / backup, with shared areas taken from the shared copy.
local function profileData(name)
    local prof = N.DeepCopy(raw.profiles[name])
    for k, area in pairs(SCOPE_OF) do
        if raw.profileScope and raw.profileScope[area] == "global" and raw.sharedData[k] then
            prof[k] = N.DeepCopy(raw.sharedData[k])
        end
    end
    return prof
end

function P.GetScope(area)
    local s = raw.profileScope
    return (s and s[area] == "global") and "global" or "profile"
end

-- "global": the active profile's settings become the shared ones; back: every profile gets a copy.
function P.SetScope(area, scope)
    local def
    for _, a in ipairs(P.SCOPE_AREAS) do
        if a.id == area then def = a end
    end
    if not def then return end
    scope = (scope == "global") and "global" or "profile"
    if P.GetScope(area) == scope then return end
    if scope == "global" then
        for _, k in ipairs(def.keys) do raw.sharedData[k] = N.DeepCopy(active[k]) end
    else
        for _, prof in pairs(raw.profiles) do
            for _, k in ipairs(def.keys) do prof[k] = N.DeepCopy(raw.sharedData[k]) end
        end
    end
    raw.profileScope[area] = scope
    bumpGeneration()
    reapply()
    N:Fire("NUCLEUS_PROFILE_CHANGED", activeName)
    N:Fire("NUCLEUS_PROFILES_CHANGED")
end


-- The Raid's entry can point at the Group's table; saved files store it twice, so it is re-joined on load.
function P.IsLinked(cat)
    local r = N.db and N.db.raid
    return r and type(r.link) == "table" and r.link[cat] == true or false
end

-- Switching on replaces the Raid's settings; off keeps the current values as its own copy.
function P.SetLink(cat, on)
    local raid, party = active.raid, active.party
    if not (raid and party and type(raid.link) == "table") then return end
    on = on and true or false
    if (raid.link[cat] == true) == on then return end
    raid.link[cat] = on
    if on then
        raid[cat] = party[cat]
    else
        raid[cat] = N.DeepCopy(party[cat])
    end
    bumpGeneration(activeName)
    reapply()
    N:Fire("NUCLEUS_PROFILE_CHANGED", activeName)
end

-- After something replaced a table (copying between Group and Raid): join the shared parts again.
function P.RelinkGroups()
    if active then linkGroups(active); bumpGeneration(activeName) end
end


function P.Backup(name, reason)
    local prof = raw.profiles[name]
    if not prof then return end
    table.insert(raw.backups, 1, {
        time = date("%Y-%m-%d %H:%M"), name = name, reason = reason,
        data = profileData(name),
    })
    while #raw.backups > MAX_BACKUPS do table.remove(raw.backups) end
    N:Fire("NUCLEUS_PROFILES_CHANGED")
end

-- Writes data over a profile (creating it) and re-applies it when it is the active one.
local function replaceProfile(name, data)
    raw.profiles[name] = normalizeProfile(N.DeepCopy(data))
    bumpGeneration(name)
    if name == activeName then
        active = raw.profiles[name]
        reapply()
        N:Fire("NUCLEUS_PROFILE_CHANGED", name)
    end
    N:Fire("NUCLEUS_PROFILES_CHANGED")
end

function P.RestoreBackup(index)
    local b = raw.backups[index]
    if not b then return false end
    if raw.profiles[b.name] then P.Backup(b.name, "before restore") end
    replaceProfile(b.name, b.data)
    return true, b.name
end


function P.CanShare()
    return LibSerialize ~= nil and LibDeflate ~= nil
end

function P.Export(name)
    local prof = raw.profiles[name]
    if not (prof and P.CanShare()) then return nil end
    local data = { v = N.Defaults.dbVersion, name = name, profile = profileData(name) }
    local str = LibSerialize:Serialize(data)
    str = LibDeflate:CompressDeflate(str, { level = 9 })
    str = LibDeflate:EncodeForPrint(str)
    return PREFIX .. N.Defaults.dbVersion .. ":PROFILE!" .. str
end

-- Returns ok, data|errorKey. Never throws on garbage input.
function P.Decode(text)
    if not P.CanShare() then return false, "IMPORT_ERR_LIBS" end
    text = (text or ""):gsub("^\239\187\191", ""):gsub("%s+", "")
    local version, body = text:match("^" .. PREFIX .. "(%d+):PROFILE!(.+)$")
    if not body then return false, "IMPORT_ERR_FORMAT" end
    version = tonumber(version)
    if version and version > N.Defaults.dbVersion then return false, "IMPORT_ERR_NEWER" end

    local decoded = LibDeflate:DecodeForPrint(body)
    if not decoded then return false, "IMPORT_ERR_DECODE" end
    local inflated = LibDeflate:DecompressDeflate(decoded)
    if not inflated then return false, "IMPORT_ERR_DECODE" end
    local ok, success, data = pcall(function() return LibSerialize:Deserialize(inflated) end)
    if not (ok and success and type(data) == "table" and type(data.profile) == "table") then
        return false, "IMPORT_ERR_DECODE"
    end

    local clean = {}
    for _, k in ipairs(P.KEYS) do
        if type(data.profile[k]) == "table" then clean[k] = data.profile[k] end
    end
    if next(clean) == nil then return false, "IMPORT_ERR_EMPTY" end
    return true, { name = type(data.name) == "string" and data.name or "Imported", profile = clean }
end

-- Imports as `name` (an existing profile is backed up first); returns the final name.
function P.Import(data, name)
    name = cleanName(name) or P.UniqueName(data.name)
    if raw.profiles[name] then P.Backup(name, "before import") end
    replaceProfile(name, data.profile)
    return name
end


function P.GetSituation()
    local _, instanceType, difficultyID, _, maxPlayers = GetInstanceInfo()
    if instanceType == "arena" then return "arena" end
    if instanceType == "pvp" then
        maxPlayers = maxPlayers or 0
        if maxPlayers >= 30 then return "battleground40" end
        return (maxPlayers > 0 and maxPlayers <= 10) and "battleground10" or "battleground15"
    end
    if not IsInGroup() then return "solo" end
    if not IsInRaid() then return "party" end
    if instanceType == "raid" then
        return (difficultyID == 16) and "raid_mythic" or "raid_instance"
    end
    return "raid_outdoor"
end

-- The size situation of the raid you are in, nil outside a plain raid or when size rules are off.
function P.GetSizeSituation()
    if not (raw and raw.autoSwitch.bySize and IsInRaid()) then return nil end
    local _, instanceType = GetInstanceInfo()
    if instanceType == "arena" or instanceType == "pvp" then return nil end
    local n = GetNumGroupMembers()
    if n <= 10 then return "raidsize10" end
    if n <= 20 then return "raidsize20" end
    return "raidsize40"
end

-- Size situation if it has an assignment, else GetSituation().
function P.ActiveSituation(tbl)
    local size = P.GetSizeSituation()
    if size and tbl and tbl[size] ~= nil then return size end
    return P.GetSituation()
end

-- Whether this client has specializations at all (Classic Era and TBC have none).
function P.HasSpecs()
    local spi = _G.C_SpecializationInfo
    return ((spi and spi.GetSpecialization) or _G.GetSpecialization) ~= nil
end

-- specID, role, spec name (only the role on clients without specializations).
function P.GetSpec()
    local spi = _G.C_SpecializationInfo
    local getSpec = (spi and spi.GetSpecialization) or _G.GetSpecialization
    local getInfo = (spi and spi.GetSpecializationInfo) or _G.GetSpecializationInfo
    if not (getSpec and getInfo) then
        local role = _G.UnitGroupRolesAssigned and UnitGroupRolesAssigned("player")
        if role == "TANK" or role == "HEALER" or role == "DAMAGER" then return nil, role, nil end
        return nil
    end
    local ok, index = pcall(getSpec)
    if not (ok and index) then return nil end
    local ok2, specID, specName, _, _, role = pcall(getInfo, index)
    if not (ok2 and specID) then return nil end
    return specID, role, specName
end

-- The assignment table in use: per spec if opted in, otherwise per role. Returns table, "spec"|"role".
function P.GetAssignmentTable()
    local specID, role = P.GetSpec()
    local a = raw.autoSwitch
    if specID and a.spec[specID] then return a.spec[specID], "spec", specID, role end
    if role and a.role[role] then return a.role[role], "role", specID, role end
    return nil
end

-- Turn per-spec assignments on (copy the role's table) or off (drop it).
function P.SetBySpec(on)
    local specID, role = P.GetSpec()
    if not (specID and role) then return end
    local a = raw.autoSwitch
    if on then
        a.spec[specID] = N.DeepCopy(a.role[role] or {})
    else
        a.spec[specID] = nil
    end
    N:Fire("NUCLEUS_PROFILES_CHANGED")
    P.Evaluate()
end

function P.SetAssignment(situation, target)
    local tbl = P.GetAssignmentTable()
    if not tbl then return end
    tbl[situation] = target
    P.Evaluate()
end

N.profileHidden = false

local pending, wantCombatEnd
local function applyHidden(hidden)
    if N.profileHidden == hidden then return end
    N.profileHidden = hidden
    for _, sec in ipairs({ "party", "raid" }) do
        N:Fire("NUCLEUS_SETTING_CHANGED", sec, sec .. ".showSolo", N.db[sec].showSolo)
    end
end

function P.Evaluate()
    if not raw then return end
    if InCombatLockdown() then
        wantCombatEnd = true
        return
    end
    local a = raw.autoSwitch
    if not a.enabled then
        applyHidden(false)
        return
    end
    local tbl = P.GetAssignmentTable()
    local target = tbl and tbl[P.ActiveSituation(tbl)]
    if target == HIDE then
        applyHidden(true)
    else
        applyHidden(false)
        if target and raw.profiles[target] then P.Switch(target) end
    end
    N:Fire("NUCLEUS_AUTOSWITCH_EVALUATED")
end

local function schedule()
    if pending then return end
    pending = true
    C_Timer.After(0.5, function()
        pending = false
        P.Evaluate()
    end)
end

local watcher = CreateFrame("Frame")
for _, ev in ipairs({
    "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "ZONE_CHANGED_NEW_AREA",
    "PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_DIFFICULTY_CHANGED", "INSTANCE_GROUP_SIZE_CHANGED", "PLAYER_REGEN_ENABLED",
}) do
    pcall(watcher.RegisterEvent, watcher, ev)
end
watcher:SetScript("OnEvent", function(_, event)
    if not raw then return end
    if event == "PLAYER_REGEN_ENABLED" then
        if wantCombatEnd then
            wantCombatEnd = false
            schedule()
        end
        return
    end
    schedule()
end)

