local _, ns = ...
local N = ns.N

-- Classic clients have some modern C_ APIs and not others: use the client's function, else the old global.

local Compat = {}
N.Compat = Compat

local C_Spell, C_SpellBook, C_Item = _G.C_Spell, _G.C_SpellBook, _G.C_Item


local Spell = {}
Compat.Spell = Spell

-- { name, iconID, spellID, castTime, minRange, maxRange } or nil
function Spell.GetSpellInfo(spell)
    if C_Spell and C_Spell.GetSpellInfo then return C_Spell.GetSpellInfo(spell) end
    if not _G.GetSpellInfo or spell == nil then return nil end
    local name, _, icon, castTime, minRange, maxRange, id = GetSpellInfo(spell)
    if not name then return nil end
    return { name = name, iconID = icon, spellID = id, castTime = castTime,
             minRange = minRange, maxRange = maxRange }
end

function Spell.GetSpellName(spell)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(spell) end
    if not _G.GetSpellInfo or spell == nil then return nil end
    return (GetSpellInfo(spell))
end

function Spell.GetSpellTexture(spell)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(spell) end
    if _G.GetSpellTexture and spell ~= nil then return GetSpellTexture(spell) end
    if _G.GetSpellInfo and spell ~= nil then return (select(3, GetSpellInfo(spell))) end
end

function Spell.IsSpellPassive(spell)
    if C_Spell and C_Spell.IsSpellPassive then return C_Spell.IsSpellPassive(spell) end
    if _G.IsPassiveSpell then return IsPassiveSpell(spell) end
end

function Spell.IsSpellHelpful(spell)
    if C_Spell and C_Spell.IsSpellHelpful then return C_Spell.IsSpellHelpful(spell) end
    if _G.IsHelpfulSpell then return IsHelpfulSpell(spell) end
end

-- { currentCharges, maxCharges, cooldownStartTime, cooldownDuration } or nil
function Spell.GetSpellCharges(spell)
    if C_Spell and C_Spell.GetSpellCharges then return C_Spell.GetSpellCharges(spell) end
    if not _G.GetSpellCharges then return nil end
    local cur, max, start, duration = GetSpellCharges(spell)
    if not cur then return nil end
    return { currentCharges = cur, maxCharges = max, cooldownStartTime = start, cooldownDuration = duration }
end

Spell.IsSpellImportant = C_Spell and C_Spell.IsSpellImportant or nil


local SpellBook = {}
Compat.SpellBook = SpellBook

function SpellBook.IsSpellKnown(id)
    if C_SpellBook and C_SpellBook.IsSpellKnown then return C_SpellBook.IsSpellKnown(id) end
    if _G.IsSpellKnown then return IsSpellKnown(id) end
    return false
end

-- Modern spellbook: skill lines with a running item index. Returns how many spells it handed out.
local function eachModern(fn)
    local n = 0
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo
        and C_SpellBook.GetSpellBookItemInfo and C_SpellBook.GetSpellBookItemName
        and Enum and Enum.SpellBookSpellBank) then
        return 0
    end
    local bank = Enum.SpellBookSpellBank.Player
    for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local skill = C_SpellBook.GetSpellBookSkillLineInfo(i)
        if skill and skill.numSpellBookItems then
            local first = (skill.itemIndexOffset or 0) + 1
            for j = first, first + skill.numSpellBookItems - 1 do
                local okItem, item = pcall(C_SpellBook.GetSpellBookItemInfo, j, bank)
                local okName, name, sub = pcall(C_SpellBook.GetSpellBookItemName, j, bank)
                if okItem and type(item) == "table" and okName and type(name) == "string" then
                    local isSpell = (not (Enum.SpellBookItemType and item.itemType))
                        or item.itemType == Enum.SpellBookItemType.Spell
                    local passive = item.isPassive
                        or (item.spellID and Spell.IsSpellPassive(item.spellID))
                    if isSpell and not passive then
                        if type(sub) ~= "string" or sub == "" then sub = nil end
                        n = n + 1
                        fn(item, name, sub)
                    end
                end
            end
        end
    end
    return n
