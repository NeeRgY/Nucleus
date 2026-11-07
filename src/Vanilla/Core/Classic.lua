local _, ns = ...
local N = ns.N

-- Everything version-specific. Spell IDs are per rank; unknown ranks are dropped at load.

N.IS_CLASSIC = true
local C = {}
N.Classic = C

-- The nine classes of Classic Era. There are no specializations and no roles to read.
C.CLASSES = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }
C.CLASS_SET = {}
for _, c in ipairs(C.CLASSES) do C.CLASS_SET[c] = true end

-- One specialization ID per class (for the class icon).
C.SPEC_ID = {
    MAGE = 1482, DRUID = 1484, HUNTER = 1485, PALADIN = 1486, PRIEST = 1487,
    ROGUE = 1488, SHAMAN = 1489, WARLOCK = 1490, WARRIOR = 1491,
}

-- What a class can remove from a friendly target (Classic: no spec talents).
C.DISPEL = {
    PRIEST  = { Magic = true, Disease = true },                  -- Dispel Magic, Cure / Abolish Disease
    PALADIN = { Magic = true, Poison = true, Disease = true },   -- Cleanse, Purify
    DRUID   = { Curse = true, Poison = true },                   -- Remove Curse, Cure / Abolish Poison
    SHAMAN  = { Poison = true, Disease = true },                 -- Cure Poison, Cure Disease
    MAGE    = { Curse = true },                                  -- Remove Lesser Curse
}


local function ids(...) return { ... } end

C.DEFENSIVES = {
    DRUID   = { ids(22812), ids(22842, 22845) },                                  -- Barkskin, Frenzied Regeneration
    SHAMAN  = { ids(30823) },                                                     -- Shamanistic Rage
    MAGE    = { ids(11958, 45438), ids(13031, 11426, 13032, 13033), ids(1463, 8494, 8495, 10191, 10192, 10193) }, -- Ice Block, Ice Barrier, Mana Shield
    PALADIN = { ids(642, 1020), ids(498, 5573), ids(20925) },                      -- Divine Shield, Divine Protection, Sacred Shield
    PRIEST  = { ids(586, 9578, 9579, 9592, 10941, 10942), ids(27827) },           -- Fade, Spirit of Redemption
    ROGUE   = { ids(5277), ids(1856, 1857, 11327, 11329), ids(31224) },            -- Evasion, Vanish, Cloak of Shadows
    WARRIOR = { ids(871), ids(12975, 12976), ids(20230), ids(23920) },             -- Shield Wall, Last Stand, Retaliation, Spell Reflection
    HUNTER  = { ids(19263) },                                                     -- Deterrence
    WARLOCK = { ids(6229, 11739, 11740, 28610) },                                 -- Shadow Ward
}
C.EXTERNALS = {
    PALADIN = { ids(1022, 5599, 10278), ids(6940, 20729), ids(1044), ids(19752), ids(31821) }, -- Protection, Sacrifice, Freedom, Divine Intervention, Aura Mastery
    PRIEST  = { ids(10060), ids(6346), ids(33206) },                              -- Power Infusion, Fear Ward, Pain Suppression
    WARRIOR = { ids(3411) },                                                      -- Intervene
    HUNTER  = { ids(34477) },                                                     -- Misdirection
    DRUID   = { ids(29166) },                                                     -- Innervate
}
C.OFFENSIVES = {
    WARRIOR = { ids(1719), ids(12328), ids(12292), ids(18499) },                  -- Recklessness, Death Wish, Sweeping Strikes, Berserker Rage
    ROGUE   = { ids(13750), ids(13877), ids(14177) },                             -- Adrenaline Rush, Blade Flurry, Cold Blood
    MAGE    = { ids(12042), ids(11129), ids(12043) },                             -- Arcane Power, Combustion, Presence of Mind
    HUNTER  = { ids(3045), ids(19574) },                                          -- Rapid Fire, Bestial Wrath
    PRIEST  = { ids(14751) },                                                     -- Inner Focus (Power Infusion is under externals)
    SHAMAN  = { ids(16188) },                                                     -- Nature's Swiftness
    DRUID   = { ids(17116), ids(5217) },                                          -- Nature's Swiftness, Tiger's Fury
    PALADIN = { ids(20216) },                                                     -- Divine Favor
}
C.HEALING_BUFFS = {
    PRIEST = { ids(6074, 139, 6075, 6076, 6077, 6078, 10927, 10928, 10929, 25315),          -- Renew
               ids(592, 17, 600, 3747, 6065, 6066, 10898, 10899, 10900, 10901),            -- Power Word: Shield
               ids(41635, 33076), ids(28276) },                                              -- Prayer of Mending, Lightwell Renew
    DRUID  = { ids(1058, 774, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299),       -- Rejuvenation
               ids(8938, 8936, 8939, 8940, 8941, 9750, 9856, 9857, 9858),                  -- Regrowth
               ids(33763) },                                                                 -- Lifebloom
    SHAMAN = { ids(974, 32593, 32594) },                                                    -- Earth Shield
}

