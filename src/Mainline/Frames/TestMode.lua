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

local NAMES = {
    "Ashvane", "Brill", "Cindra", "Dorn", "Eyala", "Fenn", "Gwyn", "Harlow",
    "Isolde", "Joro", "Kessa", "Lyle", "Mira", "Nils", "Orin", "Perah",
    "Quill", "Roan", "Sable", "Tavin", "Ula", "Vex", "Wren", "Xander",
}
local CLASSES = {
    "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN",
    "MAGE", "WARLOCK", "MONK", "DRUID", "DEMONHUNTER", "EVOKER",
}

local CLASS_POWER = {
    WARRIOR = "RAGE", PALADIN = "MANA", HUNTER = "FOCUS", ROGUE = "ENERGY", PRIEST = "MANA",
    DEATHKNIGHT = "RUNIC_POWER", SHAMAN = "MANA", MAGE = "MANA", WARLOCK = "MANA",
    DEMONHUNTER = "FURY", EVOKER = "MANA",
}
local function mockPower(class, role)
    if class == "DRUID" then return role == "TANK" and "RAGE" or role == "HEALER" and "MANA" or "ENERGY" end
    if class == "MONK" then return role == "HEALER" and "MANA" or "ENERGY" end
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

local ROLE_CYCLE = { "TANK", "HEALER", "DAMAGER" }
local PARTY_ROLES = { "TANK", "HEALER", "DAMAGER", "DAMAGER", "DAMAGER" }
local function roleOf(i, key)
    if key == "party" then return PARTY_ROLES[(i - 1) % #PARTY_ROLES + 1] end
    return ROLE_CYCLE[(i - 1) % 3 + 1]
end

local function mockFor(i, key)
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
        ppType = mockPower(CLASSES[(i - 1) % #CLASSES + 1], roleOf(i, key)),
        dead = (i % 11 == 0),
        aggro = (i == 1),
        role = roleOf(i, key),
        isLeader = (i == 1),
        raidRole = (i == 2 and "MAINTANK") or (i == 3 and "MAINASSIST") or nil,
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
    if key == "raid" then
        local groups = 0
        for g = 1, 8 do
            if not N.RaidGroupAllowed or N.RaidGroupAllowed(g) then groups = groups + 1 end
        end
        return math.max(1, groups) * 5
    end
    return math.min(cfg.maxColumns, 8) * cfg.unitsPerColumn
end

local function blockLayout(key, n)
    local cfg = N.db[key]
    local w, h, sp = cfg.width, cfg.height, cfg.spacing
    local colSp = cfg.columnSpacing or sp
    local horizontal = cfg.orientation == "horizontal"
    if key == "raid" and N.RaidGrid and N.RaidGrid.Active() then
        local l = N.RaidGrid.Layout()
        return 5, horizontal, l.w, l.h, colSp
    end
    local perCol = (key == "raid") and (cfg.groupBy == "GROUP" and 5 or cfg.unitsPerColumn) or n
    perCol = math.max(1, perCol)
    local cols = math.max(1, math.ceil(n / perCol))
    local rows = math.max(1, math.min(n, perCol))
    local totalW, totalH
    if horizontal then
        totalW, totalH = rows * w + (rows - 1) * sp, cols * h + (cols - 1) * colSp
    else
        totalW, totalH = cols * w + (cols - 1) * colSp, rows * h + (rows - 1) * sp
    end
    return perCol, horizontal, totalW, totalH, colSp
end

function TM.BlockSize(key)
    if not (N.db and N.db[key]) then return 0, 0 end
    local _, _, w, h = blockLayout(key, count(key))
    return w, h
end

local function place(container, key, pool, n)
    local cfg = N.db[key]
    local w, h, sp = cfg.width, cfg.height, cfg.spacing
    local perCol, horizontal, totalW, totalH, colSp = blockLayout(key, n)
    local rev = cfg.reverse

    local anchor = "TOPLEFT"
    if rev then anchor = horizontal and "TOPRIGHT" or "BOTTOMLEFT" end
    local sx = anchor:find("RIGHT") and -1 or 1
    local sy = anchor:find("BOTTOM") and 1 or -1

    container:SetSize(totalW, totalH)

    local grid = key == "raid" and N.RaidGrid and N.RaidGrid.Active() and N.RaidGrid.Layout() or nil
    for i = 1, n do
        local b = pool[i]
        b:SetSize(w, h)
        local idx = i - 1
        b:ClearAllPoints()
        if grid then
            local slot = grid.slots[math.floor(idx / 5) + 1]
            local pos = idx % 5
            local ux, uy = 0, 0
            if slot then
                if horizontal then
                    ux = slot.x + (rev and (grid.gw - w - pos * (w + sp)) or pos * (w + sp))
                    uy = slot.y
                else
                    ux = slot.x
                    uy = slot.y - (rev and (grid.gh - h - pos * (h + sp)) or pos * (h + sp))
                end
            end
            b:SetPoint("TOPLEFT", container, "TOPLEFT", ux, uy)
        else
            local col = math.floor(idx / perCol)
            local pos = idx % perCol
            local x, y
            if horizontal then
                x, y = pos * (w + sp), col * (h + colSp)
            else
                x, y = col * (w + colSp), pos * (h + sp)
            end
            b:SetPoint(anchor, container, anchor, sx * x, sy * y)
        end
    end
end

local function makeHandle(container, key)
    local M = N.Media
    container:SetMovable(true)
    container:SetClampedToScreen(true)
    local a = CreateFrame("Button", nil, container)
    a:SetFrameStrata("HIGH")
    a:EnableMouse(true)
    N.SkinPanel(a, { 0.10, 0.10, 0.10, 0.95 }, M.color.accent)
    local label = N.FontString(a, 10)
    label:SetPoint("CENTER")
    label:SetTextColor(M.color.accentBright[1], M.color.accentBright[2], M.color.accentBright[3])
    local title = N.L[({ party = "Party Frames", raid = "Raid Frames", ownPet = "Own Pet Frame",
        groupPets = "Group Pet Frames", npc = "NPC Companion Frames", spotlight = "Spotlight Frame" })[key]]
    N.StyleMover(a, label, title, container)
    a._restyle = function() N.StyleMover(a, label, title, container) end
    a:RegisterForDrag("LeftButton")
    a:SetScript("OnDragStart", function()
        if N.MoverMayDrag() then container:StartMoving(); a._moving = true end
    end)
    a:SetScript("OnDragStop", function()
        if not a._moving then return end
        a._moving = nil
        container:StopMovingOrSizing()
        local point = N.db[key].point
        local mx, my = N.PointXY(container, point)
        local ux, uy = N.PointXY(UIParent, point)
        N:Set(key .. ".x", N.Round(mx - ux))
        N:Set(key .. ".y", N.Round(my - uy))
        N:Fire("NUCLEUS_FRAME_MOVED", key)
    end)
    container.handle = a
end

local function syncHandles()
    for key, c in pairs(containers) do
        if c.handle then
            c.handle:SetShown(active and not N.db.locked and not c.attachPreview and N.MoverWanted(key))
            if c.handle._restyle then c.handle._restyle() end
        end
    end
end

-- Mock players in the order the real header would use (custom sorting with pins, else Group by / Sort);
-- slot i shows order[i].
local ROLE_RANK = { TANK = 1, HEALER = 2, DAMAGER = 3 }
local function testOrder(key, n)
    local order = {}
    for i = 1, n do order[i] = i end
    local cfg = N.db[key]
    if not cfg then return order end
    local isRaid = key == "raid"
    local o = cfg.ordering
    local custom = o and o.enabled
    local rank = ROLE_RANK
    local pins = {}
    if custom then
        rank = { [o.first or "TANK"] = 1, [o.second or "HEALER"] = 2, [o.third or "DAMAGER"] = 3 }
        for tok in (o.pinned or ""):gmatch("[^,;\n]+") do
            tok = strtrim(tok):lower()
            if tok ~= "" then pins[#pins + 1] = tok end
        end
    end
    local function nameOf(i) return NAMES[(i - 1) % #NAMES + 1]:lower() end
    local function classOf(i) return CLASSES[(i - 1) % #CLASSES + 1] end
    local function pinIndex(i)
        local name = nameOf(i)
        for k, pin in ipairs(pins) do
            if pin == name then return k end
        end
        return 1000
    end
    local groupBy = isRaid and cfg.groupBy or nil
    local byName = isRaid and cfg.sortMethod == "NAME" and #pins == 0
    -- Custom sorting with Group by = Group orders inside each raid group (5 mock players per group).
    local inGroups = custom and groupBy == "GROUP"
    local function groupOf(i) return math.floor((i - 1) / 5) end
    local function primary(i)
        if custom then return rank[roleOf(i, key)] or 4 end
        if groupBy == "GROUP" then return groupOf(i) end
        if groupBy == "CLASS" then return classOf(i) end
        if groupBy == "ROLE" then return ROLE_RANK[roleOf(i, key)] or 4 end
        return 0
    end
    table.sort(order, function(a, b)
        if inGroups and groupOf(a) ~= groupOf(b) then return groupOf(a) < groupOf(b) end
        if #pins > 0 then
            local pa, pb = pinIndex(a), pinIndex(b)
            if pa ~= pb then return pa < pb end
        end
        local ra, rb = primary(a), primary(b)
        if ra ~= rb then return ra < rb end
        if byName then
            local na, nb = nameOf(a), nameOf(b)
            if na ~= nb then return na < nb end
        end
        return a < b
    end)
    return order
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
    local order = (key == "party" or key == "raid") and testOrder(key, n) or nil
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
        local mock = mockFor(order and order[i] or i, key)
        if N.PET_KEYS[key] then
            mock.name = PET_NAMES[key][(i - 1) % #PET_NAMES[key] + 1]
            mock.role, mock.isLeader, mock.readyCheck, mock.raidMarker, mock.raidRole = nil, false, nil, nil, nil
        end
        UF.ApplyMock(b, mock)
        b:SetAlpha(mock.outOfRange and (cfg.appearance.outOfRangeAlpha or 0.45) or 1)
    end
    for i = n + 1, #pool do pool[i]:Hide() end

    place(container, key, pool, n)
    if key == "raid" and N.GroupLabels then N.GroupLabels.UpdateMock(pool, n) end
    container:Show()
    syncHandles()

    C_Timer.After(0, function()
        if not active then return end
        for i = 1, n do
            if pool[i]:IsShown() then UF.ApplyMock(pool[i], pool[i]._mock) end
        end
    end)
    return true
end

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

local NPC_SIDES = {
    RIGHT = { "TOPLEFT", "TOPRIGHT" }, LEFT = { "TOPRIGHT", "TOPLEFT" },
    TOP = { "BOTTOMLEFT", "TOPLEFT" }, BOTTOM = { "TOPLEFT", "BOTTOMLEFT" },
}
local SECTION_KEYS = { "party", "raid", "ownPet", "groupPets", "npc", "spotlight" }
local function rebuild()
    if not active then return end
    local edited = N:Mode()
    local extra = N.db.testSections or {}
    for _, key in ipairs(SECTION_KEYS) do
        if key == edited or extra[key] == true then
            local attached = (key == "ownPet" or key == "groupPets") and N.db[key].attachEnabled
            if attached then
                buildKey("party", true)
                if containers.party then containers.party:Show() end
            end
            local kc = N.db[key]
            local hostKey = (key == "npc" and kc.attachEnabled) and (edited == "raid" and "raid" or "party") or nil
            local hosted = (key == "ownPet" or key == "groupPets" or key == "spotlight")
                and not (key ~= "spotlight" and kc.attachEnabled)
            if hosted then
                -- the raid frames when the raid is being tested, else the group frames; the other one
                -- when only that one is switched on
                local ctx = (edited == "raid" or extra.raid == true) and "raid" or "party"
                local on = { party = kc.hostEnabled, raid = kc.raidHostEnabled }
                if not on[ctx] then ctx = (ctx == "raid") and "party" or "raid" end
                if on[ctx] then hostKey, hosted = ctx, ctx else hosted = nil end
            end
            if hostKey then
                buildKey(hostKey, true)
                if containers[hostKey] then containers[hostKey]:Show() end
            end
            local built = buildKey(key)
            if containers[key] then
                containers[key].attachPreview = (attached or hostKey) and true or false
                if not built then containers[key]:Hide() end
            end
            if attached and built then attachPreview(key) end
            if hostKey and built and containers[hostKey] then
                local cfg = N.db[key]
                local side, gap, shift = cfg.attachSide, cfg.attachGap or 2, cfg.attachShift or 0
                if hosted == "raid" then
                    side, gap, shift = cfg.raidHostSide, cfg.raidHostGap or 4, cfg.raidHostShift or 0
                elseif hosted then
                    side, gap, shift = cfg.hostSide, cfg.hostGap or 4, cfg.hostShift or 0
                end
                local s = NPC_SIDES[side] or NPC_SIDES.RIGHT
                local x, y = gap, shift
                if side == "LEFT" then x, y = -gap, shift
                elseif side == "TOP" then x, y = shift, gap
                elseif side == "BOTTOM" then x, y = shift, -gap end
                containers[key]:ClearAllPoints()
                containers[key]:SetPoint(s[1], containers[hostKey], s[2], x, y)
            end
        elseif containers[key] then
            containers[key]:Hide()
        end
    end
    syncHandles()
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
        if active and (N.GROUP_KEYS[section] or section == "testSections") then
            rebuild()
        end
    end)
    N:On("NUCLEUS_SETTING_CHANGED", function(_, _, path)
        if path == "locked" or path == "moverMode" or path == "moverSize" or path == "moverStyle"
            or path == "moverBarWidth" or path == "moverX" or path == "moverY" then
            syncHandles()
        end
    end)
    N:On("NUCLEUS_EDIT_MODE", function()
        if active then rebuild() end
    end)
end
