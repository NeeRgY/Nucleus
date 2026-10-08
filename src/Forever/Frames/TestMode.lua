local _, ns = ...
local N = ns.N
local UF = N.UnitFrame

-- Preview mode: insecure mock unit frames so layout and look can be tuned without a group. Same
-- visual layer as the real frames (UF.CreateVisual), only the data is fake.

local TM = {}
N.TestMode = TM

local active = false
local containers = {}   -- key -> Frame
local pools = {}        -- key -> { buttons }

-- Forever characters have a surname, so the sample frames show "First Surname" and the
-- Name indicator's format (full / first / last) can be tried.
local NAMES = {
    "Ashvane Stormrider", "Brill Oakheart", "Cindra Ashfall", "Dorn Ironbrow", "Eyala Moonwhisper",
    "Fenn Brightwater", "Gwyn Duskwood", "Harlow Stonefist", "Isolde Frostmere", "Joro Blackthorn",
    "Kessa Dawnbringer", "Lyle Greycloak", "Mira Silverbrook", "Nils Wolfsbane", "Orin Highmountain",
    "Perah Sunstrider", "Quill Marshwalker", "Roan Emberstone", "Sable Nightshade", "Tavin Redwater",
    "Ula Windrunner", "Vex Shadowmend", "Wren Goldleaf", "Xander Ravenhill",
}
local CLASSES = N.Classic.CLASSES

-- The power each class runs on in Classic (a Druid changes with the form; the mock
-- shows the caster form, a Hunter has mana).
local CLASS_POWER = {
    WARRIOR = "RAGE", PALADIN = "MANA", HUNTER = "MANA", ROGUE = "ENERGY", PRIEST = "MANA",
    SHAMAN = "MANA", MAGE = "MANA", WARLOCK = "MANA", DRUID = "MANA",
}
local function mockPower(class)
    return CLASS_POWER[class] or "MANA"
end
local MOCK_BUFF_ICONS = { 135953, 136041, 135987, 136052 }
local MOCK_DEBUFFS = {
    { icon = 136207, dispelName = "Magic" },
    { icon = 132090, dispelName = "Poison" },
    { icon = 136182, dispelName = "Curse" },
    { icon = 132155, dispelName = "Disease" },
    { icon = 135812, dispelName = nil },
}

