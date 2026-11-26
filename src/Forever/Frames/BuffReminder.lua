local _, ns = ...
local N = ns.N
local M = N.Media
local L = N.L
local IsSecret = N.IsSecret
local T = N.Tools
local K = T and T.Kit
if not K then return end

-- Buff Reminder (WoW Forever): icons for your own missing buffs, display only. Read out of combat, hidden in combat and in PvP.

local KEY = "buffReminder"
local WELL_FED, CAMP, BAG_BUFF, BAG_ITEM, BAG_ASLEEP, TREASURE = 19705, 1229741, 429959, 211527, 1331671, 2481
local BAG_STACKS = 3
-- Foods whose buff is not called Well Fed.
local FOOD_BUFFS = { 18192, 18194, 22730, 25661, 18125, 18141 }
-- The three armor lines, ranks weakest first. Any of them up is enough.
local MAGE_ARMORS = { { 168, 7300, 7301 }, { 7302, 7320, 10219, 10220 }, { 6117, 22782, 22783 } }

-- Class buffs: lines of spell IDs (ranks weakest first). `on` = ticked until the player decides.
local CLASS_BUFFS = {
    DRUID = { { key = "thorns", lines = { { 467, 782, 1075, 8914, 9756, 9910 } } } },
    HUNTER = {
        { key = "aspect", label = "Aspect", on = true, lines = {
            { 34074, 415423 }, { 469145 }, { 13159 }, { 5118 }, { 13163 },
            { 13161, 1299445, 1299446, 1299447 }, { 20043, 20190 },
            { 13165, 14318, 14319, 14320, 14321, 14322, 25296 } } },
        { key = "trueshot", on = true, lines = { { 1299346, 1299348, 19506, 20905, 20906 } } },
    },
    PALADIN = {
        { key = "blessing", label = "Blessing", on = true, lines = {
            { 19742, 19850, 19852, 19853, 19854, 25290 }, { 20217 },
            { 19740, 19834, 19835, 19836, 19837, 19838, 25291 },
            { 25894, 25918 }, { 25898 }, { 25782, 25916 } } },
        { key = "paladinaura", label = "Aura", on = true, lines = {
            { 19891, 19899, 19900 }, { 19888, 19897, 19898 }, { 19876, 19895, 19896 }, { 19746 },
            { 7294, 10298, 10299, 10300, 10301 }, { 465, 10290, 643, 10291, 1032, 10292, 10293 } } },
        { key = "rfury", lines = { { 25780 } } },
    },
    PRIEST = {
        { key = "innerfire", on = true, lines = { { 588, 7128, 602, 1006, 10951, 10952 } } },
        { key = "shadowform", lines = { { 15473 } } },
    },
    SHAMAN = {
        { key = "shield", label = "Shield", on = true, lines = { { 324, 325, 905, 945, 8134, 10431, 10432 }, { 408510 } } },
    },
    WARLOCK = {
        { key = "demonarmor", label = "Armor", on = true, lines = { { 687, 696, 706, 1086, 11733, 11734, 11735 } } },
    },
}

