local _, ns = ...
local N = ns.N

-- Central visual constants: flat dark surfaces, 1px black borders, accent-on-hover controls,
-- titled panes.
local M = {}
N.Media = M

-- 1px white texture for every bar and border fill.
M.flat = "Interface\\Buttons\\WHITE8X8"

-- Bar fill textures, selectable per group type (Appearance > Color). "flat" is ours (solid tint,
-- no shading); "gradient" and "modern" are Blizzard textures the client already has. A flat tint
-- reads paler than a shaded bar with the same class color.
M.barTextures = {
    flat     = "Interface\\Buttons\\WHITE8X8",
    gradient = "Interface\\TargetingFrame\\UI-StatusBar",
    modern   = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill",
    -- Default: a uniform 76.5% grey (NucleusBar3.tga, made by tools/gen_textures.ps1). Grey rather
    -- than white so SetStatusBarColor darkens the tint to a flat, matte class color, no sheen.
    nucleus  = "Interface\\AddOns\\Nucleus\\Media\\Textures\\NucleusBar3.tga",
    -- Uniform white fill: the class/custom color shows fully flat across the bar.
    nucleus2 = "Interface\\AddOns\\Nucleus\\Media\\Textures\\NucleusBar2.tga",
    -- The old default: a small grayscale vertical gradient (NucleusBar.tga, generated).
    nucleus3 = "Interface\\AddOns\\Nucleus\\Media\\Textures\\NucleusBar.tga",
}

-- Shield/absorb overlay textures (Appearance > Shield). "flat" is a plain wash; "striped" is a
-- 45-degree pattern, white RGB with the stripes in the alpha channel, tiled horizontally, so
-- SetStatusBarColor's tint and alpha give the shield color real texture.
M.shieldTextures = {
    flat    = "Interface\\Buttons\\WHITE8X8",
    striped = "Interface\\AddOns\\Nucleus\\Media\\Textures\\NucleusShield.tga",
}
-- Bundled font (SIL Open Font License, see Media/Fonts/TitilliumWeb-OFL.txt). Full Latin-1
-- coverage, so German umlauts work.
M.font = "Interface\\AddOns\\Nucleus\\Media\\Fonts\\TitilliumWeb-Bold.ttf"
M.fontDefault = M.font
M.fontUI = M.font -- options window and dialogs
-- M.font (frame texts) and M.fontUI follow the choices in General > Fonts, see N.ApplyFontChoices.

-- Choices for the two font dropdowns. `path` may be a function (resolved when used).
M.FONTS = {
    { key = "nucleus",  text = "Nucleus",        path = M.fontDefault },
    { key = "game",     path = function() return _G.STANDARD_TEXT_FONT or "Fonts/FRIZQT__.TTF" end },
    { key = "frizqt",   text = "Friz Quadrata",  path = "Fonts/FRIZQT__.TTF" },
    { key = "arialn",   text = "Arial Narrow",   path = "Fonts/ARIALN.TTF" },
    { key = "skurri",   text = "Skurri",         path = "Fonts/skurri.ttf" },
    { key = "morpheus", text = "Morpheus",       path = "Fonts/MORPHEUS.ttf" },
}

-- These languages need glyphs the bundled font and the Latin Blizzard fonts don't have, so the
-- matching Blizzard font is used for them unless "Game default" is picked.
M.LOCALE_FONTS = {
    ruRU = "Fonts/FRIZQT___CYR.TTF",
    koKR = "Fonts/2002.TTF",
    zhCN = "Fonts/ARKai_T.ttf",
    zhTW = "Fonts/bLEI00D.ttf",
}

local fontProbe
local function loadable(path)
    fontProbe = fontProbe or UIParent:CreateFontString(nil, "OVERLAY")
    return path == M.fontDefault or fontProbe:SetFont(path, 12, "")
end

local function activeLocale()
    local l = N.db and N.db.locale
    if not l or l == "auto" then l = GetLocale() end
    return l
end

-- File path of a choice; falls back to the bundled font if the client can't load it.
function M.FontPath(key)
    local special = M.LOCALE_FONTS[activeLocale()]
    if special and key ~= "game" and loadable(special) then return special end
    for _, f in ipairs(M.FONTS) do
        if f.key == key then
            local path = type(f.path) == "function" and f.path() or f.path
            if loadable(path) then return path end
            break
        end
    end
    return M.fontDefault