local function mockAuras(i)
    local now = GetTime()
    local buffs, debuffs, dispels = {}, {}, {}
    local defensives, externals, offensives, crowd = {}, {}, {}, {}
    for k = 1, (i % 4) do
        buffs[k] = {
            icon = MOCK_BUFF_ICONS[(k - 1) % #MOCK_BUFF_ICONS + 1],
            applications = (k == 1) and 5 or 2,
            duration = 30, expirationTime = now + 30 - k * 5,
        }
    end
    for k = 1, (i % 3) do
        local d = MOCK_DEBUFFS[(i + k) % #MOCK_DEBUFFS + 1]
        debuffs[k] = {
            icon = d.icon, dispelName = d.dispelName,
            applications = (k == 2) and 3 or 2,
            duration = 18, expirationTime = now + 18 - k * 4,
        }
    end
    if i % 2 == 0 then
        local d = MOCK_DEBUFFS[i % 4 + 1]
        dispels[1] = { icon = d.icon, dispelName = d.dispelName, applications = 3,
                       duration = 12, expirationTime = now + 9 }
    end
    if i % 3 == 1 then
        defensives[1] = { icon = 135841, applications = 3, duration = 10, expirationTime = now + 7 }
    end
    if i % 4 == 2 then
        externals[1] = { icon = 135936, applications = 3, duration = 8, expirationTime = now + 5, sourceUnit = "player" }
    end
    if i % 5 == 0 then
        offensives[1] = { icon = 136048, applications = 3, duration = 20, expirationTime = now + 12 }
    end
    if i % 6 == 1 then
        crowd[1] = { icon = 136071, dispelName = "Magic", applications = 3, duration = 8, expirationTime = now + 5 }
    end
    return buffs, debuffs, dispels, defensives, externals, offensives, crowd
end

local function mockFor(i)
    local buffs, debuffs, dispels, defensives, externals, offensives, crowd = mockAuras(i)
    return {
        buffs = buffs,
        debuffs = debuffs,
        dispels = dispels,
        defensives = defensives,
        externals = externals,
        offensives = offensives,
        crowd = crowd,
        outOfRange = (i == 3) or (i % 7 == 4),
        raidMarker = (i <= 8) and i or nil,
        targetedBy = i % 3,
        combat = (i % 2 == 0),
        phased = (i == 4),
        summon = (i == 7),
        otherParty = (i == 10),
        name = NAMES[(i - 1) % #NAMES + 1],
        class = CLASSES[(i - 1) % #CLASSES + 1],
        hpMax = 100,
        hp = (i % 11 == 0) and 0 or ((i * 37) % 83) + 18,
        ppMax = 100,
        pp = (i * 53) % 101,
        ppType = mockPower(CLASSES[(i - 1) % #CLASSES + 1], ({ "TANK", "HEALER", "DAMAGER" })[(i - 1) % 3 + 1]),
        dead = (i % 11 == 0),
        aggro = (i == 1),
        role = ({ "TANK", "HEALER", "DAMAGER" })[(i - 1) % 3 + 1],
        isLeader = (i == 1),
        incHeal = (i % 4 == 0) and 30 or 0,
        absorb = (i % 5 == 0) and 35 or 0,
        healAbsorb = (i % 7 == 0) and 22 or 0,
        isTarget = (i == 2),
        readyCheck = ({ "ready", "notready", "waiting" })[(i - 1) % 3 + 1],
        statusRez = (i % 6 == 0),
        feignDeath = (i % 9 == 0),
        ghost = (i % 13 == 0),
        drinking = (i % 8 == 5),
        summonStatus = (i % 6 == 3) and "pending" or (i % 6 == 4) and "accepted" or (i % 6 == 5) and "declined" or nil,
    }
end

local function count(key)
    local cfg = N.db[key]
    if key == "party" then return cfg.showPlayer and 5 or 4 end
    if key == "ownPet" or key == "npc" then return 1 end
    if key == "groupPets" then return 4 end
    if key == "spotlight" then return 3 end
    return math.min(cfg.maxColumns, 4) * cfg.unitsPerColumn
end

local function place(container, key, pool, n)
    local cfg = N.db[key]
    local w, h, sp = cfg.width, cfg.height, cfg.spacing
    local colSp = cfg.columnSpacing or sp
    local horizontal = cfg.orientation == "horizontal"
    local rev = cfg.reverse
    local perCol = (key == "raid") and cfg.unitsPerColumn or n

    local anchor = "TOPLEFT"
    if rev then anchor = horizontal and "TOPRIGHT" or "BOTTOMLEFT" end
    local sx = anchor:find("RIGHT") and -1 or 1
    local sy = anchor:find("BOTTOM") and 1 or -1

    for i = 1, n do
        local b = pool[i]
        b:SetSize(w, h)
        local idx = i - 1
        local col = math.floor(idx / perCol)
        local pos = idx % perCol
        local x, y
        if horizontal then
            x, y = pos * (w + sp), col * (h + colSp)
        else
            x, y = col * (w + colSp), pos * (h + sp)
        end
        b:ClearAllPoints()
        b:SetPoint(anchor, container, anchor, sx * x, sy * y)
    end
end

-- Drag handle above a test container (same look as the real anchors). Shown while unlocked, moves
-- the saved position.
local function makeHandle(container, key)
    local M = N.Media
    container:SetMovable(true)
    container:SetClampedToScreen(true)
    local a = CreateFrame("Button", nil, container)
    a:SetPoint("BOTTOM", container, "TOP", 0, 2)
    a:SetSize(150, 20)
    a:SetFrameStrata("HIGH")
    a:EnableMouse(true)
    N.SkinPanel(a, { 0.10, 0.10, 0.10, 0.95 }, M.color.accent)
    local label = N.FontString(a, 11)
    label:SetPoint("CENTER")
    label:SetTextColor(M.color.accentBright[1], M.color.accentBright[2], M.color.accentBright[3])
    label:SetText(N.L[({ party = "Party Frames", raid = "Raid Frames", ownPet = "Own Pet Frame",
        groupPets = "Group Pet Frames", npc = "NPC Companion Frames", spotlight = "Spotlight Frame" })[key]])
    a:RegisterForDrag("LeftButton")
    a:SetScript("OnDragStart", function() container:StartMoving() end)
    a:SetScript("OnDragStop", function()
        container:StopMovingOrSizing()
        local x = N.Round(container:GetLeft())
        local y = N.Round(container:GetTop() - UIParent:GetHeight())
        N:Set(key .. ".x", x)
        N:Set(key .. ".y", y)
    end)
    container.handle = a
end

local function syncHandles()
    for _, c in pairs(containers) do
        if c.handle then c.handle:SetShown(active and not N.db.locked and not c.attachPreview) end
    end
end

local PET_NAMES = { ownPet = { "Fenrir" }, groupPets = { "Spirit Wolf", "Imp", "Ghoul", "Water Elemental" }, npc = { "Brann" } }

local function buildKey(key, force)
    if not force and not N.db[key].enabled and not N.PET_KEYS[key] and key ~= "spotlight" then return end

    local container = containers[key]
    if not container then
        container = CreateFrame("Frame", nil, UIParent)
        containers[key] = container
        pools[key] = {}
        makeHandle(container, key)
    end
    local cfg = N.db[key]
    container:ClearAllPoints()
    container:SetPoint(cfg.point, UIParent, cfg.point, cfg.x, cfg.y)
    container:SetSize(cfg.width, cfg.height)

    local pool = pools[key]
    local n = count(key)
    for i = 1, n do
        local b = pool[i]
        if not b then
            b = CreateFrame("Button", nil, container)
            b:RegisterForClicks("AnyUp")
            UF.CreateVisual(b, key)
            pool[i] = b
        end
        UF.LayoutBars(b)
        b:Show()
        local mock = mockFor(i)
        if N.PET_KEYS[key] then
            mock.name = PET_NAMES[key][(i - 1) % #PET_NAMES[key] + 1]
            mock.role, mock.isLeader, mock.readyCheck, mock.raidMarker = nil, false, nil, nil
        end
        UF.ApplyMock(b, mock)
        b:SetAlpha(mock.outOfRange and (cfg.appearance.outOfRangeAlpha or 0.45) or 1)
    end
    for i = n + 1, #pool do pool[i]:Hide() end

    place(container, key, pool, n)
    if key == "raid" and N.GroupLabels then N.GroupLabels.UpdateMock(pool, n) end
    container:Show()
    syncHandles()

    -- Re-render once anchors resolve so heal/absorb overlays get real widths.
    C_Timer.After(0, function()
        if not active then return end
        for i = 1, n do
            if pool[i]:IsShown() then UF.ApplyMock(pool[i], pool[i]._mock) end
        end
    end)
end

-- Only the group type being edited is previewed, so it follows the Group / Raid switch.
-- Pets bound to their owner sit next to the matching mock party frames (the Hunter is frame 3) so
-- the placement can be tuned.
local function attachPreview(key)
    local c = containers[key]
    local pool, owners = pools[key], pools.party
    if not (c and pool and owners) then return end
    local cfg = N.db[key]
    local which = (key == "ownPet") and { 1 } or { 3, 5 }
    for i = 1, #pool do pool[i]:Hide() end
    for i, oi in ipairs(which) do
        local b, ob = pool[i], owners[oi]
        if b and ob and ob:IsShown() then
            N.HeaderGroup.AttachTo(b, ob, cfg)
            b:SetAlpha(1)
            b:Show()
        end
    end
end

local function rebuild()
    if not active then return end
    local shown = N:Mode()
    for _, key in ipairs({ "party", "raid", "ownPet", "groupPets", "npc", "spotlight" }) do
        if key == shown then
            local attached = (key == "ownPet" or key == "groupPets") and N.db[key].attachEnabled
            if attached then
                buildKey("party", true)
                if containers.party then containers.party:Show() end
            end
            buildKey(key)
            if containers[key] then containers[key].attachPreview = attached and true or false end
            if attached then attachPreview(key) end
            syncHandles()
        elseif containers[key] then
            containers[key]:Hide()
        end
    end
end
TM.Rebuild = rebuild

local function setRealHeadersShown(shown)
    for _, header in pairs(N.headers or {}) do
        header:SetAlpha(shown and 1 or 0)
    end
end

function TM.Set(on)
    on = on and true or false
    if on == active then return end
    active = on
    if on then
        setRealHeadersShown(false)
        rebuild()
    else
        setRealHeadersShown(true)
        for _, c in pairs(containers) do c:Hide() end
    end
    N:Fire("NUCLEUS_TEST_MODE", active)
end

function TM.Toggle() TM.Set(not active) end
function TM.IsActive() return active end

function TM.Init()
    N:On("NUCLEUS_SETTING_CHANGED", function(_, section)
        if active and N.GROUP_KEYS[section] then
            rebuild()
        end
    end)
    N:On("NUCLEUS_SETTING_CHANGED", function(_, _, path)
        if path == "locked" then syncHandles() end
    end)
    N:On("NUCLEUS_EDIT_MODE", function()
        if active then rebuild() end
    end)
end