end

-- Older spellbook: tabs, one running slot number over all of them.
local function eachLegacy(fn)
    local n = 0
    if not (_G.GetNumSpellTabs and _G.GetSpellTabInfo and _G.GetSpellBookItemName) then return 0 end
    local book = _G.BOOKTYPE_SPELL or "spell"
    local total = 0
    for tab = 1, GetNumSpellTabs() do
        local _, _, _, count = GetSpellTabInfo(tab)
        total = total + (count or 0)
    end
    for slot = 1, total do
        local name, sub = GetSpellBookItemName(slot, book)
        if name then
            local kind, id
            if _G.GetSpellBookItemInfo then kind, id = GetSpellBookItemInfo(slot, book) end
            local passive = _G.IsPassiveSpell and IsPassiveSpell(slot, book)
            if (kind == nil or kind == "SPELL") and not passive then
                if type(sub) ~= "string" or sub == "" then sub = nil end
                local icon = _G.GetSpellBookItemTexture and GetSpellBookItemTexture(slot, book) or nil
                n = n + 1
                fn({ spellID = id, iconID = icon }, name, sub)
            end
        end
    end
    return n
end

-- fn(item, name, rank) per active spell; item = { spellID, iconID }. The first spellbook with spells wins.
function SpellBook.Each(fn)
    -- Without "all ranks" only the highest is listed, but lower ones can be cast by Name(Rank n).
    local seen = {}
    local function emit(item, name, sub)
        local key = name .. "\31" .. (sub or "")
        if seen[key] then return end
        seen[key] = true
        fn(item, name, sub)
    end
    local function withLowerRanks(item, name, sub)
        emit(item, name, sub)
        local top = sub and tonumber(sub:match("(%d+)"))
        if top and top > 1 then
            for rank = top - 1, 1, -1 do
                local lower = sub:gsub("%d+", tostring(rank), 1)
                if Spell.GetSpellInfo(name .. "(" .. lower .. ")") then
                    emit({ iconID = item.iconID }, name, lower)
                end
            end
        end
    end
    local ok, n = pcall(eachModern, withLowerRanks)
    if ok and n and n > 0 then return end
    pcall(eachLegacy, withLowerRanks)
end


local Item = {}
Compat.Item = Item

function Item.GetItemSpell(item)
    if C_Item and C_Item.GetItemSpell then return C_Item.GetItemSpell(item) end
    if _G.GetItemSpell then return GetItemSpell(item) end
end

function Item.GetItemInfoInstant(item)
    if C_Item and C_Item.GetItemInfoInstant then return C_Item.GetItemInfoInstant(item) end
    if _G.GetItemInfoInstant then return GetItemInfoInstant(item) end
end

function Item.GetItemInfo(item)
    if C_Item and C_Item.GetItemInfo then return C_Item.GetItemInfo(item) end
    if _G.GetItemInfo then return GetItemInfo(item) end
end

-- /nucspells: spellbook diagnostics for bug reports.
SLASH_NUCLEUSSPELLS1 = "/nucspells"
SlashCmdList.NUCLEUSSPELLS = function()
    local function yes(v) return v and "yes" or "no" end
    N:Print("C_SpellBook:", yes(C_SpellBook), "| skill lines:", yes(C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines),
        "| Enum bank:", yes(Enum and Enum.SpellBookSpellBank))
    N:Print("GetNumSpellTabs:", yes(_G.GetNumSpellTabs), "| GetSpellBookItemName:", yes(_G.GetSpellBookItemName),
        "| BOOKTYPE_SPELL:", tostring(_G.BOOKTYPE_SPELL))
    local count, first = 0, nil
    SpellBook.Each(function(_, name, sub)
        count = count + 1
        first = first or (name .. (sub and (" (" .. sub .. ")") or ""))
    end)
    N:Print("spells found:", count, "| first:", tostring(first))
end
