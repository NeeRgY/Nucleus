local _, ns = ...
local N = ns.N

-- Forever (Classic): the class of each default spell and the spells the Buffs picker
-- offers, taken from Core/Classic.lua. Spells without a class show under General.
N.SpellClass = N.Classic.spellClass

-- Spells offered by the Buffs picker (healing buffs of every class), plus shields
-- and utility buffs that are only worth a custom indicator, not a default row.
local pool = {}
for _, id in ipairs(N.Classic.healingList) do pool[#pool + 1] = id end
local extra = {
    SHAMAN  = { 324, 325, 905, 945, 8134, 10431, 10432,       -- Lightning Shield
                546, 131 },                                   -- Water Walking, Water Breathing
    DRUID   = { 1126, 5232, 6756, 5234, 8907, 9884, 9885,     -- Mark of the Wild
                21849, 21850,                                 -- Gift of the Wild
                467, 782, 1075, 8914, 9756, 9910 },           -- Thorns
    PRIEST  = { 1243, 1244, 1245, 2791, 10937, 10938,         -- Power Word: Fortitude
                21562, 21564,                                 -- Prayer of Fortitude
                14752, 14818, 14819, 27841,                   -- Divine Spirit
                27681, 32999,                                 -- Prayer of Spirit
                976, 10957, 10958,                            -- Shadow Protection
                27683, 39374,                                 -- Prayer of Shadow Protection
                6346, 10060 },                                -- Fear Ward, Power Infusion
    PALADIN = { 20217, 25898,                                 -- Blessing of Kings (Greater)
                19740, 19834, 19835, 19836, 19837, 19838, 25291, -- Blessing of Might
                25782, 25916,                                 -- Greater Blessing of Might
                19742, 19850, 19852, 19853, 19854, 25290,     -- Blessing of Wisdom
                25894, 25918,                                 -- Greater Blessing of Wisdom
                20911, 20912, 20913, 25899,                   -- Sanctuary (Greater)
                1038, 1044 },                                 -- Salvation, Freedom
    MAGE    = { 1459, 1460, 1461, 10156, 10157, 23028,        -- Arcane Intellect, Brilliance
                1008, 8455, 10169, 10170,                     -- Amplify Magic
                604, 8450, 8451, 10173, 10174, 130 },         -- Dampen Magic, Slow Fall
    WARLOCK = { 132, 5697 },                                  -- Detect Invisibility, Unending Breath
}
local have = {}
for _, id in ipairs(pool) do have[id] = true end
for cls, ids in pairs(extra) do
    for _, id in ipairs(ids) do
        N.SpellClass[id] = N.SpellClass[id] or cls
        if not have[id] then pool[#pool + 1] = id end
    end
end
N.SpellPool = { buffs = pool }
