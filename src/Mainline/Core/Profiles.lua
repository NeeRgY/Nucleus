local _, ns = ...
local N = ns.N

-- Profiles
--
-- A profile is a full set of frame settings: party and raid frames (layout, appearance,
-- indicators, auras), tooltip, ping, click-casting and targeted spell bars. Everything else
-- (language, window scale, highlight color, minimap button, lock state, ...) is account-wide.
--
-- N.db is a thin proxy: reading or writing a profile key (N.db.party, N.db.clickCasting, ...) goes
-- to the ACTIVE profile's table, anything else to the SavedVariables root. A profile switch only
-- swaps the table the proxy points at and replays a few settings events so each module re-applies
-- itself.
--
-- SavedVariables layout (NucleusDB_Mainline):
--   <global keys>   language, uiScale, accentColor, minimap, ...
--   currentProfile  name of the active profile
--   profiles[name]  { party=, raid=, tooltip=, core=, ping=, clickCasting=, targetedSpellBars= }
--   autoSwitch      { enabled, role[ROLE][situation], spec[specID][situation] }
--   backups[i]      { time, name, data } newest first, capped

local P = {}
N.Profiles = P

local LibSerialize = LibStub and LibStub:GetLibrary("LibSerialize", true)
local LibDeflate = LibStub and LibStub:GetLibrary("LibDeflate", true)

P.KEYS = { "party", "raid", "tooltip", "core", "ping", "clickCasting", "targetedSpellBars", "actions", "tools", "ownPet", "groupPets", "npc", "spotlight" }
local KEYSET = {}
for _, k in ipairs(P.KEYS) do KEYSET[k] = true end
P.KEYSET = KEYSET

local DEFAULT_NAME = "Default"
local HIDE = "__hide" -- auto-switch target: hide the frames
P.HIDE = HIDE
local MAX_BACKUPS = 5
local PREFIX = "!NUC:"

-- Situations the auto-switch tells apart, in display order.
P.SITUATIONS = {
    { key = "solo",           label = "Solo" },
    { key = "party",          label = "Party" },
    { key = "raid_outdoor",   label = "Raid (Outdoor)" },
    { key = "raid_instance",  label = "Raid (Instance)" },
    { key = "raid_mythic",    label = "Raid (Mythic)" },
    { key = "arena",          label = "Arena" },
    { key = "battleground15", label = "Battleground (15)" },
    { key = "battleground40", label = "Battleground (40)" },
}

local raw      -- the SavedVariables table
local active   -- the active profile's table
local activeName
local profileDefaults

--------------------------------------------------------------------------------
-- setup (called once from Database.InitDB)
--------------------------------------------------------------------------------

local function buildDefaults()
    profileDefaults = {}
    for _, k in ipairs(P.KEYS) do profileDefaults[k] = N.Defaults[k] end
end

local function normalizeProfile(tbl)
    N.PruneStale(tbl, profileDefaults)
    return N.MergeDefaults(tbl, profileDefaults)
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
                    currentProfile = raw.currentProfile }
    raw.profiles, raw.backups, raw.autoSwitch, raw.currentProfile = nil, nil, nil, nil
    N.PruneStale(raw, globalDef)
    N.MergeDefaults(raw, globalDef)
    raw.profiles, raw.backups, raw.autoSwitch, raw.currentProfile =
        stash.profiles, stash.backups, stash.autoSwitch, stash.currentProfile

    if type(raw.backups) ~= "table" then raw.backups = {} end
    if type(raw.autoSwitch) ~= "table" then raw.autoSwitch = {} end
    local a = raw.autoSwitch
    if a.enabled == nil then a.enabled = true end
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

    N.db = setmetatable({}, {
        __index = function(_, k)
            if KEYSET[k] then return active[k] end
            return raw[k]
        end,
        __newindex = function(_, k, v)
            if KEYSET[k] then active[k] = v else raw[k] = v end
        end,
    })
end

--------------------------------------------------------------------------------
-- registry
--------------------------------------------------------------------------------

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

-- A name that doesn't clash with an existing profile ("Raid", "Raid (2)", ...).
function P.UniqueName(name)
    name = cleanName(name) or "Profile"
    if not raw.profiles[name] then return name end
    local i = 2
    while raw.profiles[name .. " (" .. i .. ")"] do i = i + 1 end
    return name .. " (" .. i .. ")"
end

--------------------------------------------------------------------------------
-- switching
--------------------------------------------------------------------------------

