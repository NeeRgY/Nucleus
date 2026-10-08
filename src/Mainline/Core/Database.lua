local _, ns = ...
local N = ns.N

-- Loads and normalizes NucleusDB_Mainline. Fires NUCLEUS_DB_READY once the
-- table is usable so every other module can rely on N.db existing.
--
-- dbVersion (Defaults.lua) counts changes to the SAVED data layout, starting at
-- 1 with the first public release. When a later release changes that layout
-- (renames or moves a setting, changes a value's meaning), bump dbVersion and
-- add a block below guarded by `fromVersion < <new number>`. Adding a plain
-- new setting needs nothing: defaults are merged in automatically.
local function InitDB()
    local raw = _G.NucleusDB_Mainline
    if type(raw) ~= "table" then
        raw = {}
        _G.NucleusDB_Mainline = raw
    end

    -- 0 for a brand-new save. Saves written by development builds carry a
    -- higher number than the release numbering and are simply renumbered.
    local fromVersion = raw.dbVersion or 0

    -- Profiles.Setup folds older flat saves into the first profile, prunes/merges
    -- defaults, and installs the N.db proxy onto the active profile.
    -- Before a profile is merged with the defaults: the power bar's old switches
    -- (show for tanks / healers / damage dealers) become the per-class table.
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

    -- Migrations go here, e.g.:
    --   if fromVersion > 0 and fromVersion < 2 then ... end

    N.db.dbVersion = N.Defaults.dbVersion

    -- One-time: the pet "attach to owner" option now defaults to on; a profile
    -- saved while it still defaulted to off gets it switched on once.
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
    -- One-time: the "Glow" indicator's Distance now counts outwards from the edge
    -- of the frame (0 = the ring sits right outside it), and the "Sparks" style is
    -- gone. Older entries carried the old meaning / style: reset them, in every profile.
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
    -- One-time: the "Proc border" glow style is gone; entries that used it pulse instead.
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
    if not N.db.petAttachDefaulted then
        N.db.ownPet.attachEnabled = true
        N.db.groupPets.attachEnabled = true
        N.db.petAttachDefaulted = true
    end

    -- Before anything paints - the options window is built lazily on first
    -- open, well after this - so it always sees the saved highlight color.
    if N.Recolor then N.Recolor(N.db.accentColor) end

    N:Fire("NUCLEUS_DB_READY")
end

N:On("ADDON_LOADED", function(_, name)
    if name == ns.ADDON then
        InitDB()
    end
end)

-- Every group of unit frames. party / raid are the real groups; the other
-- three (own pet, pets of group members, NPC companions) are the "pets" side.
N.GROUP_KEYS = { party = true, raid = true, ownPet = true, groupPets = true, npc = true, spotlight = true }
N.SPOTLIGHT_MAX = 10 -- most frames the spotlight group can show
N.PET_KEYS = { ownPet = true, groupPets = true, npc = true }
N.PET_ORDER = { "ownPet", "groupPets", "npc" }

-- Group type the options window is editing (a key of N.GROUP_KEYS).
function N:Mode()
    return self.db and self.db.editMode or "party"
end

function N:SetMode(mode)
    if not N.GROUP_KEYS[mode] then return end
    if N.PET_KEYS[mode] then self.db.lastPetMode = mode end
    self.db.editMode = mode
    self:Fire("NUCLEUS_EDIT_MODE", mode)
end

-- Persist a setting and notify listeners. path is a dot string, e.g.
-- "party.width". Listeners key on the top-level section name.
function N:Set(path, value)
    local node = self.db
    local keys = { strsplit(".", path) }
    for i = 1, #keys - 1 do
        node = node[keys[i]]
    end
    node[keys[#keys]] = value
    self:Fire("NUCLEUS_SETTING_CHANGED", keys[1], path, value)
end
