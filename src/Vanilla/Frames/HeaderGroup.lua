local _, ns = ...
local N = ns.N

-- Blizzard's template owns children, visibility and units; we feed it attributes out of combat.

local HG = {}
N.HeaderGroup = HG

-- The header's position lives on a plain frame (the header is protected in combat, the frame is not).
local posFrames = {}
function N.HeaderPosFrame(key) return posFrames[key] end

-- Own pet, group pets and Spotlight can hang on the party / raid frames ("Attach to group frames").
local HOSTED = { ownPet = true, groupPets = true, spotlight = true }
local HOST_SIDES = {
    RIGHT = { "TOPLEFT", "TOPRIGHT" }, LEFT = { "TOPRIGHT", "TOPLEFT" },
    TOP = { "BOTTOMLEFT", "TOPLEFT" }, BOTTOM = { "TOPLEFT", "BOTTOMLEFT" },
}

-- enabled, side, gap, shift of the set in use: raid frames in a raid, else group frames.
local function hostSettings(cfg)
    if IsInRaid() then return cfg.raidHostEnabled, cfg.raidHostSide, cfg.raidHostGap, cfg.raidHostShift end
    return cfg.hostEnabled, cfg.hostSide, cfg.hostGap, cfg.hostShift
end

local function hostFor(key, cfg)
    if not (HOSTED[key] and cfg and hostSettings(cfg)) then return nil end
    if key ~= "spotlight" and cfg.attachEnabled then return nil end -- hanging on the owner wins
    if IsInRaid() then return N.headers.raid end
    return N.headers.party
end

local function hostPoints(cfg)
    local _, hostSide, hostGap, hostShift = hostSettings(cfg)
    local side = HOST_SIDES[hostSide] and hostSide or "RIGHT"
    local gap, shift = hostGap or 4, hostShift or 0
    local x, y = gap, shift
    if side == "LEFT" then x, y = -gap, shift
    elseif side == "TOP" then x, y = shift, gap
    elseif side == "BOTTOM" then x, y = shift, -gap end
    return HOST_SIDES[side][1], HOST_SIDES[side][2], x, y
end

function N.IsHosted(key)
    return hostFor(key, N.db and N.db[key]) ~= nil
end
local function placeHeader(header, key, cfg, group)
    local pf = posFrames[key]
    if not pf then
        pf = CreateFrame("Frame", nil, UIParent)
        pf:SetSize(1, 1)
        pf:SetMovable(true)
        posFrames[key] = pf
    end
    pf:ClearAllPoints()
    header:ClearAllPoints()
    local host = hostFor(key, cfg)
    if host then
        local selfPt, hostPt, x, y = hostPoints(cfg)
        pf:SetPoint(selfPt, host, hostPt, x, y)
        header:SetPoint(selfPt, pf, selfPt, 0, 0)
        return
    end
    pf:SetPoint(cfg.point, UIParent, cfg.point, cfg.x, cfg.y)
    local corner, ox, oy = cfg.point, 0, 0
    local grid = N.RaidGrid
    if key == "raid" and grid and grid.Active() then corner, ox, oy = grid.Anchor(group or 1) end
    header:SetPoint(corner, pf, cfg.point, ox, oy)
end

-- Blizzard's group headers are secure frames: nothing of ours is stored in their Lua tables.
local headerInfo = setmetatable({}, { __mode = "k" })
function N.HeaderKey(frame)
    local i = headerInfo[frame]
    return i and i.key or frame.groupKey
end
function N.HeaderHolder(frame)
    local i = headerInfo[frame]
    return i and i.holder
end
N.headers = {}

local INITIAL_CONFIG = [[
    self:SetWidth(%d)
    self:SetHeight(%d)
    self:SetAttribute("*type1", "target")
    self:SetAttribute("*type2", "togglemenu")
    self:SetAttribute("toggleForVehicle", true)
]]

local function forChildren(header, fn)
    local i = 1
    local child = _G[header:GetName() .. "UnitButton" .. i]
    while child do
        fn(child, i)
        i = i + 1
        child = _G[header:GetName() .. "UnitButton" .. i]
    end
end

local function applyChildSize(header)
    local w, h = N.db[N.HeaderKey(header)].width, N.db[N.HeaderKey(header)].height
    forChildren(header, function(child) child:SetSize(w, h) end)
end

-- Styles and binds every child (also on roster / zone events); one bad child can't abort header setup.
local function styleChildren(header)
    forChildren(header, function(child)
        local ok, err = pcall(function()
            N.StyleUnitButton(child:GetName())
            N.UnitFrame.BindChild(child)
        end)
        if not ok then N:Print("|cffff5555style error:|r " .. tostring(err)) end
    end)
end
HG.StyleChildren = styleChildren

local CLASS_ORDER = table.concat(N.Classic.CLASSES, ",")

-- Orientation / reverse -> header anchors (vertical: groups form columns; horizontal: rows).
local function applyFlow(header, cfg)
    if cfg.orientation == "horizontal" then
        header:SetAttribute("point", cfg.reverse and "RIGHT" or "LEFT")
        header:SetAttribute("xOffset", cfg.reverse and -cfg.spacing or cfg.spacing)
        header:SetAttribute("yOffset", 0)
        header:SetAttribute("columnAnchorPoint", "TOP")
    else
        header:SetAttribute("point", cfg.reverse and "BOTTOM" or "TOP")
        header:SetAttribute("xOffset", 0)
        header:SetAttribute("yOffset", cfg.reverse and cfg.spacing or -cfg.spacing)
        header:SetAttribute("columnAnchorPoint", "LEFT")
    end
    header:SetAttribute("columnSpacing", cfg.columnSpacing or cfg.spacing)
end


local NPC_SLOTS = 4

-- A party member that is an NPC companion (Brann in Delves, follower dungeons).
local function isNpcUnit(unit)
    return UnitExists(unit) and UnitInPartyIsAI and UnitInPartyIsAI(unit) and true or false