-- Replays settings events so every module re-reads the active profile. Modules already react to
-- these for normal option changes; a switch is just everything changing at once.
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
    N:Fire("NUCLEUS_SETTING_CHANGED", "tools", "tools.readyPull.enabled")
    N:Fire("NUCLEUS_SETTING_CHANGED", "ping", "ping.enabled", N.db.ping.enabled)
    N:Fire("NUCLEUS_SETTING_CHANGED", "tooltip", "tooltip.enabled")
end

-- Makes name the active profile. Frame work is queued by the modules, so this is safe in combat;
-- the auto-switch below also waits for combat to end so a layout never changes mid-fight.
function P.Switch(name)
    if not raw.profiles[name] or name == activeName then return false end
    active = raw.profiles[name]
    activeName = name
    raw.currentProfile = name
    reapply()
    N:Fire("NUCLEUS_PROFILE_CHANGED", name)
    return true
end

function P.Create(name, copyFrom)
    name = cleanName(name)
    if not name or raw.profiles[name] then return nil end
    local src = copyFrom and raw.profiles[copyFrom]
    raw.profiles[name] = normalizeProfile(src and N.DeepCopy(src) or {})
    N:Fire("NUCLEUS_PROFILES_CHANGED")
    return name
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
    N:Fire("NUCLEUS_PROFILES_CHANGED")
    return true
end

--------------------------------------------------------------------------------
-- backups
--------------------------------------------------------------------------------

function P.Backup(name, reason)
    local prof = raw.profiles[name]
    if not prof then return end
    table.insert(raw.backups, 1, {
        time = date("%Y-%m-%d %H:%M"), name = name, reason = reason,
        data = N.DeepCopy(prof),
    })
    while #raw.backups > MAX_BACKUPS do table.remove(raw.backups) end
    N:Fire("NUCLEUS_PROFILES_CHANGED")
end

-- Writes a profile's data over name (creating it if needed) and re-applies it if it is the active
-- one.
local function replaceProfile(name, data)
    raw.profiles[name] = normalizeProfile(N.DeepCopy(data))
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

--------------------------------------------------------------------------------
-- export / import
--------------------------------------------------------------------------------

function P.CanShare()
    return LibSerialize ~= nil and LibDeflate ~= nil
end

function P.Export(name)
    local prof = raw.profiles[name]
    if not (prof and P.CanShare()) then return nil end
    local data = { v = N.Defaults.dbVersion, name = name, profile = N.DeepCopy(prof) }
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

    -- Keep only the keys a profile is made of, each as a table.
    local clean = {}
    for _, k in ipairs(P.KEYS) do
        if type(data.profile[k]) == "table" then clean[k] = data.profile[k] end
    end
    if next(clean) == nil then return false, "IMPORT_ERR_EMPTY" end
    return true, { name = type(data.name) == "string" and data.name or "Imported", profile = clean }
end

-- Imports decoded data as `name`. An existing profile of that name is backed up
-- first, then replaced. Returns the final name.
function P.Import(data, name)
    name = cleanName(name) or P.UniqueName(data.name)
    if raw.profiles[name] then P.Backup(name, "before import") end
    replaceProfile(name, data.profile)
    return name
end

--------------------------------------------------------------------------------
-- auto switch
--------------------------------------------------------------------------------

function P.GetSituation()
    local _, instanceType, difficultyID, _, maxPlayers = GetInstanceInfo()
    if instanceType == "arena" then return "arena" end
    if instanceType == "pvp" then
        return ((maxPlayers or 0) >= 30) and "battleground40" or "battleground15"
    end
    if not IsInGroup() then return "solo" end
    if not IsInRaid() then return "party" end
    if instanceType == "raid" then
        return (difficultyID == 16) and "raid_mythic" or "raid_instance"
    end
    return "raid_outdoor"
end

-- specID, role, spec display name (nil when the client can't tell yet).
function P.GetSpec()
    local spi = _G.C_SpecializationInfo
    local getSpec = (spi and spi.GetSpecialization) or _G.GetSpecialization
    local getInfo = (spi and spi.GetSpecializationInfo) or _G.GetSpecializationInfo
    if not (getSpec and getInfo) then return nil end
    local ok, index = pcall(getSpec)
    if not (ok and index) then return nil end
    local ok2, specID, specName, _, _, role = pcall(getInfo, index)
    if not (ok2 and specID) then return nil end
    return specID, role, specName
end

-- The table the settings UI and switcher read: the per-spec one if the player opted in for this
-- spec, otherwise the per-role one. Returns table, "spec"|"role".
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
    local target = tbl and tbl[P.GetSituation()]
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

