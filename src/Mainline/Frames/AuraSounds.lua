local addonName, ns = ...
local N = ns.N
local M = N.Media
local IsSecret = N.IsSecret

-- The game plays these itself, so they work in combat too.
local S = {}
N.AuraSounds = S

S.TRIGGERS = { "added", "removed", "stacks" }
S.WHO = { "all", "me" }
S.BUILTIN = {
    { key = "game:raidwarning", name = "Raid warning", id = 567397, path = "Sound\\Interface\\RaidWarning.ogg" },
    { key = "game:alarmclock", name = "Alarm clock", id = 567458, path = "Sound\\Interface\\AlarmClockWarning3.ogg" },
    { key = "game:readycheck", name = "Ready check", id = 567478, path = "Sound\\Interface\\ReadyCheck.ogg" },
    { key = "game:levelup", name = "Level up", id = 567431, path = "Sound\\Interface\\LevelUp.ogg" },
    { key = "game:mapping", name = "Map ping", id = 567416, path = "Sound\\Interface\\MapPing.ogg" },
}

for _, s in ipairs({
    { "8bit_error", "8-bit error", "8-bit-error.mp3" }, { "8bit_laser", "8-bit laser", "8-bit-laser.mp3" },
    { "coin_collect", "Coin collect", "coin-collect.mp3" }, { "glass", "Glass", "glass.mp3" },
    { "low", "Low", "low.mp3" }, { "popup_close", "Popup close", "popupclose.mp3" },
    { "slide", "Slide", "slide.mp3" }, { "slide_out", "Slide out", "slide_out.mp3" },
    { "task_complete", "Task complete", "task-complete.mp3" }, { "ui_bubble", "UI bubble", "uibubble.mp3" },
    { "ui_hover", "UI hover", "uihover.mp3" }, { "ui_pop", "UI pop", "uipop.mp3" },
    { "ui_toast", "UI toast", "uitoast.mp3" },
}) do
    S.BUILTIN[#S.BUILTIN + 1] = { key = "nuc:" .. s[1], name = s[2],
        path = "Interface\\AddOns\\" .. addonName .. "\\Media\\Sounds\\" .. s[3] }
end


local TRIGGER_FIELD = { added = "Added", removed = "Removed", stacks = "ApplicationsIncreased" }

local function apis()
    local c = _G.C_UnitAuras
    return c and c.AddAuraSound, c and c.RemoveAuraSound
end

function S.Available()
    local add, remove = apis()
    return type(add) == "function" and type(remove) == "function"
end

local function triggerValue(name)
    local enum = Enum and Enum.UnitAuraSoundTrigger
    local v = enum and enum[TRIGGER_FIELD[name]]
    if type(v) == "number" and not IsSecret(v) then return v end
end

-- A bare name means the addon's Sounds folder, anything else a path inside AddOns. Only .ogg and .mp3.
function S.CustomPath(file)
    if type(file) ~= "string" then return nil end
    file = (strtrim(file):gsub("/", "\\"))
    local low = file:lower()
    if file == "" or file:find("..", 1, true) or file:sub(1, 1) == "\\"
        or not (low:sub(-4) == ".ogg" or low:sub(-4) == ".mp3") then
        return nil
    end
    if not file:find("\\", 1, true) then file = addonName .. "\\Sounds\\" .. file end
    return "Interface\\AddOns\\" .. file
end

-- Path or file ID of a saved choice, nil for None or a missing file.
function S.Resolve(key)
    if type(key) ~= "string" or key == "" or key == "none" then return nil end
    for _, b in ipairs(S.BUILTIN) do
        if b.key == key then return b.id or b.path end
    end
    if key:sub(1, 5) == "file:" then return S.CustomPath(key:sub(6)) end
    local name = M.SharedName(key)
    local lib = name and LibStub and LibStub("LibSharedMedia-3.0", true)
    local path = lib and lib:Fetch("sound", name, true)
    if type(path) == "string" or type(path) == "number" then return path end
