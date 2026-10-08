local _, ns = ...
local N = ns.N

-- Locale store. enUS.lua provides the base; translation files add overrides.
-- All locale tables are kept so the active language can be switched at runtime
-- (db.locale); missing keys fall back to the key string.

local base = {}          -- enUS
local overrides = {}     -- locale -> { key = value }
local strings = base     -- currently resolved table (metatable target)

N.L = setmetatable({}, {
    __index = function(_, key)
        return strings[key] or base[key] or key
    end,
})

-- Called by locale files. isBase=true marks the authoritative enUS pass.
function N.RegisterLocale(locale, tbl, isBase)
    if isBase then
        for k, v in pairs(tbl) do base[k] = base[k] or v end
        return
    end
    overrides[locale] = overrides[locale] or {}
    for k, v in pairs(tbl) do overrides[locale][k] = v end
end

function N.ApplyLocale(locale)
    if locale == "auto" or not locale then locale = GetLocale() end
    if overrides[locale] then
        strings = setmetatable({}, { __index = base })
        for k, v in pairs(overrides[locale]) do strings[k] = v end
    else
        strings = base
    end
end

-- Resolve once the saved language preference is known.
N:On("NUCLEUS_DB_READY", function()
    N.ApplyLocale(N.db.locale)
end)
N:On("NUCLEUS_SETTING_CHANGED", function(_, _, path)
    if path == "locale" then N.ApplyLocale(N.db.locale) end
end)
