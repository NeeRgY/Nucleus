local _, ns = ...
local N = ns.N

-- Forever (Classic): the class of each default spell and the spells the Buffs picker
-- offers, taken from Core/Classic.lua. Spells without a class show under General.
N.SpellClass = N.Classic.spellClass

-- Spells offered by the Buffs picker (healing buffs of every class).
N.SpellPool = {
    buffs = N.Classic.healingList,
}