end

-- NPC companions leave the group frames for the NPC frames only with "Move companions here".
local function companionsMoved()
    return (N.db.npc and N.db.npc.enabled and N.db.npc.moveCompanions) and true or false
end

-- The party header's name list without NPC companions; nil when nothing needs filtering.
local function partyNameFilter()
    if not companionsMoved() or IsInRaid() then return nil end
    local any, names = false, {}
    if N.db.party.showPlayer then names[#names + 1] = GetUnitName("player", true) end
    for i = 1, 4 do
        local u = "party" .. i
        if UnitExists(u) then
            if isNpcUnit(u) then any = true
            else names[#names + 1] = GetUnitName(u, true) end
        end
    end
    if not any then return nil end
    return table.concat(names, ",")
end

-- Spotlight: the units its entries stand for right now (out of combat; reads the roster and roles).
local function spotlightUnits()
    local cfg = N.db.spotlight
    local out, used = {}, {}
    local function add(u)
        if u and not used[u] and #out < N.SPOTLIGHT_MAX then
            used[u] = true
            out[#out + 1] = u
        end
    end
    local roster = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do roster[#roster + 1] = "raid" .. i end
    else
        roster[1] = "player"
        for i = 1, 4 do roster[#roster + 1] = "party" .. i end
    end
    for _, e in ipairs(cfg and cfg.units or {}) do
        local t = e.type
        if t == "target" or t == "targettarget" or t == "focus" then
            add(t)
        elseif t == "role" then
            for _, u in ipairs(roster) do
                if UnitExists(u) then
                    local role = UnitGroupRolesAssigned(u)
                    if not N.IsSecret(role) and role == e.value then add(u) end
                end
            end
        elseif t == "name" and type(e.value) == "string" and e.value ~= "" then
            local want = e.value:lower()
            for _, u in ipairs(roster) do
                if UnitExists(u) then
                    local name, realm = UnitName(u)
                    if name and not N.IsSecret(name) then
                        local full = (realm and realm ~= "") and (name .. "-" .. realm) or name
                        if name:lower() == want or full:lower() == want then add(u) break end
                    end
                end
            end
        end
    end
    return out
end

local function placeInContainer(container, buttons, cfg, count)
    local w, h, sp = cfg.width, cfg.height, cfg.spacing
    local horizontal = cfg.orientation == "horizontal"
    for i = 1, #buttons do
        local b = buttons[i]
        b:SetSize(w, h)
        b:ClearAllPoints()
        local off = (i - 1) * ((horizontal and w or h) + sp)
        if horizontal then b:SetPoint("TOPLEFT", container, "TOPLEFT", off, 0)
        else b:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -off) end
    end
    local n = math.max(1, count)
    if horizontal then container:SetSize(n * w + (n - 1) * sp, h)
    else container:SetSize(w, n * h + (n - 1) * sp) end
end

-- The header can't put chosen people first: order the roster here and pass a name list.

-- Role ranks (1 = first) and pinned names; nil when the custom order is off.
local function sortConfig(key)
    local o = N.db[key] and N.db[key].ordering
    if not (o and o.enabled) then return nil end
    local rank = { [o.first or "TANK"] = 1, [o.second or "HEALER"] = 2, [o.third or "DAMAGER"] = 3 }
    local pins = {}
    for tok in (o.pinned or ""):gmatch("[^,;\n]+") do
        tok = strtrim(tok):lower()
        if tok ~= "" then pins[#pins + 1] = tok end
    end
    return rank, pins
end
local function raidGroupAllowed(group)
    local raid = N.db.raid
    if raid and type(raid.maxGroups) == "number" and group > raid.maxGroups then return false end
    local gf = raid and raid.groupFilter
    return not (type(gf) == "table" and gf[group] == false)
end
N.RaidGroupAllowed = raidGroupAllowed

-- Raid grid: one header per group on fixed slots, so nothing moves when the roster changes.
local RG = {}
N.RaidGrid = RG

local FLOWS = {
    RIGHT_DOWN = { 1, 0, 0, -1 }, LEFT_DOWN = { -1, 0, 0, -1 },
    RIGHT_UP = { 1, 0, 0, 1 }, LEFT_UP = { -1, 0, 0, 1 },
    DOWN_RIGHT = { 0, -1, 1, 0 }, DOWN_LEFT = { 0, -1, -1, 0 },
    UP_RIGHT = { 0, 1, 1, 0 }, UP_LEFT = { 0, 1, -1, 0 },
}
RG.FLOW_ORDER = { "RIGHT_DOWN", "LEFT_DOWN", "RIGHT_UP", "LEFT_UP", "DOWN_RIGHT", "DOWN_LEFT", "UP_RIGHT", "UP_LEFT" }

-- Only with Group by = Group and without pinned names (those need one name list over every group).
function RG.Active()
    local cfg = N.db and N.db.raid
    if not cfg or cfg.groupBy ~= "GROUP" then return false end
    if (tonumber(cfg.groupsPerRow) or 0) < 1 then return false end
    local rank, pins = sortConfig("raid")
    return not (rank and #pins > 0)
end

-- { list = allowed groups, index = group -> slot, slots[k] = {x, y} (down is negative), w, h, gw, gh }.
function RG.Layout()
    local cfg = N.db.raid
    local w, h, sp = cfg.width, cfg.height, cfg.spacing
    local list, index = {}, {}
    for g = 1, 8 do
        if raidGroupAllowed(g) then
            list[#list + 1] = g
            index[g] = #list
        end
    end
    local n = #list
    local per = math.min(8, math.max(1, math.floor(tonumber(cfg.groupsPerRow) or 1)))
    local flow = FLOWS[cfg.groupFlow] or FLOWS.RIGHT_DOWN
    local px, py, sx, sy = flow[1], flow[2], flow[3], flow[4]
    local unitsAcross = cfg.orientation == "horizontal"
    local gw = unitsAcross and (5 * w + 4 * sp) or w
    local gh = unitsAcross and h or (5 * h + 4 * sp)
    local gapP = cfg.columnSpacing or sp
    local gapS = cfg.rowSpacing or gapP
    local alongX = px ~= 0
    local nP, nS = math.min(per, math.max(n, 1)), math.max(1, math.ceil(n / per))
    local cols, rows = alongX and nP or nS, alongX and nS or nP
    local gapX, gapY = alongX and gapP or gapS, alongX and gapS or gapP
    local slots = {}
    for k = 0, n - 1 do
        local a, b = k % per, math.floor(k / per)
        local xi, yi
        if alongX then
            xi = px > 0 and a or (cols - 1 - a)
            yi = sy < 0 and b or (rows - 1 - b)
        else
            yi = py < 0 and a or (rows - 1 - a)
            xi = sx > 0 and b or (cols - 1 - b)
        end
        slots[k + 1] = { x = xi * (gw + gapX), y = -yi * (gh + gapY) }
    end
    return {
        list = list, index = index, slots = slots, gw = gw, gh = gh,
        w = n > 0 and (cols * gw + (cols - 1) * gapX) or 0,
        h = n > 0 and (rows * gh + (rows - 1) * gapY) or 0,
    }
end

function RG.Size()
    local l = RG.Layout()
    return l.w, l.h
end

-- Header corner on the slot corner; it follows the unit growth, so a part-full group keeps its place.
function RG.Anchor(group)
    local cfg = N.db.raid
    local l = RG.Layout()
    local k = l.index[group]
    local point = cfg.point or "TOPLEFT"
    if not k then return point, 0, 0 end
    local s = l.slots[k]
    local horizontal = cfg.orientation == "horizontal"
    local right = horizontal and cfg.reverse
    local bottom = (not horizontal) and cfg.reverse
    local corner = (bottom and "BOTTOM" or "TOP") .. (right and "RIGHT" or "LEFT")
    local cx = s.x + (right and l.gw or 0)
    local cy = s.y - (bottom and l.gh or 0)
    local fx = point:find("LEFT") and 0 or point:find("RIGHT") and 1 or 0.5
    local fy = point:find("TOP") and 0 or point:find("BOTTOM") and 1 or 0.5
    return corner, cx - fx * l.w, cy + fy * l.h
end

-- Role order without pins needs no name list: the header sorts by assigned role.
local function nativeRoleOrder(key)
    local rank, pins = sortConfig(key)
    if not rank or #pins > 0 then return nil end
    local o = N.db[key].ordering
    return ("%s,%s,%s,NONE"):format(o.first or "TANK", o.second or "HEALER", o.third or "DAMAGER")
end

local function customNameList(key)
    local rank, pins = sortConfig(key)
    if not rank or #pins == 0 then return nil end

    local units = {}
    if key == "party" then
        if IsInRaid() then return nil end
        if N.db.party.showPlayer then units[#units + 1] = "player" end
        for i = 1, 4 do units[#units + 1] = "party" .. i end
    elseif IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    else
        units[#units + 1] = "player"
        for i = 1, 4 do units[#units + 1] = "party" .. i end
    end

    local npcOut = key == "party" and companionsMoved()
    local list = {}
    local inRaid = key == "raid" and IsInRaid()
    for i, u in ipairs(units) do
        local group = inRaid and select(3, GetRaidRosterInfo(i)) or nil
        if UnitExists(u) and not (npcOut and isNpcUnit(u)) and (not group or raidGroupAllowed(group)) then
            local full = GetUnitName(u, true)
            -- A name the client doesn't know yet would sort wrong: keep native order until UNIT_NAME_UPDATE.
            if full == _G.UNKNOWNOBJECT or full == _G.UNKNOWN then return nil end
            if full and full ~= "" then
                local role = UnitGroupRolesAssigned(u)
                list[#list + 1] = {
                    name = full, short = (full:gsub("%-.*$", "")):lower(), full = full:lower(),
                    rank = rank[role] or 4, idx = i, pin = nil,
                }
            end
        end
    end
    if #list == 0 then return nil end

    for _, e in ipairs(list) do
        for pi, p in ipairs(pins) do
            if p == e.short or p == e.full then e.pin = pi break end
        end
    end
    table.sort(list, function(a, b)
        if a.pin or b.pin then
            if a.pin and b.pin then return a.pin < b.pin end
            return a.pin ~= nil
        end
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.idx < b.idx
    end)
    local names = {}
    for _, e in ipairs(list) do names[#names + 1] = e.name end
    return table.concat(names, ",")
end


local SIDES = {
    RIGHT = { "TOPLEFT", "TOPRIGHT" }, LEFT = { "TOPRIGHT", "TOPLEFT" },
    TOP = { "BOTTOMLEFT", "TOPLEFT" }, BOTTOM = { "TOPLEFT", "BOTTOMLEFT" },
}

local OWNER_HEADERS = { "party", "raid", "raidG2", "raidG3", "raidG4", "raidG5", "raidG6", "raidG7", "raidG8" }

-- The raid header and, with "Groups per row", the headers of groups 2-8.
function N.RaidHeaders()
    local out = {}
    for _, key in ipairs(OWNER_HEADERS) do
        if key ~= "party" and N.headers[key] then out[#out + 1] = N.headers[key] end
    end
    return out
end

local function findOwnerButton(ownerUnit)
    for pass = 1, 2 do
        for _, key in ipairs(OWNER_HEADERS) do
            local h = N.headers[key]
            if h and h:IsShown() then
                local i, child = 1, _G[h:GetName() .. "UnitButton1"]
                while child do
                    if child:IsShown() then
                        local u = child:GetAttribute("unit")
                        if u == ownerUnit then return child end
                        if pass == 2 and ownerUnit == "player" and u then
                            local same = UnitIsUnit(u, "player")
                            if not N.IsSecret(same) and same then return child end
                        end
                    end
                    i = i + 1
                    child = _G[h:GetName() .. "UnitButton" .. i]
                end
            end
        end
    end
end

local function attachTo(btn, owner, cfg)
    local s = SIDES[cfg.attachSide] or SIDES.RIGHT
    local gap, shift = cfg.attachGap or 2, cfg.attachShift or 0
    local x, y = 0, 0
    if cfg.attachSide == "LEFT" then x, y = -gap, shift
    elseif cfg.attachSide == "TOP" then x, y = shift, gap
    elseif cfg.attachSide == "BOTTOM" then x, y = shift, -gap
    else x, y = gap, shift end
    btn:SetSize(cfg.width, cfg.height)
    btn:ClearAllPoints()
    btn:SetPoint(s[1], owner, s[2], x, y)
end

HG.AttachTo = attachTo

-- Pets of group members: one secure button per possible pet, each shows itself while its pet exists.
local ATTACH_PARTY, ATTACH_RAID = 4, 40

local function createAttachedPets()
    if N.headers.groupPetsAttached then return N.headers.groupPetsAttached end
    local name = "NucleusHeaderGroupPetsAttach"
    local c = CreateFrame("Frame", name, UIParent)
    c.groupKey = "groupPets"
    c.buttons = {}
    for i = 1, ATTACH_PARTY + ATTACH_RAID do
        local b = CreateFrame("Button", name .. "UnitButton" .. i, c, "SecureUnitButtonTemplate")
        b:SetAttribute("*type1", "target")
        b:SetAttribute("*type2", "togglemenu")
        local unit, vis
        if i <= ATTACH_PARTY then
            unit = "partypet" .. i
            b._owner = "party" .. i
            vis = "[group:raid] hide; [@" .. unit .. ",exists] show; hide"
        else
            unit = "raidpet" .. (i - ATTACH_PARTY)
            b._owner = "raid" .. (i - ATTACH_PARTY)
            vis = "[group:raid,@" .. unit .. ",exists] show; hide"
        end
        b:SetAttribute("unit", unit)
        RegisterStateDriver(b, "visibility", vis)
        c.buttons[i] = b
    end
    N.headers.groupPetsAttached = c
    C_Timer.After(0, function() if N.ClickCasting then N.ClickCasting.ApplyToAll() end end)
    return c
end

local function layoutAttachedPets(c)
    local cfg = N.db.groupPets
    for _, b in ipairs(c.buttons) do
        local owner = findOwnerButton(b._owner)
        if owner then
            attachTo(b, owner, cfg)
            b:SetAlpha(1)
        else
            b:SetAlpha(0)
        end
    end
    styleChildren(c)
end

local function applyGroupPetsMode()
    local cfg = N.db.groupPets
    local header, att = N.headers.groupPets, N.headers.groupPetsAttached
    if not cfg.enabled or N.profileHidden then
        if header then header:Hide() end
        if att then att:Hide() end
        return
    end
    if cfg.attachEnabled then
        att = att or createAttachedPets()
        if header then header:Hide() end
        att:Show()
        layoutAttachedPets(att)
    else
        if att then att:Hide() end
        if header then header:Show() end
    end
end

local function configurePetContainer(container)
    local key = container.groupKey
    local cfg = N.db[key]
    local count, order = 1, container.buttons
    if key == "npc" then
        local units = {}
        for i = 1, 4 do
            if companionsMoved() and isNpcUnit("party" .. i) then units[#units + 1] = "party" .. i end
        end
        order = {}
        for i, b in ipairs(container.buttons) do
            if units[i] and cfg.enabled then
                if b:GetAttribute("unit") ~= units[i] then b:SetAttribute("unit", units[i]) end
                b:Show()
                order[#order + 1] = b
            else
                b:Hide()
            end
        end
        for _, b in ipairs(container.bossButtons) do order[#order + 1] = b end
        count = #order
    elseif key == "spotlight" then
        local units = cfg.enabled and spotlightUnits() or {}
        order = {}
        for i, b in ipairs(container.buttons) do
            local u = units[i]
            if u then
                if b:GetAttribute("unit") ~= u then b:SetAttribute("unit", u) end
                RegisterStateDriver(b, "visibility", "[@" .. u .. ",exists] show; hide")
                order[#order + 1] = b
            else
                UnregisterStateDriver(b, "visibility")
                b:Hide()
            end
        end
        count = #order
        container._spotlightSig = table.concat(units, ",")
    end
    placeInContainer(container, order, cfg, count)
    if key == "ownPet" and cfg.attachEnabled then
        local owner = findOwnerButton("player")
        if owner then attachTo(container.buttons[1], owner, cfg) end
    end
    container:ClearAllPoints()
    local host = key == "npc" and cfg.attachEnabled and ((IsInRaid() and N.headers.raid) or N.headers.party or N.headers.raid)
    local hosted = not host and hostFor(key, cfg)
    if host then
        local s = SIDES[cfg.attachSide] or SIDES.RIGHT
        local gap, shift = cfg.attachGap or 2, cfg.attachShift or 0
        local x, y = gap, shift
        if cfg.attachSide == "LEFT" then x, y = -gap, shift
        elseif cfg.attachSide == "TOP" then x, y = shift, gap
        elseif cfg.attachSide == "BOTTOM" then x, y = shift, -gap end
        container:SetPoint(s[1], host, s[2], x, y)
    elseif hosted then
        local selfPt, hostPt, x, y = hostPoints(cfg)
        container:SetPoint(selfPt, hosted, hostPt, x, y)
    else
        container:SetPoint(cfg.point, UIParent, cfg.point, cfg.x, cfg.y)
    end
    styleChildren(container)
end

-- Headers of raid groups 2-8 (1 is the raid header), made once out of combat.
local builtGroup = setmetatable({}, { __mode = "k" })
local function createGroupHeaders()
    local main = N.headers.raid
    local info = main and headerInfo[main]
    if not info or InCombatLockdown() then return end
    for g = 2, 8 do
        local key = "raidG" .. g
        if not N.headers[key] then
            local header = CreateFrame("Frame", "NucleusHeaderRaidG" .. g, info.holder or UIParent, "SecureGroupHeaderTemplate")
            headerInfo[header] = { key = "raid", holder = info.holder, group = g }
            header:SetMovable(true)
            header:SetClampedToScreen(true)
            N.headers[key] = header
        end
    end
    C_Timer.After(0, function() if N.ClickCasting then N.ClickCasting.ApplyToAll() end end)
end
local syncGroupHeaders

-- Pushes all attributes onto the header, out of combat.
local function configureInner(header)
    local key = N.HeaderKey(header)
    local cfg = N.db[key]
    local group = headerInfo[header] and headerInfo[header].group
    local grid = key == "raid" and RG.Active()
    if key == "ownPet" or key == "npc" or key == "spotlight" then
        configurePetContainer(header)
        return
    end

    header:SetAttribute("template", "SecureUnitButtonTemplate")
    header:SetAttribute("templateType", "Button")
    header:SetAttribute("initialConfigFunction",
        INITIAL_CONFIG:format(cfg.width, cfg.height))

    header:SetAttribute("showSolo", cfg.showSolo)
    header:SetAttribute("sortDir", "ASC")
    applyFlow(header, cfg)

    if key == "party" then
        header:SetAttribute("showPlayer", cfg.showPlayer)
        header:SetAttribute("showParty", true)
        header:SetAttribute("showRaid", false)
        header:SetAttribute("maxColumns", 1)
        header:SetAttribute("unitsPerColumn", 5)
        header:SetAttribute("groupBy", nil)
        header:SetAttribute("groupingOrder", nil)
        header:SetAttribute("nameList", nil)
        local roleOrder = nativeRoleOrder("party")
        if roleOrder then
            header:SetAttribute("groupingOrder", roleOrder)
            header:SetAttribute("groupBy", "ASSIGNEDROLE")
        end
        header:SetAttribute("sortMethod", "INDEX")
        local names = customNameList("party") or partyNameFilter()
        if names then
            header:SetAttribute("sortMethod", "NAMELIST")
            header:SetAttribute("nameList", names)
        end
    elseif key == "groupPets" then
        header:SetAttribute("showPlayer", false)
        header:SetAttribute("showParty", true)
        header:SetAttribute("showRaid", true)
        header:SetAttribute("unitsPerColumn", cfg.unitsPerColumn)
        header:SetAttribute("maxColumns", cfg.maxColumns)
        header:SetAttribute("groupBy", nil)
        header:SetAttribute("groupingOrder", nil)
        header:SetAttribute("sortMethod", "INDEX")
    else
        header:SetAttribute("showPlayer", true)
        header:SetAttribute("showParty", true)
        header:SetAttribute("showRaid", true)
        header:SetAttribute("unitsPerColumn", cfg.unitsPerColumn)
        header:SetAttribute("maxColumns", cfg.maxColumns)
        header:SetAttribute("sortMethod", cfg.sortMethod)

        -- groupingOrder before groupBy (groupBy alone triggers an update that errors); drop a stale nameList first.
        header:SetAttribute("nameList", nil)
        if cfg.groupBy == "GROUP" then
            header:SetAttribute("groupingOrder", "1,2,3,4,5,6,7,8")
            header:SetAttribute("groupBy", "GROUP")
            header:SetAttribute("unitsPerColumn", 5)
        elseif cfg.groupBy == "CLASS" then
            header:SetAttribute("groupingOrder", CLASS_ORDER)
            header:SetAttribute("groupBy", "CLASS")
        elseif cfg.groupBy == "ROLE" then
            header:SetAttribute("groupingOrder", "TANK,HEALER,DAMAGER,NONE")
            header:SetAttribute("groupBy", "ASSIGNEDROLE")
        else
            header:SetAttribute("groupBy", nil)
            header:SetAttribute("groupingOrder", nil)
        end

        local roleOrder = nativeRoleOrder("raid")
        if roleOrder then
            header:SetAttribute("groupingOrder", roleOrder)
            header:SetAttribute("groupBy", "ASSIGNEDROLE")
        end

        local wanted = {}
        for g = 1, 8 do
            if raidGroupAllowed(g) then wanted[#wanted + 1] = g end
        end
        header:SetAttribute("groupFilter", (#wanted == 8 or #wanted == 0) and nil or table.concat(wanted, ","))

        header:SetAttribute("nameList", nil)
        local names = customNameList("raid")
        if names then
            header:SetAttribute("groupBy", nil)
            header:SetAttribute("groupingOrder", nil)
            header:SetAttribute("sortMethod", "NAMELIST")
            header:SetAttribute("nameList", names)
        end
    end

    if key == "raid" then
        if group then
            header:SetAttribute("showPlayer", false)
            header:SetAttribute("showParty", false)
            header:SetAttribute("showSolo", false)
        end
        if grid then
            header:SetAttribute("nameList", nil)
            header:SetAttribute("unitsPerColumn", 5)
            header:SetAttribute("maxColumns", 1)
            header:SetAttribute("sortMethod", cfg.sortMethod)
            local g = group or 1
            header:SetAttribute("groupFilter", raidGroupAllowed(g) and tostring(g) or "0")
            local roleOrder = nativeRoleOrder("raid")
            if roleOrder then
                header:SetAttribute("groupingOrder", roleOrder)
                header:SetAttribute("groupBy", "ASSIGNEDROLE")
            else
                header:SetAttribute("groupBy", nil)
                header:SetAttribute("groupingOrder", nil)
            end
        elseif group then
            header:SetAttribute("showRaid", false)
            header:SetAttribute("groupFilter", "0")
        end
        if group and not InCombatLockdown() then header:SetShown(grid and true or false) end
    end

    N.Debug("configure", key, group and ("group " .. group) or "main", grid and "grid" or "single")
    placeHeader(header, key, cfg, group)

    if group and grid and not builtGroup[header] and not InCombatLockdown() then
        builtGroup[header] = true
        header:SetAttribute("startingIndex", -5)
        header:Show()
        header:SetAttribute("startingIndex", 1)
    end

    applyChildSize(header)
    styleChildren(header)
    C_Timer.After(0, function() styleChildren(header) end)
    if key == "groupPets" then applyGroupPetsMode() end
    if key == "raid" and not group then syncGroupHeaders() end
end

-- _ignore holds attribute updates, one nucRefresh bump runs the update (calling it directly taints).
local function configure(header)
    local info = headerInfo[header]
    if info then header:SetAttribute("_ignore", "attributeChanges") end
    local ok, err = pcall(configureInner, header)
    if info then
        -- The header keeps old anchors (diagonal frames): clear them, the update sets them again.
        if ok and not InCombatLockdown() then
            forChildren(header, function(child) child:ClearAllPoints() end)
        end
        header:SetAttribute("_ignore", nil)
        header:SetAttribute("nucRefresh", (header:GetAttribute("nucRefresh") or 0) + 1)
        if ok and not InCombatLockdown() then applyChildSize(header) end
    end
    if not ok then geterrorhandler()(err) end
end

syncGroupHeaders = function()
    if RG.Active() then createGroupHeaders() end
    for g = 2, 8 do
        local h = N.headers["raidG" .. g]
        if h then configure(h) end
    end
end

-- Party and raid frames swap places when a group turns into a raid: hosted frames follow.
local hostedWas = {}
local function refreshHosted()
    for key in pairs(HOSTED) do
        local header = N.headers[key]
        local host = hostFor(key, N.db[key])
        if header and host ~= hostedWas[key] then
            hostedWas[key] = host
            configure(header)
        end
    end
end

function HG.RefreshAttach()
    N.RunWhenSafe(function()
        refreshHosted()
        if N.db.groupPets.enabled and N.db.groupPets.attachEnabled and N.headers.groupPetsAttached then
            layoutAttachedPets(N.headers.groupPetsAttached)
        end
        if N.headers.ownPet and N.db.ownPet.attachEnabled then
            configurePetContainer(N.headers.ownPet)
        end
    end, "pet-attach")
end

local applyVisibility

local function createHeader(key)
    local name = "NucleusHeader" .. (key:gsub("^%l", string.upper))
    if key == "ownPet" or key == "npc" or key == "spotlight" then
        local c = CreateFrame("Frame", name, UIParent)
        c.groupKey = key
        c:SetMovable(true)
        c:SetClampedToScreen(true)
        c.buttons = {}
        local slots = (key == "npc" and NPC_SLOTS) or (key == "spotlight" and N.SPOTLIGHT_MAX) or 1
        for i = 1, slots do
            local b = CreateFrame("Button", name .. "UnitButton" .. i, c, "SecureUnitButtonTemplate")
            b:SetAttribute("*type1", "target")
            b:SetAttribute("*type2", "togglemenu")
            if key == "ownPet" then b:SetAttribute("unit", "pet") end
            b:Hide()
            c.buttons[i] = b
        end
        if key == "npc" then
            c.bossButtons = {}
            for i = 1, 8 do
                local b = CreateFrame("Button", name .. "UnitButton" .. (NPC_SLOTS + i), c, "SecureUnitButtonTemplate")
                b:SetAttribute("*type1", "target")
                b:SetAttribute("*type2", "togglemenu")
                b:SetAttribute("unit", "boss" .. i)
                RegisterStateDriver(b, "visibility", "[@boss" .. i .. ",help,exists] show; hide")
                c.bossButtons[i] = b
            end
        end
        N.headers[key] = c
        configurePetContainer(c)
        applyVisibility(c)
        if N.Layout_MakeAnchor then N.Layout_MakeAnchor(key) end
        C_Timer.After(0, function() if N.ClickCasting then N.ClickCasting.ApplyToAll() end end)
        return c
    end
    local template = (key == "groupPets") and "SecureGroupPetHeaderTemplate" or "SecureGroupHeaderTemplate"
    -- The visibility driver goes on the holder, never the header (it tainted the update in combat).
    local holder
    if key == "party" or key == "raid" then
        holder = CreateFrame("Frame", name .. "Holder", UIParent, "SecureFrameTemplate")
        holder:SetAllPoints(UIParent)
    end
    local header = CreateFrame("Frame", name, holder or UIParent, template)
    headerInfo[header] = { key = key, holder = holder }
    header:SetMovable(true)
    header:SetClampedToScreen(true)

    N.headers[key] = header
    configure(header)

    -- Create all children now, out of combat: one born in combat would run our styling mid-update.
    local perColumn = tonumber(header:GetAttribute("unitsPerColumn")) or 5
    local columns = tonumber(header:GetAttribute("maxColumns")) or 1
    header:SetAttribute("startingIndex", -(perColumn * columns))
    header:Show()
    header:SetAttribute("startingIndex", 1)
    applyChildSize(header)
    styleChildren(header)
    applyVisibility(header)
    if N.Layout_MakeAnchor then N.Layout_MakeAnchor(key) end
    return header
end

applyVisibility = function(header)
    if N.profileHidden then
        if N.HeaderKey(header) == "ownPet" then
            RegisterStateDriver(header.buttons[1], "visibility", "hide")
        elseif N.HeaderKey(header) == "groupPets" then
            applyGroupPetsMode()
        elseif N.HeaderKey(header) == "npc" or N.HeaderKey(header) == "spotlight" then
            header:Hide()
        else
            RegisterStateDriver(N.HeaderHolder(header) or header, "visibility", "hide")
        end
        return
    end
    local key = N.HeaderKey(header)
    if key == "ownPet" then
        header:Show()
        RegisterStateDriver(header.buttons[1], "visibility", "[@pet,exists] show; hide")
        return
    elseif key == "npc" or key == "spotlight" then
        header:Show()
        return
    elseif key == "groupPets" then
        applyGroupPetsMode()
        return
    end
    local solo = N.db[key].showSolo and "show" or "hide"
    local target = N.HeaderHolder(header) or header
    if key == "party" then
        RegisterStateDriver(target, "visibility",
            "[group:raid] hide; [group] show; " .. solo)
    else
        RegisterStateDriver(target, "visibility", "[group:raid] show; " .. solo)
    end
end

function HG.Init()
    for _, key in ipairs({ "party", "raid", "ownPet", "groupPets", "npc", "spotlight" }) do
        if N.db[key].enabled then
            -- A login or /reload in combat: secure headers are only made once the combat is over.
            N.RunWhenSafe(function()
                if not N.headers[key] then createHeader(key) end
            end, "create-" .. key)
        end
    end

    local rosterFrame = CreateFrame("Frame")
    N.SafeRegister(rosterFrame, "GROUP_ROSTER_UPDATE")
    N.SafeRegister(rosterFrame, "PLAYER_ENTERING_WORLD")
    N.SafeRegister(rosterFrame, "PLAYER_REGEN_ENABLED")
    local lastFilter
    local rosterDirtyInCombat = false
    rosterFrame:SetScript("OnEvent", function(_, event)
        -- Restyling touches secure children: not in combat, afterwards only if the roster changed.
        if InCombatLockdown() then
            if event == "GROUP_ROSTER_UPDATE" then rosterDirtyInCombat = true end
        elseif event ~= "PLAYER_REGEN_ENABLED" or rosterDirtyInCombat then
            rosterDirtyInCombat = false
            for _, header in pairs(N.headers) do
                styleChildren(header)
            end
        end
        if companionsMoved() then
            local sig = tostring(partyNameFilter())
            if sig ~= lastFilter then
                lastFilter = sig
                N.RunWhenSafe(function()
                    if N.headers.npc then configure(N.headers.npc) end
                    if N.headers.party then configure(N.headers.party) end
                end, "npc-roster")
            end
        end
    end)
    rosterFrame:HookScript("OnEvent", function()
        if N.db.spotlight and N.db.spotlight.enabled and N.headers.spotlight then
            N.RunWhenSafe(function()
                local header = N.headers.spotlight
                if header and table.concat(spotlightUnits(), ",") ~= header._spotlightSig then
                    configure(header)
                end
            end, "spotlight-roster")
        end
    end)
    local lastInRaid
    rosterFrame:HookScript("OnEvent", function()
        local r = IsInRaid() and true or false
        if r ~= lastInRaid then
            lastInRaid = r
            local npc = N.headers.npc
            if npc and N.db.npc.attachEnabled then
                N.RunWhenSafe(function() configure(npc) end, "npc-attach")
            end
        end
    end)
    N.SafeRegister(rosterFrame, "UNIT_NAME_UPDATE")
    N.SafeRegister(rosterFrame, "PLAYER_ROLES_ASSIGNED")
    local lastOrder = {}
    rosterFrame:HookScript("OnEvent", function()
        for _, key in ipairs({ "party", "raid" }) do
            local header = N.headers[key]
            if header then
                local sig = tostring(customNameList(key))
                if sig ~= lastOrder[key] then
                    lastOrder[key] = sig
                    N.RunWhenSafe(function() configure(header) end, "order-" .. key)
                end
            end
        end
    end)
    rosterFrame:HookScript("OnEvent", function()
        if N.headers.raid and RG.Active() and not N.headers.raidG2 and not InCombatLockdown() then
            N.RunWhenSafe(function() configure(N.headers.raid) end, "raid-groups")
        end
    end)
    rosterFrame:HookScript("OnEvent", function()
        HG.RefreshAttach()
        C_Timer.After(0.5, HG.RefreshAttach)
    end)
end

N:On("NUCLEUS_SETTING_CHANGED", function(_, section, path)
    if not N.GROUP_KEYS[section] then return end
    if path and (path:find("%.indicators%.") or path:find("%.appearance%.") or path:find("%.auras%.") or path:find("%.customIndicators")) then return end

    if section == "npc" and N.headers.party then
        N.RunWhenSafe(function() configure(N.headers.party) end, "configure-party-npc")
    end

    if not N.headers[section] and N.db[section].enabled then
        N.RunWhenSafe(function() createHeader(section) end, "create-" .. section)
        return
    end

    local header = N.headers[section]
    if header then
        if path == section .. ".enabled" then
            if N.db[section].enabled then
                N.RunWhenSafe(function() applyVisibility(header); configure(header) end, "reenable-" .. section)
            else
                N.RunWhenSafe(function()
                    local target = N.HeaderHolder(header) or header
                    UnregisterStateDriver(target, "visibility")
                    target:Hide()
                    -- Group pets hanging on their owners live in a container of their own.
                    if section == "groupPets" and N.headers.groupPetsAttached then
                        N.headers.groupPetsAttached:Hide()
                    end
                end, "hide-" .. section)
            end
            return
        end
        if path and path:find("%.showSolo$") then
            applyVisibility(header)
        end
        N.RunWhenSafe(function() configure(header) end, "configure-" .. section)
    end
    N.RunWhenSafe(N.RefreshAllButtons, "refresh-buttons")
end)

-- /nucsize: configured vs real size of the first frame.
local function sizeText(v)
    local ok, r = pcall(tostring, v)
    return ok and r or "?"
end
SLASH_NUCLEUSSIZE1 = "/nucsize"
SlashCmdList.NUCLEUSSIZE = function()
    for _, key in ipairs({ "party", "raid" }) do
        local h, cfg = N.headers[key], N.db[key]
        local child = h and _G[h:GetName() .. "UnitButton1"]
        if child then
            N:Print(key, "| set:", sizeText(cfg.width), "x", sizeText(cfg.height), "| frame:",
                sizeText(child:GetWidth()), "x", sizeText(child:GetHeight()), "| header:",
                sizeText(h:GetWidth()), "x", sizeText(h:GetHeight()))
            for i = 1, child:GetNumPoints() do
                local p, rel, rp, x, y = child:GetPoint(i)
                N:Print("  anchor", i, sizeText(p), "->", sizeText(rel and rel.GetName and rel:GetName() or rel),
                    sizeText(rp), sizeText(x), sizeText(y))
            end
        end
    end
end

-- /nucorder: what the custom order produced for the raid and why (for bug reports).
SLASH_NUCLEUSORDER1 = "/nucorder"
SlashCmdList.NUCLEUSORDER = function()
    local h = N.headers.raid
    N:Print("order enabled:", tostring(N.db.raid.ordering and N.db.raid.ordering.enabled),
        "| first/second/third:", tostring(N.db.raid.ordering and N.db.raid.ordering.first),
        tostring(N.db.raid.ordering and N.db.raid.ordering.second), tostring(N.db.raid.ordering and N.db.raid.ordering.third))
    N:Print("computed list:", tostring(customNameList("raid")))
    if h then
        N:Print("header sortMethod:", tostring(h:GetAttribute("sortMethod")), "| groupBy:", tostring(h:GetAttribute("groupBy")),
            "| nameList:", tostring(h:GetAttribute("nameList")))
        N:Print("reverse growth:", tostring(N.db.raid.reverse), "| orientation:", tostring(N.db.raid.orientation),
            "| unitsPerColumn:", tostring(h:GetAttribute("unitsPerColumn")))
    end
    for i = 1, GetNumGroupMembers() do
        local u = "raid" .. i
        if UnitExists(u) then N:Print(i, GetUnitName(u, true), UnitGroupRolesAssigned(u)) end
    end
    if h then
        for i = 1, 10 do
            local child = _G[h:GetName() .. "UnitButton" .. i]
            if child and child:IsShown() then
                local top, left = child:GetTop(), child:GetLeft()
                N:Print("child", i, tostring(child:GetAttribute("unit")),
                    (function() local bb = N.UnitFrame.ButtonOf(child); return bb and bb.unit and GetUnitName(bb.unit, true) or "?" end)(),
                    ("top=%s left=%s"):format(top and math.floor(top) or "?", left and math.floor(left) or "?"))
            end
        end
    end
end

-- /nuctaint: last blocked action plus insecure header fields.
do
    local events, blocked = {}, {}
    local function note(text)
        events[#events + 1] = ("%.1f %s"):format(GetTime(), text)
        if #events > 12 then table.remove(events, 1) end
    end
    local watcher = CreateFrame("Frame")
    for _, e in ipairs({ "ADDON_ACTION_BLOCKED", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_DISABLED",
        "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD" }) do
        N.SafeRegister(watcher, e)
    end
    watcher:SetScript("OnEvent", function(_, event, addon, func)
        if event == "ADDON_ACTION_BLOCKED" then
            if addon == "Nucleus" then
                blocked[#blocked + 1] = ("%.1f %s | combat=%s | secure=%s"):format(GetTime(),
                    tostring(func), tostring(InCombatLockdown()), tostring(issecure()))
                if #blocked > 5 then table.remove(blocked, 1) end
            end
        else
            note(event .. (InCombatLockdown() and " (combat)" or ""))
        end
    end)

    local function scan(label, t)
        local bad = {}
        for k in pairs(t) do
            if not issecurevariable(t, k) then bad[#bad + 1] = tostring(k) end
        end
        if #bad > 0 then N:Print(label, "insecure fields:", table.concat(bad, ", ")) end
    end

    SLASH_NUCLEUSTAINT1 = "/nuctaint"
    SlashCmdList.NUCLEUSTAINT = function()
        N:Print("combat:", tostring(InCombatLockdown()), "| group:", tostring(IsInGroup()),
            "| raid:", tostring(IsInRaid()))
        for key, h in pairs(N.headers or {}) do
            scan(key, h)
            local i, child = 1, _G[h:GetName() .. "UnitButton1"]
            while child do
                scan(key .. " child " .. i, child)
                i = i + 1
                child = _G[h:GetName() .. "UnitButton" .. i]
            end
        end
        N:Print("recent events:")
        for _, line in ipairs(events) do N:Print("  " .. line) end
        N:Print("blocked actions (" .. #blocked .. "):")
        for _, line in ipairs(blocked) do N:Print("  " .. line) end
    end
end

-- /nuctaintlog [on|off] [level]: taint log; level 2 logs most but raises extra errors.
SLASH_NUCLEUSTAINTLOG1 = "/nuctaintlog"
SlashCmdList.NUCLEUSTAINTLOG = function(msg)
    local word, level = strsplit(" ", strlower(strtrim(msg or "")))
    local want
    if word == "on" then want = true
    elseif word == "off" then want = false
    else want = (tonumber(GetCVar("taintLog")) or 0) == 0 end
    SetCVar("taintLog", want and (tonumber(level) == 1 and 1 or 2) or 0)
    if want then
        N:Print("taint log ON. Type /reload, play until the error appears, then post the Nucleus lines of "
            .. "World of Warcraft/_retail_/Logs/taint.log. Switch it off again with /nuctaintlog off")
    else
        N:Print("taint log off")
    end
end
