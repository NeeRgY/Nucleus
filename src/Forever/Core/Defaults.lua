local _, ns = ...
local N = ns.N

-- Default settings (NucleusDB_Mainline). party and raid are fully independent of each other.

-- Roles each class can play, in option-list order; the power bar is switched per class and role.
N.CLASS_ROLES = {} -- Forever: nine classes and no roles, so one switch ("ALL") per class
for _, class in ipairs(N.Classic.CLASSES) do
    N.CLASS_ROLES[#N.CLASS_ROLES + 1] = { class, { "ALL" } }
end

local function powerFilterDefaults()
    local t = {}
    for _, e in ipairs(N.CLASS_ROLES) do
        t[e[1]] = {}
        for _, role in ipairs(e[2]) do t[e[1]][role] = true end
    end
    return t
end

local function deepMerge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" and type(dst[k]) == "table" then
            deepMerge(dst[k], v)
        else
            dst[k] = v
        end
    end
end

local function groupDefaults(overrides)
    local t = {
        enabled = true,
        width = 72,
        height = 50,
        spacing = 3,
        hideBlizzard = true,
        orientation = "vertical", -- vertical | horizontal
        reverse = false,          -- grow up/left instead of down/right
        showPlayer = true,        -- party only
        showSolo = true,          -- show the frames when not in a group
        groupBy = "GROUP",        -- raid only: GROUP | CLASS | ROLE | NONE
        sortMethod = "INDEX",     -- raid only: INDEX | NAME
        unitsPerColumn = 5,
        maxColumns = 8,
        columnSpacing = 3,
        point = "TOPLEFT",
        x = 24,
        y = -240,

        -- Own order (party / raid): roles in first / second / third order, `pinned` names always first.
        ordering = { enabled = false, first = "TANK", second = "HEALER", third = "DAMAGER", pinned = "" },

        customIndicators = { _list = true },

        appearance = {
            outOfRangeAlpha = 0.45,
            cdStyleMode = "row",           -- "row" (each indicator decides) | "global"
            cdStyleGlobal = "spiral",       -- "spiral" | "vertical"
            barTexture = "nucleus",          -- "flat" | "gradient" | "modern" | "nucleus"
            healthColorMode = "class",       -- "class" | "custom" | "gradient"
            healthCustomColor = { 0.20, 0.55, 0.95 },
            healthLossColor = { 0.065, 0.068, 0.075 },
            deadColorEnabled = false,        -- dead / ghost units get deadColor on the health bar
            deadColor = { 0.30, 0.30, 0.30 },
            -- Shield / heal-absorb / heal-prediction overlays (Appearance > Shield).
            showOvershield = true,
            absorb     = { enabled = true, style = "striped", opacity = 0.35, color = { 1.00, 1.00, 1.00 }, invertFill = false },
            overshieldColor = { 0.75, 0.90, 1.00 },
            healAbsorb = { enabled = true, style = "flat", opacity = 0.75, color = { 0.55, 0.20, 0.75 } },
            healPredict = { enabled = true, opacity = 0.30, color = { 1.00, 1.00, 1.00 },
                           -- Overheal: the part of an incoming heal beyond full health, outside the frame.
                           overheal = { enabled = false, mode = "extend", length = 40, edgeWidth = 3,
                                        opacity = 0.70, color = { 0.30, 1.00, 0.55 } } },
            targetBorder = { color = { 0.42, 0.70, 1.00 }, thickness = 1 },
            hoverBorder  = { color = { 1.00, 1.00, 1.00 }, thickness = 1 },
            -- Aura time text: turns `color` below `seconds`, counts in tenths below `decimals` (0 = never).
            timeColor    = { enabled = true, seconds = 3, color = { 1.00, 0.15, 0.15 }, decimals = 0 },
            frameBorder  = { enabled = true, color = { 0.00, 0.00, 0.00 }, thickness = 1 },
            -- Dims the frame (outOfRangeAlpha) once health reaches the threshold.
            healthFade = { enabled = false, threshold = 1.0 },
        },
        indicators = {
            custom     = { enabled = true },
            name       = { enabled = true,  size = 11, x = 0, y = 0, color = { 0.92, 0.92, 0.94 }, position = "center", colorMode = "custom", outline = "thin", maxChars = 0,
                           nameFormat = "full" }, -- Forever: "full" (First Surname) | "first" | "last"
            -- "custom" format: {p} percent, {v} value, {m} max, {d} deficit.
            healthText = { enabled = true,  size = 10, x = 0, y = 0, color = { 0.85, 0.85, 0.87 },
                           format = "percent", customFormat = "{p}%", hideAtFull = false,
                           position = "center", colorMode = "custom", outline = "thin" },
            -- Power Bar: height, which roles get one, offset, optional text.
            powerBar   = { enabled = false, height = 4, x = 0, y = 0,
                           filter = powerFilterDefaults(), -- [class][role] = show the bar
                           text = false, textFormat = "percent", customFormat = "{p}%",
                           textSize = 9, textPosition = "bottom", textX = 0, textY = 0,
                           textColorMode = "power", textColor = { 1, 1, 1 },
                           barColorMode = "power", barColor = { 0.2, 0.4, 1 }, barColors = { _list = true }, -- barColors[token] = color
                           position = "bottom" },
            -- Status: a pill naming the unit's state; anchor / align place it, `show` switches single states.
            status     = { enabled = true, size = 11, outline = "thin", anchor = "bottom", align = "center", y = 2,
                           showTimer = true, showBackground = true,
                           stateColors = {
                               afk            = { 1.00, 0.40, 0.40 },
                               offline        = { 1.00, 0.40, 0.40 },
                               dead           = { 1.00, 0.40, 0.40 },
                               drinking       = { 0.12, 0.75, 1.00 },
                               ghost          = { 0.75, 0.80, 1.00 },
                               feignDeath     = { 1.00, 0.85, 0.30 },
                               summonPending  = { 1.00, 0.85, 0.30 },
                               summonAccepted = { 0.40, 1.00, 0.50 },
                               summonDeclined = { 1.00, 0.40, 0.40 },
                           },
                           show = {
                               offline = true, afk = true, feignDeath = true, ghost = true, dead = true, drinking = true,
                               summonPending = true, summonAccepted = true, summonDeclined = true,
                           } },
            -- Role icon: shape "square" | "circle", showTank / showHealer / showDamager.
            role       = { enabled = true,  position = "topleft", size = 11, x = 0, y = 0, shape = "square",
                           showTank = true, showHealer = true, showDamager = true, hideInCombat = false,
                           showSolo = true }, -- showSolo: your own role (from your spec) while not in a group
            -- Class / spec icon: mode "class" | "spec" | "both", off by default.
            classSpec  = { enabled = false, position = "topleft", size = 12, x = 13, y = 0, mode = "spec" },
            leader     = { enabled = true,  position = "topright", size = 10, x = 0, y = 0 },
            -- Raid role icon: main tank / main assist, off by default.
            raidRole   = { enabled = false, position = "bottomright", size = 10, x = 0, y = 0,
                           showTank = true, showAssist = true },
            readyCheck = { enabled = true,  position = "center", size = 16, x = 0, y = 0 },
            raidMarker    = { enabled = true,  position = "top", size = 14, x = 0,  y = 0 },
            -- Status Icon: `show` = kinds that may appear (Indicators.statusIconKinds).
            statusIcon    = { enabled = true,  position = "center", size = 24, x = 0,  y = 0,
                              show = { otherParty = true, incomingRez = true, rezDebuff = true,
                                       soulstone = true, summon = true, phase = true,
                                       bgFlag = true, bgOrb = true } },
            combatIcon    = { enabled = true,  position = "bottomright", size = 12, x = -2, y = 2 },
            targetCounter = { enabled = false, size = 11, x = 0,  y = -2, color = { 1.00, 0.85, 0.30 } },
            -- Absorb Text: format = "short" (12K) | "full" (12,345) | "percent" of max health
            absorbText    = { enabled = false, size = 10, x = 0,  y = 8,  color = { 0.75, 0.90, 1.00 },
                              position = "center", colorMode = "custom", format = "short" },
            -- Private Auras: up to 5 slots, Blizzard draws icon and border (borderScale).
            privateAura   = { enabled = true, num = 2, size = 18, spacing = 1, position = "top",
                              growth = "RIGHT", x = 0, y = 3, showCountdownFrame = true,
                              showCountdownNumbers = false, borderScale = 1 },
            -- Shield Bar: thin bar on the bottom / top edge, growFrom "left" | "right".
            shieldBar     = { enabled = false, height = 4, position = "bottom", growFrom = "left", x = 0, y = 0,
                              color = { 1.00, 1.00, 1.00 }, alpha = 0.8, onlyOvershield = false },
            -- Cast Bar: position = bottom | top | below | above, timeFormat = remaining | both
            castBar       = { enabled = false, height = 10, position = "bottom", x = 0, y = 0, width = 0,
                              texture = "same", borderSize = 0, borderColor = { 0.00, 0.00, 0.00 }, bgAlpha = 0.6,
                              showIcon = false, iconSide = "left", showSpark = false,
                              color = { 1.00, 0.80, 0.20 }, channelColor = { 0.35, 0.65, 1.00 },
                              empowerColor = { 0.65, 0.45, 1.00 }, classColor = false,
                              showInterrupt = true, interruptColor = { 1.00, 0.20, 0.20 },
                              markUninterruptible = false, uninterruptColor = { 0.60, 0.60, 0.60 },
                              showName = true, showTarget = false, showTime = true, timeFormat = "remaining",
                              textSize = 9 },
            -- Health Thresholds: marks at chosen health percentages, a list of { pct, color }.
            healthThresholds = { enabled = false, thickness = 1,
                                 thresholds = { { pct = 90, color = { 1.00, 0.00, 0.00 } } } },
            -- Aggro Border: warnColor = almost aggro, tankColor = aggro; gradient fades inward.
            aggroBorder   = { enabled = true, thickness = 2, gradient = true,
                              warnColor = { 1.00, 0.60, 0.00 }, tankColor = { 1.00, 0.00, 0.00 } },
            threatIcon    = { enabled = false, position = "bottomleft", size = 10, x = 0, y = 0, showLow = false, blink = false,
                              lowColor = { 1.00, 0.90, 0.10 }, warnColor = { 1.00, 0.60, 0.00 },
                              tankColor = { 1.00, 0.00, 0.00 } },
            -- Level Text: format = "full" (Level 80) | "short" (Lvl 80) | "number" (80)
            levelText     = { enabled = false, size = 10, x = 0, y = -16, color = { 0.85, 0.85, 0.87 }, format = "full" },
            -- Missing Buffs: an icon per missing raid buff; `buffs` switches each one.
            missingBuffs  = { enabled = false, size = 13, spacing = 1, position = "bottomright",
                              growth = "LEFT", x = 0, y = 4, hideInCombat = true,
                              buffs = { fortitude = true, intellect = true, wild = true,
                                        shout = true, skyfury = true, bronze = true } },
        },
        auras = {
            buffs = {
                enabled = false, max = 3, size = 15, spacing = 2, perRow = 8, lineSpacing = 2,
                point = "TOPRIGHT", growth = "LEFT", x = 0, y = 0,
                showStacks = true, showCooldown = true, cdStyle = "spiral", showTime = true, timeSize = 10, timeX = 0, timeY = 0, stackSize = 10, stackX = 1, stackY = -1, stackPoint = "BOTTOMRIGHT", stackColor = { 1, 1, 1 }, timePoint = "CENTER", timeBaseColor = { 1, 1, 1 }, onlyMine = true,
                -- useList: only spells in `list` (the options show your class); off = every buff.
                useList = true, pickAll = false, -- pickAll: show the spells of every class in the picker
                list = "1278914,33763,419207,1227806,8936,419287,774,419204,155777,474754,474750,48438,419344,355941,355936,382614,376788,364343,373267,366155,367364,409895,450769,450521,450711,450526,450531,1292922,124682,119611,115175,1260617,198533,156910,53563,200025,1244893,431381,156322,461432,432502,469703,194384,77489,17,1246768,1254306,1300008,41635,401877,1240848,1240849,139,1253593,1300009,383648,974,444490,61295,360827,395152,395296,410089",
            },
            debuffs = {
                enabled = true, max = 3, size = 18, spacing = 2, perRow = 8, lineSpacing = 2,
                point = "BOTTOMLEFT", growth = "RIGHT", x = 0, y = 0,
                showStacks = true, showCooldown = true, cdStyle = "spiral", showTime = true, timeSize = 10, timeX = 0, timeY = 0, stackSize = 10, stackX = 1, stackY = -1, stackPoint = "BOTTOMRIGHT", stackColor = { 1, 1, 1 }, timePoint = "CENTER", timeBaseColor = { 1, 1, 1 }, dispelBorder = true,
                -- Filters: with showAll off only debuffs matching the ticked filters show (match = "any" | "all").
                showAll = true, match = "any",
                showSated = false, -- true: also show the Bloodlust-type exhaustion debuffs
                onlyNonPlayer = false, -- kept for older settings; castBy below is what counts
                castBy = "all", -- "all" | "npc" (hide debuffs cast by players or their pets, e.g. the
                                -- Bloodlust exhaustion) | "me" | "others"
                filters = { nonplayer = false, priority = false, cc = false, bossaura = false,
                            roleaura = false, raid = false, raidcombat = false,
                            dispellable = false, dispeltyped = false },
            },
            dispels = {
                -- showIcons: off by default, the row then only drives highlight, border and dispel-type icons.
                showIcons = false,
                -- Only the types the player can dispel (off: every debuff with a dispel type).
                dispellableOnly = true,
                -- Colour per dispel type (highlight, border, fallback type icons).
                typeColors = { Magic = { 0.2, 0.6, 1 }, Curse = { 0.6, 0, 1 }, Disease = { 0.6, 0.4, 0 },
                               Poison = { 0, 0.6, 0 }, Bleed = { 1, 0.2, 0.6 } },
                enabled = true, max = 3, size = 18, spacing = 2, perRow = 8, lineSpacing = 2,
                point = "TOP", growth = "RIGHT", x = 0, y = 0,
                -- Health bar highlight: "none" | "edge-top" | "edge-bottom" | "fill" | "full".
                highlightType = "edge-bottom", highlightOpacity = 50,
                frameBorder = false, frameBorderThickness = 2,
                typeIcons = true, typeIconSize = 12, typeIconPoint = "BOTTOMRIGHT",
                typeIconGrowth = "LEFT", typeIconX = 0, typeIconY = 4,
                showStacks = true, showCooldown = true, cdStyle = "spiral", showTime = true, timeSize = 10, timeX = 0, timeY = 0, stackSize = 10, stackX = 1, stackY = -1, stackPoint = "BOTTOMRIGHT", stackColor = { 1, 1, 1 }, timePoint = "CENTER", timeBaseColor = { 1, 1, 1 }, dispelBorder = true,
            },
            -- Cooldown rows: `list` = spell IDs; others fall back to Blizzard's classification if `useFilter`.
            defensives = {
                enabled = true, max = 2, size = 16, spacing = 2, perRow = 8, lineSpacing = 2,
                point = "LEFT", growth = "RIGHT", x = 0, y = 6,
                showStacks = false, showCooldown = true, cdStyle = "vertical", showTime = true, timeSize = 10, timeX = 0, timeY = 0, stackSize = 10, stackX = 1, stackY = -1, stackPoint = "BOTTOMRIGHT", stackColor = { 1, 1, 1 }, timePoint = "CENTER", timeBaseColor = { 1, 1, 1 }, useFilter = false,
                list = "48707,444741,48792,55233,101568,212800,187827,207771,22812,22842,61336,1261872,404381,363916,374349,186265,264735,342246,45438,414658,449336,1309793,122783,115203,120954,125174,132578,322507,1241059,498,403876,642,31850,86659,212641,19236,47585,586,193065,27827,31224,5277,1966,185311,108271,260881,108416,104773,132413,387636,118038,184364,190456,1277297,147833,385391,871",
            },
            externals = {
                enabled = true, max = 2, size = 16, spacing = 2, perRow = 8, lineSpacing = 2,
                point = "RIGHT", growth = "LEFT", x = 0, y = 6,
                showStacks = false, showCooldown = true, cdStyle = "vertical", showTime = true, timeSize = 10, timeX = 0, timeY = 0, stackSize = 10, stackX = 1, stackY = -1, stackPoint = "BOTTOMRIGHT", stackColor = { 1, 1, 1 }, timePoint = "CENTER", timeBaseColor = { 1, 1, 1 }, useFilter = false,
                list = "102342,357170,53480,116849,1022,1309794,6940,204018,387804,47788,33206,145629,51052,209426,196718,374227,31821,317929,81782,62618,325174,98008,97463,97462",
            },
            offensives = {
                enabled = false, max = 2, size = 18, spacing = 2, perRow = 8, lineSpacing = 2,
                point = "BOTTOM", growth = "RIGHT", x = 0, y = 4,
                showStacks = false, showCooldown = true, cdStyle = "vertical", showTime = true, timeSize = 10, timeX = 0, timeY = 0, stackSize = 10, stackX = 1, stackY = -1, stackPoint = "BOTTOMRIGHT", stackColor = { 1, 1, 1 }, timePoint = "CENTER", timeBaseColor = { 1, 1, 1 },
                list = "1249658,152279,42650,51271,191427,321067,321068,162264,471306,1217605,473671,1217607,194223,102560,106951,102543,375087,186254,1235388,1285912,19574,288613,1250646,1251703,190319,365350,365362,1247908,1249625,31884,231895,454351,216331,10060,194249,13750,121471,1249810,114050,114051,114052,1219480,466772,442726,1276166,266087,417282,107574,1719,1225789,1241937,1265063,459808,1234189,185422,51690,394095,385627,13877,265187,205180,111685,446035,227847",
            },
            -- Crowd controls use Blizzard's CROWD_CONTROL filter, so there is no spell list.
            crowdControls = {
                enabled = false, max = 3, size = 22, spacing = 2, perRow = 8, lineSpacing = 2,
                point = "CENTER", growth = "RIGHT", x = 0, y = 0,
                showStacks = false, showCooldown = true, cdStyle = "spiral", showTime = true, timeSize = 10, timeX = 0, timeY = 0, stackSize = 10, stackX = 1, stackY = -1, stackPoint = "BOTTOMRIGHT", stackColor = { 1, 1, 1 }, timePoint = "CENTER", timeBaseColor = { 1, 1, 1 }, dispellableOnly = false,
            },
        },
    }
    -- Debuffs 2-4: extra debuff rows with their own filter, position and look (off by default).
    local function extraDebuffs(filter, over)
        local d = CopyTable(t.auras.debuffs)
        d.enabled, d.showAll, d.max = false, false, 2
        d.castBy, d.onlyNonPlayer = "all", false
        for k in pairs(d.filters) do d.filters[k] = false end
        d.filters[filter] = true
        for k, v in pairs(over) do d[k] = v end
        return d
    end
    t.auras.debuffs2 = extraDebuffs("priority", { point = "BOTTOMLEFT", growth = "RIGHT", x = 0, y = 22 })
    t.auras.debuffs3 = extraDebuffs("bossaura", { point = "CENTER", growth = "RIGHT", x = 0, y = 0, size = 24 })
    t.auras.debuffs4 = extraDebuffs("raid", { point = "BOTTOMRIGHT", growth = "LEFT", x = 0, y = 0 })
    -- Defensives & Externals in one row: both spell lists, and Blizzard's classification for either kind.
    t.auras.defext = {
        enabled = false, max = 3, size = 16, spacing = 2, perRow = 8, lineSpacing = 2,
        point = "LEFT", growth = "RIGHT", x = 0, y = 6,
        showStacks = false, showCooldown = true, cdStyle = "vertical", showTime = true, timeSize = 10, timeX = 0, timeY = 0,
        stackSize = 10, stackX = 1, stackY = -1, stackPoint = "BOTTOMRIGHT", stackColor = { 1, 1, 1 },
        timePoint = "CENTER", timeBaseColor = { 1, 1, 1 }, useFilter = false,
        list = t.auras.defensives.list .. "," .. t.auras.externals.list,
    }
    -- Row glow: "off", "icon" (around each icon) or "frame" (around the whole unit frame).
    for _, k in ipairs({ "buffs", "debuffs", "debuffs2", "debuffs3", "debuffs4", "defensives", "externals",
                         "defext", "offensives", "crowdControls" }) do
        local row = t.auras[k]
        if row then
            row.glow, row.glowStyle, row.glowColor = "off", "pixel", { 1, 0.85, 0.2 }
            row.glowSpeed, row.glowLength, row.glowThickness, row.glowOffset = 0.15, 6, 2, 0
        end
    end
    for k, v in pairs(overrides or {}) do
        if type(v) == "table" and type(t[k]) == "table" then
            deepMerge(t[k], v)
        else
            t[k] = v
        end
    end
    return t
end

-- Shared base of the pet-side groups: off, fixed green health color, no role-only indicators.
local function petDefaults(o)
    local t = {
        enabled = false,
        showSolo = true,
        -- Attach to the owner's frame: side, gap and sideways shift.
        attachEnabled = true, attachSide = "RIGHT", attachGap = 2, attachShift = 0,
        -- Hang on the party frames (host*) or the raid frames (raidHost*) instead of a free position.
        hostEnabled = false, hostSide = "RIGHT", hostGap = 4, hostShift = 0,
        raidHostEnabled = false, raidHostSide = "RIGHT", raidHostGap = 4, raidHostShift = 0,
        appearance = { healthColorMode = "custom", healthCustomColor = { 0.35, 0.75, 0.40 } },
        indicators = {
            role = { enabled = false }, leader = { enabled = false },
            readyCheck = { enabled = false }, powerBar = { enabled = false },
        },
    }
    for k, v in pairs(o) do
        if type(v) == "table" and type(t[k]) == "table" then
            for k2, v2 in pairs(v) do t[k][k2] = v2 end
        else
            t[k] = v
        end
    end
    return t
end

N.Defaults = {
    dbVersion = 1,

    editMode = "party", -- party | raid | ownPet | groupPets | npc | spotlight
    lastPetMode = "ownPet", -- the pet-side group the "Pets" switch opens
    -- Areas every profile shares ("global"); the master's linked profiles follow it in the ticked parts.
    profileSync = {
        master = "",
        slaves = { _list = true },
        parts = {
            ["party.size"] = false, ["party.layout"] = false, ["party.position"] = false,
            ["party.appearance"] = true, ["party.indicators"] = true, ["party.auras"] = true, ["party.custom"] = true,
            ["raid.size"] = false, ["raid.layout"] = false, ["raid.position"] = false,
            ["raid.appearance"] = true, ["raid.indicators"] = true, ["raid.auras"] = true, ["raid.custom"] = true,
            ownPet = false, groupPets = false, npc = false, partyTargets = false, spotlight = false, tooltip = false,
            clickCasting = false, targetedSpellBars = false, actions = false, auraSounds = false, tools = false, ping = false,
        },
    },
    profileScope = { tooltip = "profile", clickCasting = "profile", utilities = "profile", spotlight = "profile" },
    -- Test Mode: sections previewed besides the one being edited (the menu next to the button)
    testSections = { party = false, raid = false, ownPet = false, groupPets = false, npc = false, spotlight = false },

    locale = "auto", -- "auto" follows the game client
    locked = true,
    moverMode = "always", -- how the move handle is dragged: always | alt
    moverSize = 100,
    moverStyle = "label", -- label (name tab) | bar
    moverHover = false, -- handle visible only under the mouse
    moverBarWidth = 100,
    moverX = 0,
    moverY = 0,
    translitNames = false,
    debugMode = false, -- Debug console: log internal messages
    bindingPresets = { _list = true }, -- Click-Casting presets: [class][name] = bindings, shared by all profiles
    welcomeMessage = true, -- the "Nucleus loaded - version X" line in the chat at login / reload
    showWhatsNew = true,   -- show the "What's new" window once after an update
    whatsNewSeen = "",     -- the version whose "What's new" window was shown last
    blizzFilterOff = false, -- one-time migration: Blizzard-classification fallback switched off
    -- One-time migrations (Core/Database.lua): the flag has to be listed here or the load prunes it.
    timeColorDefaulted = false,
    decimalsOffDefaulted = false,
    glowDistanceReset = false,
    glowProcRemoved = false,
    localeAutoDefaulted = false,
    petAttachDefaulted = false,

    -- Inline preview settings of the Indicators tab; global, an editing tool.
    previewSettings = {
        cycleHealth = false,    -- rotate the mock health through dead/25/50/75/100%
        showAllEnabled = false, -- show every currently-enabled indicator, not just this one
        healthPercent = 100,    -- static mock health % used whenever cycleHealth is off
    },
    fontScale = 1.0,
    fontUI = "nucleus",    -- General > Fonts: options window font
    fontFrame = "nucleus", -- General > Fonts: font of every text on the frames
    uiScale = 1.0,
    accentColor = { 0.20, 0.55, 0.95 },

    core = {
        rangeUpdateInterval = 0.15,
    },

    tooltip = {
        enabled = true,
        hideInCombat = false,
        auras = false, -- tooltips of single auras when hovering their icons
        anchor = "frame", -- frame | cursor | default
    },

    minimap = {
        hide = false,
        angle = 205,    -- own button (used when LibDBIcon is missing)
        minimapPos = 205, -- LibDBIcon's position
    },

    party = groupDefaults({
        spacing = 3,
        indicators = { powerBar = { enabled = true } },
    }),

    raid = groupDefaults({
        showSolo = false,
        groupFilter = { true, true, true, true, true, true, true, true },
        -- How many groups are shown at most (1-8): groups 1..maxGroups.
        maxGroups = 8,
        -- Groups per row: 0 = the groups in one run; 1-8 puts every raid group on its own slot of a grid.
        groupsPerRow = 8, rowSpacing = 3, groupFlow = "RIGHT_DOWN",
        -- Parts that use the Group's settings (see Profiles.lua): one switch per part.
        link = { appearance = false, indicators = false, auras = false, customIndicators = false },
        groupNames = { enabled = false, position = "above", size = 11, x = 0, y = 0, color = { 1, 1, 1 } },
    }),

    -- Pet side: own pet, group pets and NPC companions, same structure as party / raid.
    ownPet = groupDefaults(petDefaults({ width = 80, height = 26, x = 24, y = -420 })),
    groupPets = groupDefaults(petDefaults({
        width = 66, height = 22, spacing = 2, x = 24, y = -470,
        unitsPerColumn = 5, maxColumns = 2,
    })),
    npc = groupDefaults(petDefaults({
        moveCompanions = false, -- take party NPC companions out of the group frames and show them here
        width = 80, height = 30, spacing = 2, x = 24, y = -540,
        appearance = { healthCustomColor = { 0.40, 0.60, 1.00 } },
    })),

    -- Party targets (roles = whose target shows).
    partyTargets = groupDefaults(petDefaults({
        width = 66, height = 22, x = 24, y = -500,
        roles = { TANK = true, HEALER = false, DAMAGER = false },
        appearance = { healthCustomColor = { 0.80, 0.30, 0.30 } },
    })),

    -- Spotlight `units`: { type = "target"|"targettarget"|"focus" | "role" | "name", value }.
    spotlight = groupDefaults({
        enabled = false,
        showSolo = true,
        width = 80, height = 40, spacing = 3,
        x = 24, y = -640,
        hostEnabled = false, hostSide = "RIGHT", hostGap = 4, hostShift = 0,
        raidHostEnabled = false, raidHostSide = "RIGHT", raidHostGap = 4, raidHostShift = 0,
        units = { _list = true },
        indicators = { powerBar = { enabled = true } },
    }),

    actions = {
        enabled = true,
        speed = 1,
        list = {
            { spell = 6262,    anim = "sweep", color = { 0.40, 1.00, 0.00 } }, -- Healthstone
            { spell = 1234768, anim = "sweep", color = { 1.00, 0.10, 0.10 } }, -- Silvermoon Health Potion
            { spell = 1236616, anim = "rise",  color = { 1.00, 1.00, 0.00 } }, -- Light's Potential
        },
    },

    -- Aura sounds: list of { spell, sound, trigger = added | removed | stacks, who = all | me }
    auraSounds = {
        enabled = false,
        list = { _list = true }, -- _list keeps the entries on load, an empty default would drop them
        custom = { _list = true }, -- { name, file }, file relative to Interface\AddOns
    },

    -- Utilities: movable displays; positions are offsets from the screen centre.
    tools = {
        readyPull = {
            enabled = true, fadeOut = false, backdrop = false, background = { 0.05, 0.05, 0.07 }, border = 1,
            borderColor = { 0.20, 0.20, 0.25 }, alpha = 1, strata = "MEDIUM", showReady = true, showPull = true, onlyLeader = true,
            orientation = "horizontal", width = 64, height = 22, gap = 4,
            pullTime = 10, pullMethod = "default", -- default | dbm | bw | mrt
            pullTimerMode = "remaining", pullFinishText = "none", -- remaining | elapsed | elapsedTotal | remainingTotal; go | zero | none
            point = "CENTER", x = 0, y = -120,
        },
        battleRes = {
            enabled = true, fadeOut = false, backdrop = false, background = { 0.05, 0.05, 0.07 }, border = 1,
            borderColor = { 0.20, 0.20, 0.25 }, alpha = 1, strata = "MEDIUM", iconSize = 30, showTimer = true,
            point = "CENTER", x = 0, y = -160,
        },
        marks = {
            enabled = false, fadeOut = false, backdrop = false, background = { 0.05, 0.05, 0.07 }, border = 1,
            borderColor = { 0.20, 0.20, 0.25 }, alpha = 1, strata = "MEDIUM", mode = "target", -- target | world | both
            orientation = "horizontal", size = 22, spacing = 2,
            showClear = true, onlyLeader = true,
            point = "CENTER", x = 0, y = -200,
        },
        -- Death Report: says when a group member dies; output = "local" | "group".
        deathReport = { enabled = false, output = "local", encounterOnly = true, leaderOnly = true, rolesOnly = false },
    },

    -- Targeted spell bars: a floating stack of enemy casts aimed at group members; global.
    targetedSpellBars = {
        enabled = false,
        where = "both",
        num = 5,
        width = 220, height = 22,
        orientation = "top-to-bottom",
        showIcon = true, showSpellName = true, showTargetText = true,
        color = { 0.62, 0.42, 0.95 },
        importantColor = { 1.00, 0.80, 0.20 },
        point = "CENTER", x = 0, y = 120,
    },

    -- Retail-only: a short pulse on a frame when a groupmate pings that unit.
    ping = {
        enabled = true,
        duration = 4, -- how long the icon stays up; Blizzard's own is a few seconds
        scale = 1.0,  -- multiplies the auto-sized icon (proportional to frame size)
        x = 0, y = 0,
    },

    -- Click-casting: global; kind = "none" | "spell" | "item" | "macro" | "general".
    clickCasting = {
        -- "off" | "normal" | "combat" (also the class's combat resurrection)
        smartRes = "off",
        selfCastDeclined = "",
        highestRank = false,

        -- Left select and right menu: ordinary rows the user can change.
        bindings = {
            { modifier = "none", button = "LeftButton",  kind = "general", value = "target" },
            { modifier = "none", button = "RightButton", kind = "general", value = "menu" },
        },
        -- `bindings` = list of the played class; other classes live in byClass.
        migrated = false,
        -- [specID] = list; a spec without one uses its class's list. _list keeps it out of default merging.
        bySpec = { _list = true },
        byClass = {
            DRUID = {
                { modifier = "none", button = "LeftButton",  kind = "general", value = "target" },
                { modifier = "none", button = "RightButton", kind = "general", value = "menu" },
            },
            HUNTER = {
                { modifier = "none", button = "LeftButton",  kind = "general", value = "target" },
                { modifier = "none", button = "RightButton", kind = "general", value = "menu" },
            },
            MAGE = {
                { modifier = "none", button = "LeftButton",  kind = "general", value = "target" },
                { modifier = "none", button = "RightButton", kind = "general", value = "menu" },
            },
            PALADIN = {
                { modifier = "none", button = "LeftButton",  kind = "general", value = "target" },
                { modifier = "none", button = "RightButton", kind = "general", value = "menu" },
            },
            PRIEST = {
                { modifier = "none", button = "LeftButton",  kind = "general", value = "target" },
                { modifier = "none", button = "RightButton", kind = "general", value = "menu" },
            },
            ROGUE = {
                { modifier = "none", button = "LeftButton",  kind = "general", value = "target" },
                { modifier = "none", button = "RightButton", kind = "general", value = "menu" },
            },
            SHAMAN = {
                { modifier = "none", button = "LeftButton",  kind = "general", value = "target" },
                { modifier = "none", button = "RightButton", kind = "general", value = "menu" },
            },
            WARLOCK = {
                { modifier = "none", button = "LeftButton",  kind = "general", value = "target" },
                { modifier = "none", button = "RightButton", kind = "general", value = "menu" },
            },
            WARRIOR = {
                { modifier = "none", button = "LeftButton",  kind = "general", value = "target" },
                { modifier = "none", button = "RightButton", kind = "general", value = "menu" },
            },
        },
    },
}

-- The spell lists, raid buffs, potions and the class-only icon come from Core/Classic.lua.
do
    local C = N.Classic
    for _, key in ipairs({ "party", "raid", "ownPet", "groupPets", "npc", "partyTargets", "spotlight" }) do
        local g = N.Defaults[key]
        g.auras.defensives.list = C.LIST.defensives
        g.auras.externals.list = C.LIST.externals
        g.auras.defext.list = C.LIST.defensives .. "," .. C.LIST.externals
        g.auras.offensives.list = C.LIST.offensives
        g.auras.buffs.list = C.LIST.buffs
        local mb = g.indicators.missingBuffs
        mb.buffs = {}
        for _, buff in ipairs(C.BUFFS) do mb.buffs[buff.key] = C.BUFF_DEFAULT[buff.key] == true end
        for _, sub in ipairs(C.BLESSINGS) do mb.buffs[sub.key] = C.BUFF_DEFAULT[sub.key] ~= false end
        g.indicators.classSpec.mode = "class" -- Forever has one specialization per class
    end
    -- Party targets: only name and health text, no aura rows.
    for k, o in pairs(N.Defaults.partyTargets.indicators) do
        if type(o) == "table" and k ~= "name" and k ~= "healthText" then o.enabled = false end
    end
    for _, o in pairs(N.Defaults.partyTargets.auras) do
        if type(o) == "table" then o.enabled = false end
    end
    N.Defaults.actions.list = C.ACTIONS
end
