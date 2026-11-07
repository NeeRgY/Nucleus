local _, ns = ...
local N = ns.N

-- Layout change of saved data: bump dbVersion and add a `fromVersion < n` block.
local function InitDB()
    local raw = _G.NucleusDB_Vanilla
    if type(raw) ~= "table" then
        raw = {}
        _G.NucleusDB_Vanilla = raw
    end

    local fromVersion = raw.dbVersion or 0

    -- Old per-role power bar switches become the per-class table.
    N.Profiles.PreNormalize = function(tbl)
        for _, k in ipairs({ "ownPet", "groupPets", "spotlight" }) do
            local g = type(tbl[k]) == "table" and tbl[k]
            if g and g.raidHostEnabled == nil and g.hostEnabled ~= nil then
                g.raidHostEnabled, g.raidHostSide = g.hostEnabled, g.hostSide
                g.raidHostGap, g.raidHostShift = g.hostGap, g.hostShift
            end
        end
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

    -- One-time: pet "attach to owner" switched on.
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
    -- One-time: Glow distance now counts from the frame edge, the Sparks style is gone.
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
    -- One-time: the Blizzard-classification fallback of the Defensive / External rows starts off.
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
    -- One-time: the language used to default to German; it now follows the client.
    if not N.db.localeAutoDefaulted then
        if N.db.locale == "deDE" then N.db.locale = "auto" end
        N.db.localeAutoDefaulted = true
    end
    if not N.db.petAttachDefaulted then
        N.db.ownPet.attachEnabled = true
        N.db.groupPets.attachEnabled = true
        N.db.petAttachDefaulted = true
    end

    -- Before anything paints: the options window is built lazily and must see the saved highlight color.
    if N.Recolor then N.Recolor(N.db.accentColor) end

    N:Fire("NUCLEUS_DB_READY")
end

N:On("ADDON_LOADED", function(_, name)
    if name == ns.ADDON then
        InitDB()
    end
end)

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

function N:Set(path, value)
    local node = self.db
    local keys = { strsplit(".", path) }
    for i = 1, #keys - 1 do
        node = node[keys[i]]
    end
    node[keys[#keys]] = value
    self:Fire("NUCLEUS_SETTING_CHANGED", keys[1], path, value)
    if (keys[1] == "raid" or keys[1] == "party") and keys[2] and N.Profiles and N.Profiles.IsLinked
        and N.Profiles.IsLinked(keys[2]) then
        local other = (keys[1] == "raid") and "party" or "raid"
        self:Fire("NUCLEUS_SETTING_CHANGED", other, other .. path:sub(#keys[1] + 1), value)
    end
end