local function flatten(byClass)
    local list, class = {}, {}
    for cls, groups in pairs(byClass) do
        for _, group in ipairs(groups) do
            for _, id in ipairs(group) do
                list[#list + 1] = id
                class[id] = cls
            end
        end
    end
    table.sort(list)
    return list, class
end

local function known(id)
    return not (N.Compat.Spell and N.Compat.Spell.GetSpellInfo) or N.Compat.Spell.GetSpellInfo(id) ~= nil
end

-- Keeps the IDs this client knows (a wrong or Retail-only rank drops out).
function C.Known(list)
    local out = {}
    for _, id in ipairs(list) do
        if known(id) then out[#out + 1] = id end
    end
    return out
end

local function csv(list) return table.concat(list, ",") end

C.defensiveList, C.spellClass = flatten(C.DEFENSIVES)
C.externalList, C.externalClass = flatten(C.EXTERNALS)
C.offensiveList, C.offensiveClass = flatten(C.OFFENSIVES)
C.healingList, C.healingClass = flatten(C.HEALING_BUFFS)
for _, t in ipairs({ C.externalClass, C.offensiveClass, C.healingClass }) do
    for id, cls in pairs(t) do C.spellClass[id] = C.spellClass[id] or cls end
end

-- Default lists as the strings the settings hold (all ranks; unknown ranks never match an aura).
C.LIST = {
    defensives = csv(C.defensiveList),
    externals = csv(C.externalList),
    offensives = csv(C.offensiveList),
    buffs = csv(C.healingList),
}

-- Raid buffs: ids = spells that apply it, cast = castable ranks, icon, class = provider.
local FAMILY = {
    fort = { ids = { 1243, 1244, 1245, 2791, 10937, 10938, 10939, 10940, 13864, 23947, 23948, 21562, 21564, 450086 },
             cast = { 1243, 1244, 1245, 2791, 10937, 10938, 21562, 21564 } },
    spirit = { ids = { 14752, 14818, 14819, 16875, 27841, 27681 },
               cast = { 14752, 14818, 14819, 27841, 27681 } },
    shadowprot = { ids = { 976, 10957, 10958, 25433, 27683, 39374 },
                   cast = { 976, 10957, 10958, 25433, 27683, 39374 } },
    intellect = { ids = { 1459, 1460, 1461, 10156, 10157, 13326, 16876, 364161, 23028 },
                  cast = { 1459, 1460, 1461, 10156, 10157, 23028 } },
    mark = { ids = { 1126, 5232, 5234, 5286, 5287, 6756, 8907, 8908, 9884, 9885, 16878, 24752, 364163, 1291335, 1310503, 21849, 21850 },
             cast = { 1126, 5232, 6756, 5234, 8907, 9884, 9885, 21849, 21850 } },
    thorns = { ids = { 467, 782, 1075, 8914, 9756, 9910, 15438, 16877, 21335, 21337, 22128, 22351, 22696, 25640, 25777 },
               cast = { 467, 782, 1075, 8914, 9756, 9910 } },
    shout = { ids = { 6673, 5242, 6192, 11549, 11550, 11551, 25289, 9128, 24438, 25101, 26043, 26099, 27578 },
              cast = { 6673, 5242, 6192, 11549, 11550, 11551, 25289 } },
    might = { ids = { 19740, 19834, 19835, 19836, 19837, 19838, 25291, 25782, 25916 },
              cast = { 19740, 19834, 19835, 19836, 19837, 19838, 25291, 25782, 25916 } },
    wisdom = { ids = { 19742, 19850, 19852, 19853, 19854, 25290, 25894, 25918 },
               cast = { 19742, 19850, 19852, 19853, 19854, 25290, 25894, 25918 } },
    kings = { ids = { 20217, 1213408, 25898 }, cast = { 20217, 25898 } },
    salvation = { ids = { 1038, 25895 }, cast = { 1038, 25895 } },
    light = { ids = { 19977, 19978, 19979, 26650, 25890 }, cast = { 19977, 19978, 19979, 25890 } },
}
local function union(keys, field)
    local out = {}
    for _, k in ipairs(keys) do
        for _, id in ipairs(FAMILY[k][field]) do out[#out + 1] = id end
    end
    return out
end
C.BUFFS = {
    { key = "fort",      label = "Power Word: Fortitude", class = "PRIEST", icon = 1243,
      ids = FAMILY.fort.ids, cast = FAMILY.fort.cast },
    { key = "spirit",    label = "Divine Spirit",         class = "PRIEST", icon = 14752,
      ids = FAMILY.spirit.ids, cast = FAMILY.spirit.cast },
    { key = "shadowprot", label = "Shadow Protection",    class = "PRIEST", icon = 976,
      ids = FAMILY.shadowprot.ids, cast = FAMILY.shadowprot.cast },
    { key = "intellect", label = "Arcane Intellect",      class = "MAGE",   icon = 1459,
      ids = FAMILY.intellect.ids, cast = FAMILY.intellect.cast },
    { key = "mark",      label = "Mark of the Wild",      class = "DRUID",  icon = 1126,
      ids = FAMILY.mark.ids, cast = FAMILY.mark.cast },
    { key = "thorns",    label = "Thorns",                class = "DRUID",  icon = 467,
      ids = FAMILY.thorns.ids, cast = FAMILY.thorns.cast },
    { key = "shout",     label = "Battle Shout",          class = "WARRIOR", icon = 6673,
      ids = FAMILY.shout.ids, cast = FAMILY.shout.cast },
    { key = "blessing",  label = "Blessings",             class = "PALADIN", icon = 20217,
      ids = union({ "might", "wisdom", "kings", "salvation", "light" }, "ids"),
      cast = union({ "might", "wisdom", "kings", "salvation", "light" }, "cast") },
}
-- A member misses the Blessings entry while none of the enabled ones is on them.
C.BLESSINGS = {
    { key = "might",     label = "Blessing of Might",     class = "PALADIN", icon = 19740,
      ids = FAMILY.might.ids, cast = FAMILY.might.cast },
    { key = "wisdom",    label = "Blessing of Wisdom",    class = "PALADIN", icon = 19742,
      ids = FAMILY.wisdom.ids, cast = FAMILY.wisdom.cast },
    { key = "kings",     label = "Blessing of Kings",     class = "PALADIN", icon = 20217,
      ids = FAMILY.kings.ids, cast = FAMILY.kings.cast },
    { key = "salvation", label = "Blessing of Salvation", class = "PALADIN", icon = 1038,
      ids = FAMILY.salvation.ids, cast = FAMILY.salvation.cast },
    { key = "light",     label = "Blessing of Light",     class = "PALADIN", icon = 19977,
      ids = FAMILY.light.ids, cast = FAMILY.light.cast },
}
C.BUFF_DEFAULT = { fort = true, spirit = true, shadowprot = false, intellect = true, mark = true, thorns = true,
                   shout = true, blessing = true, might = true, wisdom = true, kings = true, salvation = true,
                   light = true }

-- The client's name of a spell (localized), nil when it can't tell.
function C.SpellName(id)
    if _G.C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if N.Compat and N.Compat.Spell and N.Compat.Spell.GetSpellName then return N.Compat.Spell.GetSpellName(id) end
    if _G.GetSpellInfo then return (GetSpellInfo(id)) end
end
C.ACTIONS = {
    { spell = 17534, anim = "sweep", color = { 1.00, 0.10, 0.10 } }, -- Major Healing Potion
    { spell = 17531, anim = "sweep", color = { 0.20, 0.50, 1.00 } }, -- Major Mana Potion
    { spell = 6262,  anim = "sweep", color = { 0.40, 1.00, 0.00 } }, -- Healthstone
}

-- Classic health values are small, so nothing under 10,000 is abbreviated.
local abbrevOpts
function N.Abbreviate(n)
    if abbrevOpts == nil then
        abbrevOpts = false
        if _G.CreateAbbreviateConfig and _G.AbbreviateNumbers then
            abbrevOpts = { config = CreateAbbreviateConfig({
                { breakpoint = 1000000000, abbreviation = "B", significandDivisor = 10000000, fractionDivisor = 100, abbreviationIsGlobal = false },
                { breakpoint = 1000000,    abbreviation = "M", significandDivisor = 10000,    fractionDivisor = 100, abbreviationIsGlobal = false },
                { breakpoint = 10000,      abbreviation = "K", significandDivisor = 100,      fractionDivisor = 10,  abbreviationIsGlobal = false },
                { breakpoint = 1,          abbreviation = "",  significandDivisor = 1,        fractionDivisor = 1,   abbreviationIsGlobal = false },
            }) }
        end
    end
    if abbrevOpts then return AbbreviateNumbers(n, abbrevOpts) end
    if _G.AbbreviateNumbers then return AbbreviateNumbers(n) end
    if type(n) ~= "number" then return tostring(n) end
    if n >= 1000000000 then return ("%.1fB"):format(n / 1000000000) end
    if n >= 1000000 then return ("%.1fM"):format(n / 1000000) end
    if n >= 10000 then return ("%.1fK"):format(n / 1000) end
    return tostring(math.floor(n + 0.5))
end
