local _, ns = ...
local N = ns.N

-- Data for the Options > About section. Rendered by UI/OptionsFrame.lua.
-- Icon textures are optional; drop matching .tga files in Media/ to enable
-- them. The options renderer ignores color/icon fields it cannot use yet.

local MEDIA = "Interface\\AddOns\\Nucleus\\Media\\"

N.About = {
    author = "NeRgY",
    -- Where "Support Nucleus" in the Supporters pane leads (nil = no button).
    supportUrl = "https://ko-fi.com/neergy",
    -- The Supporters pane (About tab): tiers, best first. Add names to a tier's `names`
    -- list (a name as they like to be shown); a tier without names is not shown, and with no names at all
    -- the pane says nobody is listed yet. `color` = { r, g, b }.
    supporters = {
        { name = "Gold",      color = { 1.00, 0.82, 0.25 }, names = {} },
        { name = "Silver",    color = { 0.78, 0.82, 0.88 }, names = {} },
        { name = "Supporter", color = { 0.42, 0.70, 1.00 },
          names = { "Longhorn", "Milkerson", "Kieran Smith", "Zozo" } },
    },
    links = {
        {
            label = "Discord",
            url   = "https://discord.gg/YjfyDKckCS",
            color = { 0.345, 0.396, 0.949 },
            icon  = MEDIA .. "discord.png",
        },
        {
            label = "CurseForge",
            url   = "https://www.curseforge.com/wow/addons/nucleus",
            color = { 0.945, 0.392, 0.212 },
            icon  = MEDIA .. "curseforge.png",
        },
        {
            label = "GitHub",
            url   = "https://github.com/NeeRgY/Nucleus",
            color = { 0.55, 0.55, 0.60 },
            icon  = MEDIA .. "github.png",
        },
        {
            label = "Wago",
            url   = "https://addons.wago.io/addons/nucleus",
            color = { 0.788, 0.310, 0.996 },
            icon  = MEDIA .. "wago.png",
        },
        {
            label = "Ko-fi",
            url   = "https://ko-fi.com/neergy",
            color = { 1.000, 0.370, 0.360 },
            icon  = MEDIA .. "kofi.png",
        },
    },
}
