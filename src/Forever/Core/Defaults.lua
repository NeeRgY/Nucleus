local _, ns = ...
local N = ns.N

-- Default SavedVariables layout for the Retail client. Stored in
-- NucleusDB_Mainline (see TOC). One flat profile for now; a profile manager
-- can wrap this later without changing the schema.
--
-- party/raid are fully independent: layout, appearance and indicators all live
-- under each so editing one group type never touches the other. Only `general`
-- and `core` are shared.

-- The roles each class can play, in the order the options list the classes.
-- The power bar can be switched on / off per class and role.
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
        hideBlizzard = true,      -- suppress the matching Blizzard frames
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

        -- Own order of the frames (party / raid): when `enabled`, roles come in the
        -- order first / second / third (anyone without a role last); `pinned` =
        -- optional names (comma separated) that always come first, in that order.
        ordering = { enabled = false, first = "TANK", second = "HEALER", third = "DAMAGER", pinned = "" },

        -- Indicators the player created (Indicators > "+"): a list of entries,
        -- see Frames/CustomIndicators.lua for the fields.
        customIndicators = { _list = true },

        appearance = {
            outOfRangeAlpha = 0.45,
            barTexture = "nucleus",          -- "flat" | "gradient" | "modern" | "nucleus"
            healthColorMode = "class",       -- "class" | "custom" | "gradient"
            healthCustomColor = { 0.20, 0.55, 0.95 },
            healthLossColor = { 0.065, 0.068, 0.075 },
            -- Shield / heal-absorb / heal-prediction overlays (Appearance >
            -- Shield). style is "flat" | "striped" (heal-prediction has no
            -- style of its own - it's always a plain translucent wash).
            showOvershield = true,
            absorb     = { enabled = true, style = "striped", opacity = 0.35, color = { 1.00, 1.00, 1.00 }, invertFill = false },
            overshieldColor = { 0.75, 0.90, 1.00 },
            healAbsorb = { enabled = true, style = "flat", opacity = 0.75, color = { 0.55, 0.20, 0.75 } },
            healPredict = { enabled = true, opacity = 0.30, color = { 1.00, 1.00, 1.00 } },
            -- Same default look as before (accentBright blue outline, plain
            -- white hover), now its own setting instead of following the
            -- options-window accent color.
            targetBorder = { color = { 0.42, 0.70, 1.00 }, thickness = 1 },
            hoverBorder  = { color = { 1.00, 1.00, 1.00 }, thickness = 1 },
            -- The time text of aura icons turns `color` once less than `seconds` are left
            -- Below `decimals` seconds (0 = never) the time counts in tenths ("3.3").
            timeColor    = { enabled = true, seconds = 3, color = { 1.00, 0.15, 0.15 }, decimals = 0 },
            -- The border around every frame (inside its edge).
            frameBorder  = { enabled = true, color = { 0.00, 0.00, 0.00 }, thickness = 1 },
            -- Cell-style: dim the whole frame (reusing outOfRangeAlpha) once
            -- a unit's health reaches threshold, so healthy raid members recede.
            healthFade = { enabled = false, threshold = 1.0 },
        },
        -- Every on-frame element is an entry here and gets its own options tab:
        -- enabled + placement (x/y) + type-specific fields.
        indicators = {
            custom     = { enabled = true }, -- switch for the custom indicators as a whole
            name       = { enabled = true,  size = 11, x = 0, y = 0, color = { 0.92, 0.92, 0.94 }, position = "center", colorMode = "custom",
                           nameFormat = "full" }, -- Forever: "full" (First Surname) | "first" | "last"
            -- format/textFormat "custom" uses customFormat instead: a typed
            -- template with {p}=percent, {v}=value, {m}=max, {d}=deficit.
            healthText = { enabled = true,  size = 10, x = 0, y = 0, color = { 0.85, 0.85, 0.87 },
                           format = "percent", customFormat = "{p}%",
                           position = "center", colorMode = "custom" },
            -- Power Bar: the bar itself (height, which roles get one, offset) and
            -- its optional text (format, position on the health bar, colour).
            powerBar   = { enabled = false, height = 4, x = 0, y = 0,
                           filter = powerFilterDefaults(), -- [class][role] = show the bar
                           text = false, textFormat = "percent", customFormat = "{p}%",
                           textSize = 9, textPosition = "bottom", textX = 0, textY = 0,
                           textColorMode = "power", textColor = { 1, 1, 1 } },
            -- Status: a small pill (rounded badge) that names the unit's state -
            -- Offline / AFK / Feign Death / Ghost / Dead and the three summon states -
            -- in a colour per state, with an optional running timer (Offline / AFK).
            -- anchor = top / center / bottom of the health bar, align = left / center /
            -- right along it. `show` switches individual states on or off.
            status     = { enabled = true, size = 11, anchor = "bottom", align = "center", y = 2,
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
            -- Role icon: shape = "square" (default) or "circle"; showTank/Healer/Damager
            -- pick which roles get one.
            role       = { enabled = true,  size = 11, x = 0, y = 0, shape = "square",
                           showTank = true, showHealer = true, showDamager = true, hideInCombat = false,
                           showSolo = true }, -- showSolo: your own role (from your spec) while not in a group
            -- Class / spec icon: mode = "class" | "spec" | "both"; off by default. x = 13
            -- puts it right next to the role icon (top left).
            classSpec  = { enabled = false, size = 12, x = 13, y = 0, mode = "spec" },
            leader     = { enabled = true,  size = 10, x = 0, y = 0 },
            readyCheck = { enabled = true,  size = 16, x = 0, y = 0 },
            raidMarker    = { enabled = true,  size = 14, x = 0,  y = 0 },
            -- Status Icon: show = which kinds of icon may appear (see
            -- Indicators.statusIconKinds).
            statusIcon    = { enabled = true,  size = 24, x = 0,  y = 0,
                              show = { otherParty = true, incomingRez = true, rezDebuff = true,
                                       soulstone = true, summon = true, phase = true,
                                       bgFlag = true, bgOrb = true } },
            combatIcon    = { enabled = true,  size = 12, x = -2, y = 2 },
            targetCounter = { enabled = false, size = 11, x = 0,  y = -2, color = { 1.00, 0.85, 0.30 } },
            -- Absorb Text: format = "short" (12K) | "full" (12,345) | "percent" of max health
            absorbText    = { enabled = false, size = 10, x = 0,  y = 8,  color = { 0.75, 0.90, 1.00 },
                              position = "center", colorMode = "custom", format = "short" },
            -- Private Auras (boss mechanics Blizzard draws itself): up to 5 slots in a
            -- row, anchored at one of nine spots on the frame. Blizzard also draws the
            -- red border around each icon; borderScale scales it.
            privateAura   = { enabled = true, num = 2, size = 18, spacing = 1, position = "top",
                              growth = "RIGHT", x = 0, y = 3, showCountdownFrame = true,
                              showCountdownNumbers = false, borderScale = 1 },
            -- Shield Bar: a thin bar on the bottom / top edge of the health bar showing
            -- the shield as a fraction of max health; growFrom = "left" | "right".
            shieldBar     = { enabled = false, height = 4, position = "bottom", growFrom = "left", x = 0, y = 0,
                              color = { 1.00, 1.00, 1.00 }, alpha = 0.8, onlyOvershield = false },
            -- Health Thresholds: thin marks on the health bar at chosen health
            -- percentages (e.g. an execute range). A list of { pct, color }.
            healthThresholds = { enabled = false, thickness = 1,
                                 thresholds = { { pct = 90, color = { 1.00, 0.00, 0.00 } } } },
            -- Aggro Border: warnColor = orange "almost aggro", tankColor = red "aggro"
            -- (Blizzard's threat colours, as Cell shows them); gradient = fade inward.
            aggroBorder   = { enabled = true, thickness = 2, gradient = true,
                              warnColor = { 1.00, 0.60, 0.00 }, tankColor = { 1.00, 0.00, 0.00 } },
            -- Level Text: format = "full" (Level 80) | "short" (Lvl 80) | "number" (80)
            levelText     = { enabled = false, size = 10, x = 0, y = -16, color = { 0.85, 0.85, 0.87 }, format = "full" },
            -- Missing Buffs: an icon for every raid buff the unit lacks (only checked
            -- out of combat when hideInCombat is on). `buffs` switches each buff on/off.
            missingBuffs  = { enabled = false, size = 13, spacing = 1, position = "bottomright",
                              growth = "LEFT", x = 0, y = 4, hideInCombat = true,
                              buffs = { fortitude = true, intellect = true, wild = true,
                                        shout = true, skyfury = true, bronze = true } },
        },
        -- On-frame aura icons. buffs/debuffs are independent rows anchored to a
        -- frame corner and grown in a chosen direction.
        auras = {
            buffs = {
                enabled = false, max = 3, size = 15, spacing = 2,
                point = "TOPRIGHT", growth = "LEFT", x = 0, y = 0,
                showStacks = true, showCooldown = true, cdStyle = "spiral", showTime = true, timeSize = 10, timeX = 0, timeY = 0, stackSize = 10, stackX = 1, stackY = -1, onlyMine = true,
                -- useList: only the spells in `list` (healing buffs; the options show your
                -- own class). Off = every buff.
                useList = true,
                list = "1278914,33763,419207,1227806,8936,419287,774,419204,155777,474754,474750,48438,419344,355941,355936,382614,376788,364343,373267,366155,367364,409895,450769,450521,450711,450526,450531,1292922,124682,119611,115175,1260617,198533,156910,53563,200025,1244893,431381,156322,461432,432502,469703,194384,77489,17,1246768,1254306,1300008,41635,139,1253593,1300009,383648,974,444490,61295,360827,395152,395296,410089",
            },
            debuffs = {
                enabled = true, max = 3, size = 18, spacing = 2,
                point = "BOTTOMLEFT", growth = "RIGHT", x = 0, y = 0,
                showStacks = true, showCooldown = true, cdStyle = "spiral", showTime = true, timeSize = 10, timeX = 0, timeY = 0, stackSize = 10, stackX = 1, stackY = -1, dispelBorder = true,
                -- Filters: with showAll off only debuffs matching the ticked filters
                -- show (match = "any" | "all").
                showAll = true, match = "any",
                filters = { nonplayer = false, priority = false, cc = false, bossaura = false,
                            roleaura = false, raid = false, raidcombat = false,
                            dispellable = false, dispeltyped = false },
            },
            dispels = {
                -- showIcons: the debuffs' own spell icons. Off by default: this row then
                -- only drives the highlight, border and dispel-type icons below.
                showIcons = false,
                -- Only the types the player can dispel (off: every debuff with a dispel type).
                dispellableOnly = true,
                -- Colour per dispel type (highlight, border, fallback type icons).
                typeColors = { Magic = { 0.2, 0.6, 1 }, Curse = { 0.6, 0, 1 }, Disease = { 0.6, 0.4, 0 },
                               Poison = { 0, 0.6, 0 }, Bleed = { 1, 0.2, 0.6 } },
                enabled = true, max = 3, size = 18, spacing = 2,
                point = "TOP", growth = "RIGHT", x = 0, y = 0,
                -- Highlight on the health bar: "none" | "edge-top" | "edge-bottom" | "fill" | "full"
                -- (opacity applies to fill / full). Border + dispel-type icons as in Cell.
                highlightType = "edge-bottom", highlightOpacity = 50,
                frameBorder = false, frameBorderThickness = 2,
                typeIcons = true, typeIconSize = 12, typeIconPoint = "BOTTOMRIGHT",
                typeIconGrowth = "LEFT", typeIconX = 0, typeIconY = 4,
                showStacks = true, showCooldown = true, cdStyle = "spiral", showTime = true, timeSize = 10, timeX = 0, timeY = 0, stackSize = 10, stackX = 1, stackY = -1, dispelBorder = true,
            },
            -- Cooldown rows. `list` = spell IDs this row shows. When an aura's
            -- spell ID is readable the list decides; when the game hides it (some
            -- situations on Midnight) `useFilter` falls back to Blizzard's own
            -- classification (BIG_DEFENSIVE / EXTERNAL_DEFENSIVE). Defensives sit
            -- on the far left of the frame, externals on the far right.
            defensives = {
                enabled = true, max = 2, size = 16, spacing = 2,
                point = "LEFT", growth = "RIGHT", x = 0, y = 6,
                showStacks = false, showCooldown = true, cdStyle = "vertical", showTime = true, timeSize = 10, timeX = 0, timeY = 0, stackSize = 10, stackX = 1, stackY = -1, useFilter = true,
                list = "48707,444741,48792,55233,101568,212800,187827,207771,22812,22842,61336,1261872,404381,363916,374349,186265,264735,342246,45438,414658,449336,1309793,122783,115203,120954,125174,132578,322507,1241059,498,403876,642,31850,86659,212641,19236,47585,586,193065,27827,31224,5277,1966,185311,108271,260881,108416,104773,132413,387636,118038,184364,190456,1277297,147833,385391,871",
            },
            externals = {
                enabled = true, max = 2, size = 16, spacing = 2,
                point = "RIGHT", growth = "LEFT", x = 0, y = 6,
                showStacks = false, showCooldown = true, cdStyle = "vertical", showTime = true, timeSize = 10, timeX = 0, timeY = 0, stackSize = 10, stackX = 1, stackY = -1, useFilter = true,
                list = "102342,357170,53480,116849,1022,1309794,6940,204018,387804,47788,33206,145629,51052,209426,196718,374227,31821,317929,81782,62618,325174,98008,97463,97462",
            },
            offensives = {
                enabled = false, max = 2, size = 18, spacing = 2,
                point = "BOTTOM", growth = "RIGHT", x = 0, y = 4,
                showStacks = false, showCooldown = true, cdStyle = "vertical", showTime = true, timeSize = 10, timeX = 0, timeY = 0, stackSize = 10, stackX = 1, stackY = -1,
                list = "1249658,152279,42650,51271,191427,321067,321068,162264,471306,1217605,473671,1217607,194223,102560,106951,102543,375087,186254,1235388,1285912,19574,288613,1250646,1251703,190319,365350,365362,1247908,1249625,31884,231895,454351,216331,10060,194249,13750,121471,1249810,114050,114051,114052,1219480,466772,442726,1276166,266087,417282,107574,1719,1225789,1241937,1265063,459808,1234189,185422,51690,394095,385627,13877,265187,205180,111685,446035,227847",
            },
            -- Crowd controls come from Blizzard's own CROWD_CONTROL aura filter -
            -- there is deliberately no spell list.
            crowdControls = {
                enabled = false, max = 3, size = 22, spacing = 2,
                point = "CENTER", growth = "RIGHT", x = 0, y = 0,
                showStacks = false, showCooldown = true, cdStyle = "spiral", showTime = true, timeSize = 10, timeX = 0, timeY = 0, stackSize = 10, stackX = 1, stackY = -1, dispellableOnly = false,
            },
        },
    }
    for k, v in pairs(overrides or {}) do
        if type(v) == "table" and type(t[k]) == "table" then
            deepMerge(t[k], v)
        else
            t[k] = v
        end
    end
    return t
end

-- Starting point shared by the pet-side groups: off by default, a fixed green
-- health colour (pets have no useful class colour) and no role-only indicators.
local function petDefaults(o)
    local t = {
        enabled = false,
        showSolo = true,
        -- Attach: bind the pet frame to its owner's frame (ownPet, groupPets).
        -- attachSide = RIGHT | LEFT | TOP | BOTTOM of the owner frame; attachGap =
        -- distance from it; attachShift = sideways shift.
        attachEnabled = true, attachSide = "RIGHT", attachGap = 2, attachShift = 0,
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

    -- Which group type the options window is currently editing.
    editMode = "party", -- party | raid | ownPet | groupPets | npc | spotlight
    lastPetMode = "ownPet", -- the pet-side group the "Pets" switch opens

    locale = "deDE",
    locked = true, -- frames locked in place (drag anchors hidden)
    translitNames = false, -- write out Cyrillic player names in Latin letters
    welcomeMessage = true, -- the "Nucleus loaded - version X" line in the chat at login / reload

    -- Indicators tab: the little inline preview above each indicator's own
    -- settings. Global (not per party/raid) - it's a tool for editing, not a
    -- frame appearance setting.
    previewSettings = {
        cycleHealth = false,    -- rotate the mock health through dead/25/50/75/100%
        showAllEnabled = false, -- show every currently-enabled indicator, not just this one
        healthPercent = 100,    -- static mock health % used whenever cycleHealth is off
    },
    fontScale = 1.0, -- General > Interface: text size inside the options windows
    uiScale = 1.0,   -- General > Interface: scales the whole options window
    accentColor = { 0.20, 0.55, 0.95 }, -- General > Interface: options window highlight color

    core = {
        rangeUpdateInterval = 0.15,
    },

    tooltip = {
        enabled = true,
        hideInCombat = false,
    },

    minimap = {
        hide = false,
        angle = 205,
    },

    party = groupDefaults({
        spacing = 3,
        indicators = { powerBar = { enabled = true } },
    }),

    raid = groupDefaults({
        showSolo = false,
        -- Which raid groups (1-8) get frames.
        groupFilter = { true, true, true, true, true, true, true, true },
        -- How many groups are shown at most (1-8): groups 1..maxGroups.
        maxGroups = 8,
        -- A "Group n" text on the first frame of each raid group (Group by: Raid group).
        groupNames = { enabled = false, position = "above", size = 11, x = 0, y = 0, color = { 1, 1, 1 } },
    }),

    -- Pets / companions: three more frame groups with the same structure as
    -- party / raid (so every indicator and aura setting works for them).
    -- ownPet: your own pet; groupPets: pets of group members; npc: NPC
    -- companions in your party (Brann in Delves, follower-dungeon allies).
    ownPet = groupDefaults(petDefaults({ width = 80, height = 26, x = 24, y = -420 })),
    groupPets = groupDefaults(petDefaults({
        width = 66, height = 22, spacing = 2, x = 24, y = -470,
        unitsPerColumn = 5, maxColumns = 2,
    })),
    npc = groupDefaults(petDefaults({
        width = 80, height = 30, spacing = 2, x = 24, y = -540,
        appearance = { healthCustomColor = { 0.40, 0.60, 1.00 } },
    })),

    -- Spotlight: a small group of frames you choose yourself (the tanks, a player by
    -- name, your target / focus, ...), the same structure as party / raid. `units` =
    -- the list of entries: { type = "target" | "targettarget" | "focus" } or
    -- { type = "role", value = "TANK" | "HEALER" } or { type = "name", value = "Name" }.
    spotlight = groupDefaults({
        enabled = false,
        showSolo = true,
        width = 80, height = 40, spacing = 3,
        x = 24, y = -640,
        units = { _list = true },
        indicators = { powerBar = { enabled = true } },
    }),

    -- Actions (after Cell): a short animation on a group member's frame when they
    -- use a listed spell (potions, Healthstone, ...). Each entry: spell = spell ID,
    -- anim = "sweep" | "diagonal" | "rise", color = {r, g, b}.
    actions = {
        enabled = true,
        speed = 1,
        list = {
            { spell = 6262,    anim = "sweep", color = { 0.40, 1.00, 0.00 } }, -- Healthstone
            { spell = 1234768, anim = "sweep", color = { 1.00, 0.10, 0.10 } }, -- Silvermoon Health Potion
            { spell = 1236616, anim = "rise",  color = { 1.00, 1.00, 0.00 } }, -- Light's Potential
        },
    },

    -- Utilities: free-standing, movable displays (positions are offsets from the
    -- screen centre). readyPull: Ready Check + Pull Timer buttons; battleRes:
    -- combat-resurrection charges; marks: target / world marker bar.
    tools = {
        readyPull = {
            enabled = true, showReady = true, showPull = true, onlyLeader = true,
            orientation = "horizontal", width = 64, height = 22, gap = 4,
            pullTime = 10, pullMethod = "default", -- default | dbm | bw | mrt
            point = "CENTER", x = 0, y = -120,
        },
        battleRes = {
            enabled = true, iconSize = 30, showTimer = true,
            point = "CENTER", x = 0, y = -160,
        },
        marks = {
            enabled = false, mode = "target", -- target | world | both
            orientation = "horizontal", size = 22, spacing = 2,
            showClear = true, onlyLeader = true,
            point = "CENTER", x = 0, y = -200,
        },
    },

    -- Floating stack of enemy cast bars showing who each cast is aimed at.
    -- Global (not per party/raid): it is a free-standing display, not a part
    -- of any unit frame. orientation = top-to-bottom | bottom-to-top |
    -- left-to-right | right-to-left; where = both | party | raid.
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
        x = 0, y = 0, -- offset from the frame's center
    },

    -- Modifier+click -> spell/item/macro directly from a frame. Global (not
    -- per party/raid) - click-cast bindings are almost always wanted
    -- identically everywhere. kind = "none" | "spell" | "item" | "macro".
    clickCasting = {

        -- The two clicks every frame needs: left selects, right opens the menu.
        -- Both are ordinary rows the user can change or delete.
        bindings = {
            { modifier = "none", button = "LeftButton",  kind = "general", value = "target" },
            { modifier = "none", button = "RightButton", kind = "general", value = "menu" },
        },
        -- Bindings are kept per class: `bindings` above is whatever list belongs
        -- to the class being played (set at login, see ClickCasting.SelectClass);
        -- the other classes keep theirs here. `migrated` marks that the old shared
        -- list was split up.
        migrated = false,
        -- Own bindings for single specializations: [specID] = list. A specialization
        -- without an entry uses its class's list (byClass). _list keeps the table
        -- from being merged with / pruned against the defaults.
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

-- Forever (Classic): the spell lists, raid buffs, potions and the class-only icon come
-- from Core/Classic.lua instead of Retail's data.
do
    local C = N.Classic
    for _, key in ipairs({ "party", "raid", "ownPet", "groupPets", "npc", "spotlight" }) do
        local g = N.Defaults[key]
        g.auras.defensives.list = C.LIST.defensives
        g.auras.externals.list = C.LIST.externals
        g.auras.offensives.list = C.LIST.offensives
        g.auras.buffs.list = C.LIST.buffs
        local mb = g.indicators.missingBuffs
        mb.buffs = {}
        for _, buff in ipairs(C.BUFFS) do mb.buffs[buff.key] = C.BUFF_DEFAULT[buff.key] == true end
        g.indicators.classSpec.mode = "class" -- Forever has one specialization per class
    end
    N.Defaults.actions.list = C.ACTIONS
end