end



-- Shape textures for the options UI (tools/gen_textures.ps1): white RGB, the alpha carries the
-- shape, tinted with SetVertexColor. round and roundSm are 9-sliced (SetTextureSliceMargins) so
-- one small file fits any panel; circle is a plain dot; shadow is a 9-sliced soft glow.
local TEX = "Interface\\AddOns\\Nucleus\\Media\\Textures\\"
M.tex = {
    round   = TEX .. "NucleusRound.tga",   -- 32px, radius 8, slice margin 9
    roundSm = TEX .. "NucleusRoundSm.tga", -- 16px, radius 4, slice margin 5
    circle  = TEX .. "NucleusCircle.tga",
    gear    = TEX .. "NucleusGear.tga",    -- 32px settings cog
    roles   = TEX .. "NucleusRoles.tga",   -- 128x32: tank / healer / damage tiles (square role icons)
    shadow  = TEX .. "NucleusShadow.tga",  -- 64px, slice margin 28, shape inset 14
    glowDash  = TEX .. "NucleusGlowDash.tga",  -- 32x4 tile: one dash, one gap (marching glow)
    empty     = TEX .. "NucleusEmpty.tga",     -- fully transparent (mask that hollows a ring)
    classSpec = TEX .. "NucleusClassSpec.tga", -- 512x512 sheet, 8x8 cells of 64px: class + spec icons (tools\gen_classspec_atlas.ps1)
    logo    = TEX .. "Logo.tga",           -- 128px addon logo (tools\gen_logo.ps1)
}

-- Index of each icon on the sheet above (row-major, 8 per row).
M.classSpecCells = {
    class = { DEMONHUNTER = 0, DRUID = 1, WARLOCK = 2, HUNTER = 3, WARRIOR = 4, MAGE = 5, MONK = 6, PALADIN = 7, PRIEST = 8, EVOKER = 9, SHAMAN = 10, ROGUE = 11, DEATHKNIGHT = 12 },
    spec = { [577] = 13, [581] = 14, [102] = 15, [103] = 16, [104] = 17, [105] = 18, [265] = 19, [266] = 20, [267] = 21, [253] = 22, [254] = 23, [255] = 24, [71] = 25, [72] = 26, [73] = 27, [62] = 28, [63] = 29, [64] = 30, [268] = 31, [269] = 32, [270] = 33, [65] = 34, [66] = 35, [70] = 36, [256] = 37, [257] = 38, [258] = 39, [1467] = 40, [1468] = 41, [1473] = 42, [262] = 43, [263] = 44, [264] = 45, [259] = 46, [260] = 47, [261] = 48, [250] = 49, [251] = 50, [252] = 51, [1480] = 52 },
}

M.color = {
    accent      = { 0.20, 0.55, 0.95, 1.00 },
    accentDim   = { 0.20, 0.55, 0.95, 0.18 },
    accentBright = { 0.42, 0.70, 1.00, 1.00 },
    accentHover = { 0.20, 0.55, 0.95, 0.55 },
    navActive   = { 0.20, 0.55, 0.95, 0.85 }, -- held/active button fill
    navHover    = { 0.20, 0.55, 0.95, 0.45 },
    tabBand     = { 0.075, 0.080, 0.100, 0.97 }, -- top tab-strip ground (matches window)
    tabTint     = { 0.24, 0.56, 0.96, 0.16 },    -- active sub-tab wash
    itemHover   = { 1.00, 1.00, 1.00, 0.06 },    -- tab / sub-tab hover wash
    scrollTrack = { 1.00, 1.00, 1.00, 0.04 },
    scrollThumb = { 0.36, 0.38, 0.43, 1.00 },
    -- Options UI surfaces, darkest to lightest: window < segment < card < base.
    base        = { 0.140, 0.150, 0.175, 1.00 }, -- control fill (inputs, buttons)
    baseHover   = { 0.190, 0.203, 0.235, 1.00 },
    windowBg    = { 0.072, 0.078, 0.095, 0.97 },
    navBg       = { 0.072, 0.078, 0.095, 0.97 },
    segment     = { 0.048, 0.052, 0.066, 1.00 }, -- recessed track (tab strip, mode switch)
    card        = { 0.104, 0.112, 0.134, 1.00 },
    line        = { 1.00, 1.00, 1.00, 0.075 },   -- hairlines / card dividers
    frameBg     = { 0.055, 0.058, 0.065, 0.95 },
    border      = { 0.00, 0.00, 0.00, 1.00 },
    borderSoft  = { 1.00, 1.00, 1.00, 0.07 },
    borderInner = { 1.00, 1.00, 1.00, 0.05 },
    paneRule    = { 0.20, 0.55, 0.95, 0.55 },     -- accent underline under pane titles
    healthLoss  = { 0.065, 0.068, 0.075, 1.00 },  -- neutral, not blood-red - lets class color read
    text        = { 0.92, 0.92, 0.94, 1.00 },
    textDim     = { 0.58, 0.60, 0.65, 1.00 },
    aggro       = { 0.90, 0.15, 0.15, 1.00 },
    tank        = { 0.20, 0.55, 0.95, 1.00 },
}