-- Weapon buffs: an imbue (poison, shaman imbue, warlock stone) or a temporary one (sharpening stone, oil).
-- A buff is a list of spells or of items, weakest first. `weapon` limits a stone to bladed or blunt weapons.
local WEAPON_BUFFS = {
    { key = "instant", name = "Instant Poison", imbue = true, class = "ROGUE", items = { 6947, 6949, 6950, 8926, 8927, 8928 } },
    { key = "deadly", name = "Deadly Poison", imbue = true, class = "ROGUE", items = { 2892, 2893, 8984, 8985, 20844 } },
    { key = "crippling", name = "Crippling Poison", imbue = true, class = "ROGUE", items = { 3775, 3776 } },
    { key = "mindnumbing", name = "Mind-numbing Poison", imbue = true, class = "ROGUE", items = { 5237, 6951, 9186 } },
    { key = "wound", name = "Wound Poison", imbue = true, class = "ROGUE", items = { 10918, 10920, 10921, 10922 } },
    { key = "windfury", name = "Windfury Weapon", imbue = true, class = "SHAMAN", spells = { 8232, 8235, 10486, 16362 } },
    { key = "flametongue", name = "Flametongue Weapon", imbue = true, class = "SHAMAN", spells = { 8024, 8027, 8030, 16339, 16341, 16342 } },
    { key = "frostbrand", name = "Frostbrand Weapon", imbue = true, class = "SHAMAN", spells = { 8033, 8038, 10456, 16355, 16356 } },
    { key = "rockbiter", name = "Rockbiter Weapon", imbue = true, class = "SHAMAN", spells = { 8017, 8018, 8019, 10399, 16314, 16315, 16316 } },
    { key = "firestone", name = "Firestone", imbue = true, class = "WARLOCK", items = { 1254, 13699, 13700, 13701 } },
    { key = "spellstone", name = "Spellstone", imbue = true, class = "WARLOCK", items = { 5522, 13602, 13603 } },
    { key = "sharpening", name = "Sharpening Stone", weapon = "BLADED", items = { 2862, 287978, 2863, 2871, 7964, 12404 } },
    { key = "weightstone", name = "Weightstone", weapon = "BLUNT", items = { 3239, 3240, 3241, 7965, 12643 } },
    { key = "elemental", name = "Elemental Sharpening Stone", items = { 18262, 287980 } },
    { key = "wizardoil", name = "Wizard Oil", items = { 20744, 20746, 287979, 20750, 20749 } },
    { key = "manaoil", name = "Mana Oil", items = { 20745, 20747, 20748 } },
    { key = "shadowoil", name = "Shadow Oil", items = { 3824 } },
    { key = "frostoil", name = "Frost Oil", items = { 3829 } },
    { key = "blessedoil", name = "Blessed Wizard Oil", items = { 23123 } },
    { key = "consecrated", name = "Consecrated Sharpening Stone", items = { 23122 } },
}
-- Weapon subclasses by the way they are sharpened (Enum.ItemWeaponSubclass numbers).
local BLADED = { [0] = true, [1] = true, [6] = true, [7] = true, [8] = true, [9] = true, [15] = true }
local BLUNT = { [4] = true, [5] = true, [10] = true, [13] = true }
local FISHING_POLE = 20

local _, playerClass = UnitClass("player")

local function cfg() return K.cfg(KEY) end

local function known(id)
    local C = C_SpellBook
    if C and C.IsSpellKnown then
        local ok, v = pcall(C.IsSpellKnown, id)
        if ok and v then return true end
    end
    if _G.IsPlayerSpell then
        local ok, v = pcall(IsPlayerSpell, id)
        if ok and v then return true end
    end
    return false
end

local function texture(id)
    return (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(id)) or 134400
end

local function spellName(id)
    return C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
end

local function itemIcon(id)
    return (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or 134400
end

local function itemCount(id)
    return (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id)) or 0
end

-- The aura table when the spell is up, false when it is not, nil when it cannot be read.
local function aura(id)
    local ok, a = pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)
    if not ok or IsSecret(a) then return nil end
    return a or false
end

local function expiration(a)
    local e = a and a.expirationTime
    if not e or IsSecret(e) or e <= 0 then return nil end
    return e
end

-- true when one of the spells is up, false when none is, nil when an aura could not be read.
local function anyUp(ids)
    local unreadable = false
    for _, id in ipairs(ids) do
        local a = aura(id)
        if a == nil then unreadable = true elseif a then return true end
    end
    if unreadable then return nil end
    return false
end

