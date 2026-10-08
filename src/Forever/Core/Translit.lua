local _, ns = ...
local N = ns.N

-- Optional Cyrillic -> Latin transliteration for player names (General > Interface). Plain
-- letter-for-letter romanization.

local MAP = {
    ["А"] = "A", ["а"] = "a", ["Б"] = "B", ["б"] = "b", ["В"] = "V", ["в"] = "v",
    ["Г"] = "G", ["г"] = "g", ["Д"] = "D", ["д"] = "d", ["Е"] = "E", ["е"] = "e",
    ["Ё"] = "Yo", ["ё"] = "yo", ["Ж"] = "Zh", ["ж"] = "zh", ["З"] = "Z", ["з"] = "z",
    ["И"] = "I", ["и"] = "i", ["Й"] = "Y", ["й"] = "y", ["К"] = "K", ["к"] = "k",
    ["Л"] = "L", ["л"] = "l", ["М"] = "M", ["м"] = "m", ["Н"] = "N", ["н"] = "n",
    ["О"] = "O", ["о"] = "o", ["П"] = "P", ["п"] = "p", ["Р"] = "R", ["р"] = "r",
    ["С"] = "S", ["с"] = "s", ["Т"] = "T", ["т"] = "t", ["У"] = "U", ["у"] = "u",
    ["Ф"] = "F", ["ф"] = "f", ["Х"] = "Kh", ["х"] = "kh", ["Ц"] = "Ts", ["ц"] = "ts",
    ["Ч"] = "Ch", ["ч"] = "ch", ["Ш"] = "Sh", ["ш"] = "sh", ["Щ"] = "Shch", ["щ"] = "shch",
    ["Ъ"] = "", ["ъ"] = "", ["Ы"] = "Y", ["ы"] = "y", ["Ь"] = "", ["ь"] = "",
    ["Э"] = "E", ["э"] = "e", ["Ю"] = "Yu", ["ю"] = "yu", ["Я"] = "Ya", ["я"] = "ya",
    -- Ukrainian/Belarusian letters that show up in realm names.
    ["Ґ"] = "G", ["ґ"] = "g", ["Є"] = "Ye", ["є"] = "ye", ["І"] = "I", ["і"] = "i",
    ["Ї"] = "Yi", ["ї"] = "yi", ["Ў"] = "U", ["ў"] = "u",
}

-- Quick pre-check so names without Cyrillic skip the rebuild.
local function hasCyrillic(s)
    return s:find("[\208-\211]") ~= nil
end

function N.Translit(name)
    if type(name) ~= "string" or name == "" then return name end
    if not N.db or not N.db.translitNames then return name end
    if not hasCyrillic(name) then return name end
    local out = name:gsub("[\194-\244][\128-\191]*", function(ch)
        return MAP[ch] or ch
    end)
    return out
end