-- Recolors every accent-derived entry from one base {r,g,b} (General > Interface > Highlight
-- color), keeping each entry's alpha and brightness relative to the accent. The color tables are
-- changed in place, so anything holding a reference sees the new values. Textures that baked a
-- color in via SetColorTexture only update when something repaints them, which is what N.OnRecolor
-- below is for.
function N.ApplyAccentColor(rgb)
    rgb = rgb or { 0.20, 0.55, 0.95 }
    local r, g, b = rgb[1], rgb[2], rgb[3]
    local mix = 0.35 -- how far accentBright lightens toward white
    local br, bg, bb = r + (1 - r) * mix, g + (1 - g) * mix, b + (1 - b) * mix

    local function set3(c, cr, cg, cb) c[1], c[2], c[3] = cr, cg, cb end
    set3(M.color.accent, r, g, b)
    set3(M.color.accentDim, r, g, b)
    set3(M.color.accentBright, br, bg, bb)
    set3(M.color.accentHover, r, g, b)
    set3(M.color.navActive, r, g, b)
    set3(M.color.navHover, r, g, b)
    set3(M.color.tabTint, r, g, b)
    set3(M.color.paneRule, r, g, b)
end

-- Widgets that bake the accent into a texture (SetColorTexture copies the value) register a
-- repaint closure here. N.Recolor changes the palette and then calls all of them, so an open
-- options window updates live.
local recolorHooks = {}
function N.OnRecolor(fn) recolorHooks[#recolorHooks + 1] = fn end

function N.Recolor(rgb)
    N.ApplyAccentColor(rgb)
    for _, fn in ipairs(recolorHooks) do pcall(fn) end
end

-- Use this instead of N.ApplyAccentColor when the UI may already be built (from the options
-- window), so the change shows without a /reload.

-- Class color as {r,g,b}, using Blizzard's fixed class colors. Not CUSTOM_CLASS_COLORS: that
-- follows the player's own override and would drift from the real colors.
-- C_ClassColor.GetClassColor is the modern accessor for the same table as RAID_CLASS_COLORS.
-- Everything is pcall-guarded: a bad or secret class token must not abort the render that also
-- paints name, health text and power. Worst case it falls back to grey.
function N.ClassRGB(class)
    if class == nil then return 0.6, 0.6, 0.6 end

    if C_ClassColor and C_ClassColor.GetClassColor then
        local ok, c = pcall(C_ClassColor.GetClassColor, class)
        if ok and c then
            local ok2, r, g, b = pcall(c.GetRGB, c)
            if ok2 and type(r) == "number" then return r, g, b end
        end
    end

    local ok3, c2 = pcall(function() return RAID_CLASS_COLORS[class] end)
    if ok3 and c2 then return c2.r, c2.g, c2.b end

    return 0.6, 0.6, 0.6
end

function N.ApplyFontChoices()
    local db = N.db
    M.fontUI = M.FontPath(db and db.fontUI)
    M.font = M.FontPath(db and db.fontFrame)
end
N:On("NUCLEUS_DB_READY", N.ApplyFontChoices)
