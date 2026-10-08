local _, ns = ...
local N = ns.N

-- Loads and normalizes NucleusDB_Forever, then fires NUCLEUS_DB_READY.
--
-- dbVersion (Defaults.lua) counts changes to the saved data layout. If a release renames or moves
-- a setting or changes what a value means, bump dbVersion and add a block below guarded by
-- `fromVersion < <new number>`. Plain new settings need nothing, defaults are merged in.
local function InitDB()
    local raw = _G.NucleusDB_Forever
    if type(raw) ~= "table" then
        raw = {}
        _G.NucleusDB_Forever = raw
    end

    -- 0 for a brand-new save. Saves from development builds carry a higher number and are just
    -- renumbered.
    local fromVersion = raw.dbVersion or 0

    -- Profiles.Setup folds older flat saves into the first profile, prunes/merges defaults and
    -- installs the N.db proxy.
    -- Before a profile is merged with defaults: the old power bar switches (tanks / healers /
    -- damage dealers) become the per-class table.
    N.Profiles.PreNormalize = function(tbl)
        for _, k in ipairs({ "party", "raid", "ownPet", "groupPets", "npc", "spotlight" }) do
            local pb = type(tbl[k]) == "table" and type(tbl[k].indicators) == "table" and tbl[k].indicators.powerBar
            if type(pb) == "table" and (pb.showTank == false or pb.showHealer == false or pb.showDamager == false) then
                local off = { TANK = pb.showTank == false, HEALER = pb.showHealer == false, DAMAGER = pb.showDamager == false }
                pb.filter = type(pb.filter) == "table" and pb.filter or {}
                for _, e in ipairs(N.CLASS_ROLES) do
                    for _, role in ipairs(e[2]) do
                        if off[role] then
                            pb.filter[e[1]] = type(pb.filter[e[1]]) == "table" and pb.filter[e[1]] or {}
                            pb.filter[e[1]][role] = false
                        end
                    end
                end
            end
        end
    end
    N.Profiles.Setup(raw)

    N.db.dbVersion = N.Defaults.dbVersion

    -- One-time: pet "attach to owner" now defaults to on; profiles saved while it was off get it
    -- switched on once.
    if not N.db.timeColorDefaulted then
        for _, k in ipairs({ "party", "raid", "ownPet", "groupPets", "npc", "spotlight" }) do
            N.db[k].appearance.timeColor.enabled = true
        end
        N.db.timeColorDefaulted = true
    end
    if not N.db.decimalsOffDefaulted then
        for _, k in ipairs({ "party", "raid", "ownPet", "groupPets", "npc", "spotlight" }) do
            N.db[k].appearance.timeColor.decimals = 0
        end
        N.db.decimalsOffDefaulted = true
    end
    -- One-time: the Glow indicator's Distance now counts outwards from the frame edge and the
    -- Sparks style is gone. Older entries are reset, in every profile.
    if not N.db.glowDistanceReset then
        for _, prof in pairs(raw.profiles or {}) do
            for _, k in ipairs({ "party", "raid", "ownPet", "groupPets", "npc", "spotlight" }) do
                local list = type(prof) == "table" and prof[k] and prof[k].customIndicators
                for _, e in ipairs(type(list) == "table" and list or {}) do
                    if e.type == "glow" then
                        e.offset = 0
                        if e.glow == "autocast" then e.glow = "pixel" end
                    end
                end
            end
        end
        N.db.glowDistanceReset = true
    end
    -- One-time: the Proc border glow style is gone, entries using it pulse instead.
    if not N.db.glowProcRemoved then
        for _, prof in pairs(raw.profiles or {}) do
            for _, k in ipairs({ "party", "raid", "ownPet", "groupPets", "npc", "spotlight" }) do
                local list = type(prof) == "table" and prof[k] and prof[k].customIndicators
                for _, e in ipairs(type(list) == "table" and list or {}) do
                    if e.type == "glow" and e.glow == "proc" then e.glow = "pulse" end
                end
            end
        end
        N.db.glowProcRemoved = true
    end
    -- One-time: the Blizzard-classification fallback of the Defensive / External rows now starts
    -- off. The game matches the spell list itself (also in combat); the fallback only added
    -- unrelated buffs next to the listed ones.
    if not N.db.blizzFilterOff then
        for _, prof in pairs(raw.profiles or {}) do
            for _, k in ipairs({ "party", "raid", "ownPet", "groupPets", "npc", "spotlight" }) do
                local a = type(prof) == "table" and prof[k] and prof[k].auras
                if type(a) == "table" then
                    if type(a.defensives) == "table" then a.defensives.useFilter = false end
                    if type(a.externals) == "table" then a.externals.useFilter = false end
                end
            end
        end
        N.db.blizzFilterOff = true
    end
    if not N.db.petAttachDefaulted then
        N.db.ownPet.attachEnabled = true
        N.db.groupPets.attachEnabled = true
        N.db.petAttachDefaulted = true
    end

    -- Before anything paints. The options window is built lazily on first open, so it always sees
    -- the saved highlight color.
    if N.Recolor then N.Recolor(N.db.accentColor) end

    N:Fire("NUCLEUS_DB_READY")
end

N:On("ADDON_LOADED", function(_, name)
    if name == ns.ADDON then
        InitDB()
    end
end)

-- Every group of unit frames. party and raid are the real groups; the other three (own pet, group
-- pets, NPC companions) are the pet side.
N.GROUP_KEYS = { party = true, raid = true, ownPet = true, groupPets = true, npc = true, spotlight = true }
N.SPOTLIGHT_MAX = 10 -- most frames the spotlight group can show
N.PET_KEYS = { ownPet = true, groupPets = true, npc = true }
N.PET_ORDER = { "ownPet", "groupPets", "npc" }

function N:Mode()
    return self.db and self.db.editMode or "party"
end

function N:SetMode(mode)
    if not N.GROUP_KEYS[mode] then return end
    if N.PET_KEYS[mode] then self.db.lastPetMode = mode end
    self.db.editMode = mode
    self:Fire("NUCLEUS_EDIT_MODE", mode)
end

-- Saves a setting and notifies listeners. path is dotted, e.g. "party.width"; listeners key on the
-- top-level section.
function N:Set(path, value)
    local node = self.db
    local keys = { strsplit(".", path) }
    for i = 1, #keys - 1 do
        node = node[keys[i]]
    end
    node[keys[#keys]] = value
    self:Fire("NUCLEUS_SETTING_CHANGED", keys[1], path, value)
end