end

local function play(file)
    local ok, willPlay = pcall(PlaySoundFile, file, "Master")
    return ok and willPlay ~= false
end

function S.Test(entry)
    local file = entry and S.Resolve(entry.sound)
    if not file then
        N:Print("Aura sounds: no sound chosen.")
        return
    end
    if play(file) then return end
    for _, b in ipairs(S.BUILTIN) do
        if b.id == file and play(b.path) then return end
    end
    N:Print("Aura sounds: the game could not play this sound (" .. tostring(file) .. ").")
end

-- Registering only works out of combat and outside boss encounters.
local function blocked()
    if InCombatLockdown() then return true end
    local types = Enum and Enum.AddOnRestrictionType
    if IsAddOnRestrictionActive and types and types.Encounter ~= nil then
        local ok, v = pcall(IsAddOnRestrictionActive, types.Encounter)
        if not ok or IsSecret(v) or v ~= false then return true end
    end
    return false
end

local function unitsFor(who)
    local out = { "player" }
    if who == "me" then return out end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local u = "raid" .. i
            local same = UnitIsUnit(u, "player")
            if IsSecret(same) or not same then out[#out + 1] = u end
        end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do out[#out + 1] = "party" .. i end
    end
    return out
end

-- Ranks share the spell's name and an aura carries whichever rank was cast, so every rank is registered.
local families
local function spellName(id)
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
    if type(name) == "string" and not IsSecret(name) then return name end
end

local function family(id)
    if not families then
        families = {}
        for sid in pairs(N.SpellClass or {}) do
            local name = spellName(sid)
            if name then
                local list = families[name]
                if not list then list = {}; families[name] = list end
                list[#list + 1] = sid
            end
        end
    end
    local name = spellName(id)
    local list = name and families[name]
    if not list then return { id } end
    for _, sid in ipairs(list) do
        if sid == id then return list end
    end
    local out = { id }
    for _, sid in ipairs(list) do out[#out + 1] = sid end
    return out
end

local function desired()
    local out = {}
    local cfg = N.db and N.db.auraSounds
    if not (cfg and cfg.enabled) then return out end
    for _, e in ipairs(cfg.list or {}) do
        local id, trigger, path = e.spell, triggerValue(e.trigger or "added"), S.Resolve(e.sound)
        if type(id) == "number" and id > 0 and trigger and path then
            local units = unitsFor(e.who)
            for _, sid in ipairs(family(id)) do
                for _, unit in ipairs(units) do
                    local sig = unit .. "|" .. sid .. "|" .. trigger .. "|" .. tostring(path)
                    if not out[sig] then
                        local info = { unitToken = unit, spellID = sid, outputChannel = "Master" }
                        if type(path) == "number" then info.soundFileID = path else info.soundFileName = path end
                        out[sig] = { trigger = trigger, info = info }
                    end
                end
            end
        end
    end
    return out
end

local registered = {}

function S.Refresh()
    if not N.db or not S.Available() or blocked() then return end
    local add, remove = apis()
    families = nil
    local want = desired()
    for sig, handle in pairs(registered) do
        if not want[sig] and pcall(remove, handle) then registered[sig] = nil end
    end
    for sig, e in pairs(want) do
        if not registered[sig] then
            local ok, handle = pcall(add, e.trigger, e.info)
            if ok and type(handle) == "number" and not IsSecret(handle) then registered[sig] = handle end
        end
    end
end

local queued
function S.Request()
    if queued then return end
    queued = true
    C_Timer.After(0.3, function()
        queued = nil
        S.Refresh()
    end)
end

for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED",
                         "ADDON_RESTRICTION_STATE_CHANGED", "SPELLS_CHANGED" }) do
    pcall(N.On, N, event, function() S.Request() end)
end
N:On("NUCLEUS_SETTING_CHANGED", function(_, section)
    if section == "auraSounds" then S.Request() end
end)