local function flatten(lines)
    local out = {}
    for _, line in ipairs(lines) do
        for _, id in ipairs(line) do out[#out + 1] = id end
    end
    return out
end

local function anyKnown(ids)
    for _, id in ipairs(ids) do
        if known(id) then return true end
    end
    return false
end

-- Icon of the strongest rank the player knows, going from the last line to the first.
local function bestIcon(lines)
    for i = #lines, 1, -1 do
        local line = lines[i]
        for j = #line, 1, -1 do
            if known(line[j]) then return texture(line[j]) end
        end
    end
    return texture(lines[1][1])
end

local function trackingActive(spellID)
    if not (C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo) then return nil end
    for i = 1, C_Minimap.GetNumTrackingTypes() do
        local info = C_Minimap.GetTrackingInfo(i)
        if info and info.active and info.spellID == spellID then return true end
    end
    return false
end

local function atMaxLevel()
    local level = UnitLevel("player") or 0
    if _G.IsPlayerAtEffectiveMaxLevel and IsPlayerAtEffectiveMaxLevel() then return true end
    local max = (_G.GetMaxLevelForPlayerExpansion and GetMaxLevelForPlayerExpansion()) or (_G.GetMaxPlayerLevel and GetMaxPlayerLevel())
    return (max and level >= max) or false
end

-- Where the player is: "world", "instance" or nil in PvP (nothing is shown there).
local function place()
    local inInstance, kind = IsInInstance()
    if not inInstance then return "world" end
    if kind == "pvp" or kind == "arena" then return nil end
    return "instance"
end

-- A reminder may have its own "Show in"; "inherit" follows the general one.
local function allowed(r, c, where)
    local w = r.where
    if w == nil or w == "inherit" then w = c.where end
    return w == nil or w == "all" or w == where
end

local function warnSeconds(r)
    return (r.showBelow or 0) * 60
end

-- Weapons. Returns ok, imbueSecondsLeft, tempSecondsLeft of the hand (nil = nothing on it).
local function enchantTimes(slotName, legacyIndex)
    if C_Item and C_Item.GetWeaponEnchantInfo and Enum.WeaponSlot and Enum.WeaponSlot[slotName] and Enum.ItemEnchantType then
        local ok, list = pcall(C_Item.GetWeaponEnchantInfo, Enum.WeaponSlot[slotName])
        if not ok or IsSecret(list) then return false end
        local imbue, temp
        if type(list) == "table" then
            for _, e in ipairs(list) do
                local has, kind, left = e.hasEnchant, e.enchantType, e.timeLeft
                if IsSecret(has) or IsSecret(kind) or IsSecret(left) then return false end
                if has and left and left > 0 then
                    if kind == Enum.ItemEnchantType.Imbue then imbue = left / 1000
                    elseif kind == Enum.ItemEnchantType.Temporary then temp = left / 1000 end
                end
            end
        end
        return true, imbue, temp
    end
    if _G.GetWeaponEnchantInfo then
        local a, b, _, _, c, d = GetWeaponEnchantInfo()
        local has, left
        if legacyIndex == 1 then has, left = a, b else has, left = c, d end
        if IsSecret(has) or IsSecret(left) then return false end
        if has and left and left > 0 then return true, left / 1000, left / 1000 end
        return true
    end
    return false
end

-- The weapon in a slot: its sharpening kind ("BLADED" or "BLUNT", nil for others), or false when there is none.
local function weaponKind(slot)
    local id = GetInventoryItemID("player", slot)
    if not id then return false end
    local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(id)
    if classID ~= Enum.ItemClass.Weapon or subID == FISHING_POLE then return false end
    return BLADED[subID] and "BLADED" or BLUNT[subID] and "BLUNT" or "OTHER"
end

-- Icon of a weapon buff the player has at hand (a known imbue or an item in the bags), else nil.
local function buffIcon(buff)
    if buff.spells then
        for i = #buff.spells, 1, -1 do
            if known(buff.spells[i]) then return texture(buff.spells[i]) end
        end
    else
        for i = #buff.items, 1, -1 do
            if itemCount(buff.items[i]) > 0 then return itemIcon(buff.items[i]) end
        end
    end
end

local function buffName(buff)
    if buff.spells then
        for i = #buff.spells, 1, -1 do
            local n = spellName(buff.spells[i])
            if n and known(buff.spells[i]) then return n end
        end
        return spellName(buff.spells[1]) or buff.name
    end
    return (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(buff.items[#buff.items])) or buff.name
end

-- What a hand should have: the buff, its icon and whether it is only a stand-in (nothing at hand).
local function pickBuff(choice, imbue, kind, hideNoItem)
    if choice == "off" then return nil end
    local auto = choice == nil or choice == "auto"
    for _, buff in ipairs(WEAPON_BUFFS) do
        if (auto or choice == buff.key) and (buff.imbue == true) == imbue
           and (not buff.class or buff.class == playerClass)
           and (not buff.weapon or buff.weapon == kind) then
            local icon = buffIcon(buff)
            if icon then return buff, icon, false end
            if not auto and not hideNoItem then
                local last = buff.spells and buff.spells[#buff.spells]
                return buff, last and texture(last) or itemIcon(buff.items[#buff.items]), true
            end
        end
    end
end

local sleepStart, sleepStacks

local function collect(c, where)
    local out = {}
    local now = GetTime()
    local rem = c.reminders or {}
    local function add(e) out[#out + 1] = e end

    local r = rem.camp
    if r and r.enabled and allowed(r, c, where) and anyUp({ CAMP }) == false then
        add({ tex = texture(CAMP), label = L["Camp Benefits"] })
    end

    r = rem.sleepingBag
    if r and r.enabled and allowed(r, c, where) and not atMaxLevel() and itemCount(BAG_ITEM) > 0 then
        local a = aura(BAG_BUFF)
        if a ~= nil then
            local stacks = a and a.applications or 0
            if not IsSecret(stacks) then
                local tex = itemIcon(BAG_ITEM)
                local entry
                if stacks < BAG_STACKS then
                    entry = { tex = tex, label = L["Sleeping Bag"], count = stacks .. "/" .. BAG_STACKS }
                    -- Asleep in the bag: one stack a minute until the third.
                    local asleep = aura(BAG_ASLEEP)
                    if asleep then
                        if not sleepStart or sleepStacks ~= stacks then sleepStart, sleepStacks = now, stacks end
                        if r.timer ~= false then entry.expireAt = sleepStart + (BAG_STACKS - stacks) * 60 end
                    else
                        sleepStart, sleepStacks = nil, nil
                    end
                else
                    sleepStart, sleepStacks = nil, nil
                    local e = expiration(a)
                    local warn = warnSeconds(r)
                    if warn > 0 and e and e - now <= warn then
                        entry = { tex = tex, label = L["Sleeping Bag"], count = stacks .. "/" .. BAG_STACKS }
                        if r.timer ~= false then entry.expireAt = e end
                    end
                end
                if entry then add(entry) end
            end
        end
    end

    r = rem.wellFed
    if r and r.enabled and allowed(r, c, where) then
        local name = spellName(WELL_FED) or "Well Fed"
        local ok, named = pcall(C_UnitAuras.GetAuraDataBySpellName, "player", name, "HELPFUL")
        if ok and not IsSecret(named) then
            local up, expire, unreadable = named and true or false, named and expiration(named), false
            if not up then
                for _, id in ipairs(FOOD_BUFFS) do
                    local a = aura(id)
                    if a == nil then
                        unreadable = true
                    elseif a then
                        up = true
                        local e = expiration(a)
                        if e and (not expire or e > expire) then expire = e end
                    end
                end
            end
            if not unreadable or up then
                local warn = warnSeconds(r)
                if not up then
                    add({ tex = texture(WELL_FED), label = name })
                elseif warn > 0 and expire and expire - now <= warn then
                    add({ tex = texture(WELL_FED), label = name, expireAt = r.timer ~= false and expire or nil })
                end
            end
        end
    end

    r = rem.treasure
    if r and r.enabled and allowed(r, c, where) and known(TREASURE) and trackingActive(TREASURE) == false then
        add({ tex = texture(TREASURE), label = spellName(TREASURE) or L["Find Treasure"] })
    end

    r = rem.mageArmor
    if r and r.enabled and allowed(r, c, where) and playerClass == "MAGE" then
        local all = flatten(MAGE_ARMORS)
        if anyKnown(all) and anyUp(all) == false then
            add({ tex = bestIcon(MAGE_ARMORS), label = L["Mage armors"] })
        end
    end

    r = rem.classBuffs
    if r and r.enabled and allowed(r, c, where) and CLASS_BUFFS[playerClass] then
        for _, buff in ipairs(CLASS_BUFFS[playerClass]) do
            local on = r.list and r.list[buff.key]
            if on == nil then on = buff.on == true end
            if on then
                local ids = flatten(buff.lines)
                if anyKnown(ids) and anyUp(ids) == false then
                    add({ tex = bestIcon(buff.lines), label = buff.label and L[buff.label] or spellName(buff.lines[1][1]) or buff.key })
                end
            end
        end
    end

    r = rem.weapon
    if r and r.enabled and allowed(r, c, where) then
        local warn = warnSeconds(r)
        local hideNoItem = r.hideNoItem ~= false
        for index, hand in ipairs({
            { slot = 16, name = "MainHand", cfg = r.mh, label = L["BR_MAINHAND"] },
            { slot = 17, name = "OffHand", cfg = r.oh, label = L["BR_OFFHAND"] },
        }) do
            local kind = weaponKind(hand.slot)
            if kind then
                local ok, imbueLeft, tempLeft = enchantTimes(hand.name, index)
                if ok then
                    for _, part in ipairs({
                        { imbue = true, left = imbueLeft, choice = hand.cfg and hand.cfg.imbue },
                        { imbue = false, left = tempLeft, choice = hand.cfg and hand.cfg.temp },
                    }) do
                        local buff, icon, standIn = pickBuff(part.choice, part.imbue, kind, hideNoItem)
                        if buff and (not part.left or (warn > 0 and part.left <= warn)) then
                            add({
                                tex = icon, dim = standIn, label = hand.label .. ": " .. buffName(buff),
                                expireAt = (part.left and r.timer ~= false) and (now + part.left) or nil,
                            })
                        end
                    end
                end
            end
        end
    end
    return out
end

-- While the tool is moved: one sample icon per reminder that is switched on.
local function samples(c)
    local out = {}
    local rem = c.reminders or {}
    local now = GetTime()
    local function on(key) return rem[key] and rem[key].enabled end
    if on("camp") then out[#out + 1] = { tex = texture(CAMP), label = L["Camp Benefits"] } end
    if on("sleepingBag") then
        out[#out + 1] = { tex = itemIcon(BAG_ITEM), label = L["Sleeping Bag"], count = "1/" .. BAG_STACKS,
            expireAt = rem.sleepingBag.timer ~= false and now + 125 or nil }
    end
    if on("wellFed") then
        out[#out + 1] = { tex = texture(WELL_FED), label = L["Well Fed"],
            expireAt = rem.wellFed.timer ~= false and now + 125 or nil }
    end
    if on("treasure") then out[#out + 1] = { tex = texture(TREASURE), label = L["Find Treasure"] } end
    if on("mageArmor") and playerClass == "MAGE" then
        out[#out + 1] = { tex = bestIcon(MAGE_ARMORS), label = L["Mage armors"] }
    end
    if on("classBuffs") and CLASS_BUFFS[playerClass] then
        for _, buff in ipairs(CLASS_BUFFS[playerClass]) do
            local ticked = rem.classBuffs.list and rem.classBuffs.list[buff.key]
            if ticked == nil then ticked = buff.on == true end
            if ticked then
                out[#out + 1] = { tex = bestIcon(buff.lines), label = buff.label and L[buff.label] or spellName(buff.lines[1][1]) or buff.key }
            end
        end
    end
    if on("weapon") then
        out[#out + 1] = { tex = GetInventoryItemTexture("player", 16) or 134400, label = L["Weapon buffs"],
            expireAt = rem.weapon.timer ~= false and now + 125 or nil }
    end
    -- Nothing switched on yet: three generic icons still show where the tool sits.
    if #out == 0 then
        out = {
            { tex = texture(WELL_FED), label = L["Well Fed"], expireAt = now + 125 },
            { tex = texture(168), label = L["Mage armors"] },
            { tex = texture(CAMP), label = L["Camp Benefits"] },
        }
        return out, true
    end
    return out, false
end

-- For the options: the class buffs of the player's class and the weapon buffs the player can pick.
function T.ReminderClassBuffs()
    local out = {}
    for _, buff in ipairs(CLASS_BUFFS[playerClass] or {}) do
        out[#out + 1] = {
            key = buff.key, on = buff.on == true, icon = bestIcon(buff.lines),
            name = buff.label and L[buff.label] or spellName(buff.lines[1][1]) or buff.key,
        }
    end
    return out
end

function T.ReminderWeaponBuffs(imbue)
    local out = {}
    for _, buff in ipairs(WEAPON_BUFFS) do
        if (buff.imbue == true) == imbue and (not buff.class or buff.class == playerClass) then
            out[#out + 1] = { key = buff.key, name = buffName(buff) }
        end
    end
    return out
end

-- The icons of the tool.
local host, icons, ticker, pending

local function build()
    host = K.makeHost(KEY, L["Buff Reminder"])
    icons = {}
end

local function clock(seconds)
    seconds = math.max(0, math.ceil(seconds))
    if seconds >= 3600 then return ("%d:%02d:%02d"):format(seconds / 3600, seconds % 3600 / 60, seconds % 60) end
    if seconds >= 60 then return ("%d:%02d"):format(seconds / 60, seconds % 60) end
    return seconds .. "s"
end

local function icon(i)
    local ic = icons[i]
    if ic then return ic end
    ic = CreateFrame("Frame", nil, host)
    ic:EnableMouse(true)
    N.SkinRound(ic, M.color.base, M.color.line, true)
    ic.tex = ic:CreateTexture(nil, "ARTWORK")
    ic.tex:SetPoint("TOPLEFT", 2, -2)
    ic.tex:SetPoint("BOTTOMRIGHT", -2, 2)
    ic.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    ic.count = N.FontString(ic, 11)
    ic.count:SetPoint("BOTTOMRIGHT", -2, 2)
    ic.time = N.FontString(ic, 11)
    ic.time:SetPoint("CENTER", 0, 0)
    ic:SetScript("OnEnter", function(self)
        if not self.label then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.label)
        GameTooltip:Show()
    end)
    ic:SetScript("OnLeave", function() GameTooltip:Hide() end)
    icons[i] = ic
    return ic
end

-- Highlight of an icon: a colored border or one of the glows, set in the tool's settings.
local function highlight(ic, c, size)
    local mode = c.highlight or "none"
    local hc = c.highlightColor or { 1, 0.85, 0.1 }
    local th, dist = c.highlightThickness or 1, c.highlightDistance or 0
    local speed, len = c.highlightSpeed or 0.3, c.highlightLength or 4
    if mode == "border" then
        local edges = ic._hlEdges
        if not edges then
            edges = {}
            for k = 1, 4 do edges[k] = ic:CreateTexture(nil, "OVERLAY", nil, 6) end
            ic._hlEdges = edges
        end
        local t = N.Snap(ic, th)
        for k = 1, 4 do
            edges[k]:SetColorTexture(hc[1], hc[2], hc[3], 1)
            edges[k]:ClearAllPoints()
            edges[k]:Show()
        end
        edges[1]:SetPoint("TOPLEFT"); edges[1]:SetPoint("TOPRIGHT"); edges[1]:SetHeight(t)
        edges[2]:SetPoint("BOTTOMLEFT"); edges[2]:SetPoint("BOTTOMRIGHT"); edges[2]:SetHeight(t)
        edges[3]:SetPoint("TOPLEFT", 0, -t); edges[3]:SetPoint("BOTTOMLEFT", 0, t); edges[3]:SetWidth(t)
        edges[4]:SetPoint("TOPRIGHT", 0, -t); edges[4]:SetPoint("BOTTOMRIGHT", 0, t); edges[4]:SetWidth(t)
    elseif ic._hlEdges then
        for k = 1, 4 do ic._hlEdges[k]:Hide() end
    end
    if mode == "pixel" or mode == "halo" or mode == "pulse" then
        local newGlow = (N.AuraEngine and N.AuraEngine.NewGlow) or N.NewGlow
        if newGlow then
            ic.glow = ic.glow or newGlow(ic, ic)
            local sig = table.concat({ mode, size, hc[1], hc[2], hc[3], th, dist, speed, len }, "|")
            if ic._glowSig ~= sig then
                ic._glowSig = sig
                ic.glow:Show(mode, hc[1], hc[2], hc[3], dist, th, speed, len)
            end
        end
    elseif ic.glow and ic._glowSig then
        ic._glowSig = nil
        ic.glow:Hide()
    end
    if mode == "blink" then
        if not ic._blink then
            ic._blink = true
            ic:SetScript("OnUpdate", function(self)
                self:SetAlpha(0.3 + 0.7 * math.abs(1 - 2 * (GetTime() % 1)))
            end)
        end
    elseif ic._blink then
        ic._blink = nil
        ic:SetScript("OnUpdate", nil)
        ic:SetAlpha(1)
    end
end

-- Timers on the icons, refreshed twice a second; a timer that ran out asks for a new look.
local elapsedSince = 0
local function tickTimers(_, elapsed)
    elapsedSince = elapsedSince + elapsed
    if elapsedSince < 0.5 then return end
    elapsedSince = 0
    local now, again = GetTime(), false
    for _, ic in ipairs(icons) do
        if ic:IsShown() and ic.expireAt then
            local left = ic.expireAt - now
            ic.time:SetText(clock(left))
            if left <= 0 then again = true end
        end
    end
    if again then T.BuffReminderUpdate() end
end

local function update()
    if not host then return end
    local c = cfg()
    if not c then return end
    local moving = K.unlocked()
    host.handle:SetShown(c.enabled and moving and true or false)

    -- Time based buffs (a weapon enchant running out) have no event, so a slow ticker looks again.
    if c.enabled and not ticker then
        ticker = C_Timer.NewTicker(5, function() T.BuffReminderUpdate() end)
    elseif not c.enabled and ticker then
        ticker:Cancel()
        ticker = nil
    end

    local entries, placeholder = {}, false
    local where = place()
    if moving and c.enabled then
        entries, placeholder = samples(c)
    elseif c.enabled and not N.InCombat() and where then
        entries = collect(c, where)
    end

    for _, ic in ipairs(icons) do ic:Hide() end
    if not host.note then
        host.note = N.FontString(host, 11)
        host.note:SetPoint("TOPLEFT", host, "BOTTOMLEFT", 0, -4)
        host.note:SetJustifyH("LEFT")
        host.note:SetTextColor(M.color.textDim[1], M.color.textDim[2], M.color.textDim[3])
        host.note:SetText(L["BR_PLACEHOLDER"])
    end
    host.note:SetShown(placeholder and true or false)
    if not c.enabled or #entries == 0 then
        host:SetScript("OnUpdate", nil)
        K.setVisible(host, false, c.fadeOut)
        return
    end

    local size, spacing = c.iconSize or 34, c.spacing or 4
    local vertical = c.orientation == "vertical"
    local timed = false
    for i, e in ipairs(entries) do
        local ic = icon(i)
        ic.label, ic.expireAt = e.label, e.expireAt
        ic:SetSize(size, size)
        ic:ClearAllPoints()
        local off = (i - 1) * (size + spacing)
        if vertical then
            ic:SetPoint("TOPLEFT", host, "TOPLEFT", 0, -off)
        else
            ic:SetPoint("TOPLEFT", host, "TOPLEFT", off, 0)
        end
        ic.tex:SetTexture(e.tex)
        ic.tex:SetDesaturated(e.dim and true or false)
        ic.count:SetFont(M.font, math.max(10, math.floor(size * 0.32)), "OUTLINE")
        ic.count:SetText(e.count or "")
        ic.time:SetFont(M.font, math.max(10, math.floor(size * 0.36)), "OUTLINE")
        ic.time:SetText(e.expireAt and clock(e.expireAt - GetTime()) or "")
        if e.expireAt then timed = true end
        ic:Show()
        highlight(ic, c, size)
    end
    host:SetScript("OnUpdate", timed and tickTimers or nil)
    local total = #entries * size + (#entries - 1) * spacing
    if vertical then host:SetSize(size, total) else host:SetSize(total, size) end
    K.setVisible(host, true, c.fadeOut)
end

-- Events only mark the tool dirty, the work happens once a moment later.
local function schedule()
    if pending then return end
    pending = true
    C_Timer.After(0.3, function()
        pending = false
        update()
    end)
end

function T.BuffReminderUpdate() update() end

function T.BuffReminderRefresh()
    if not host then build() end
    local c = cfg()
    if c then
        K.loadPosition(host, c)
        K.applyLook(host, c)
    end
    update()
end

local ev = CreateFrame("Frame")
for _, e in ipairs({
    "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED",
    "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "PLAYER_LEVEL_UP", "MINIMAP_UPDATE_TRACKING",
}) do pcall(ev.RegisterEvent, ev, e) end
ev:RegisterUnitEvent("UNIT_AURA", "player")
ev:SetScript("OnEvent", function()
    local c = cfg()
    if c and c.enabled then schedule() end
end)
