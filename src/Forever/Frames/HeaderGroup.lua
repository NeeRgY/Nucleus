local _, ns = ...
local N = ns.N

-- Secure group headers. Blizzard's SecureGroupHeaderTemplate owns child
-- creation, visibility and unit assignment; Nucleus only feeds it attributes
-- (out of combat) and skins each child once via CallMethod.

local HG = {}
N.HeaderGroup = HG
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
    local w, h = N.db[header.groupKey].width, N.db[header.groupKey].height
    forChildren(header, function(child) child:SetSize(w, h) end)
end

-- Style + bind every child. The initialConfigFunction already does this via
-- CallMethod for freshly created children; this is the belt-and-braces pass
-- that also runs on roster/zone events and right after (re)configuration.
-- Wrapped so a single bad child can't abort header setup.
local function styleChildren(header)
    forChildren(header, function(child)
        local ok, err = pcall(function()
            N.StyleUnitButton(child:GetName())
            if child.NucleusBind then child:NucleusBind() end
        end)
        if not ok then N:Print("|cffff5555style error:|r " .. tostring(err)) end
    end)
end
HG.StyleChildren = styleChildren

local CLASS_ORDER = table.concat(N.Classic.CLASSES, ",") -- Forever: the nine Classic classes

-- Translate the orientation/reverse settings into the header anchor attributes.
-- vertical  = unit rows stacked, extra groups form columns to the right.
-- horizontal = unit columns side by side, extra groups stack downward.
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

--------------------------------------------------------------------------------
-- Pets / companions
--------------------------------------------------------------------------------

local NPC_SLOTS = 4

-- A party member that is an NPC companion (Brann in Delves, follower dungeons).
local function isNpcUnit(unit)
    return UnitExists(unit) and UnitInPartyIsAI and UnitInPartyIsAI(unit) and true or false
end

-- While the NPC frames are on, party members that are NPCs leave the party
-- frames: the header is given an explicit name list without them. Returns nil
-- when nothing needs filtering (no NPC in the group, or the feature is off).
local function partyNameFilter()
    if not (N.db.npc and N.db.npc.enabled) or IsInRaid() then return nil end
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

-- Spotlight: the units its entries stand for right now (out of combat only - it reads
-- the roster and the assigned roles). "target" / "focus" stay tokens of their own, the
-- rest become the group member's raid / party token.
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

-- Custom order (Appearance > Layout > Sorting) -------------------------------------
-- The game's group header can sort by role or class, but cannot put chosen people
-- first. So when a custom order is wanted, the whole roster is ordered here and
-- handed to the header as an explicit name list (sortMethod NAMELIST). That only
-- changes outside combat, like every header attribute.

-- Returns the rank of each role (1 = first) and the pinned names, or nil when
-- the custom order is off.
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
-- Raid groups the player wants frames for (Layout > Raid groups).
local function raidGroupAllowed(group)
    local raid = N.db.raid
    if raid and type(raid.maxGroups) == "number" and group > raid.maxGroups then return false end
    local gf = raid and raid.groupFilter
    return not (type(gf) == "table" and gf[group] == false)
end

-- nil when the default (native) ordering is wanted, else the ordered name list.
local function customNameList(key)
    local rank, pins = sortConfig(key)
    if not rank then return nil end

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

    local npcOut = key == "party" and N.db.npc and N.db.npc.enabled
    local list = {}
    local inRaid = key == "raid" and IsInRaid()
    for i, u in ipairs(units) do
        local group = inRaid and select(3, GetRaidRosterInfo(i)) or nil
        if UnitExists(u) and not (npcOut and isNpcUnit(u)) and (not group or raidGroupAllowed(group)) then
            local full = GetUnitName(u, true)
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

-- Attaching pets to their owner's frame ---------------------------------------

local SIDES = {
    RIGHT = { "TOPLEFT", "TOPRIGHT" }, LEFT = { "TOPRIGHT", "TOPLEFT" },
    TOP = { "BOTTOMLEFT", "TOPLEFT" }, BOTTOM = { "TOPLEFT", "BOTTOMLEFT" },
}

-- The unit button currently showing `ownerUnit` ("party2", "raid7", "player").
local function findOwnerButton(ownerUnit)
    for pass = 1, 2 do
        for _, key in ipairs({ "party", "raid" }) do
            local h = N.headers[key]
            if h and h:IsShown() then
                local i, child = 1, _G[h:GetName() .. "UnitButton1"]
                while child do
                    if child:IsShown() then
                        local u = child:GetAttribute("unit")
                        if u == ownerUnit then return child end
                        -- The player is "playerN" / "raidN" depending on the header.
                        if pass == 2 and ownerUnit == "player" and u and UnitIsUnit(u, "player") then
                            return child
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

-- Pets of group members, each bound to its owner's frame: one secure button per
-- possible pet (party1-4 / raid1-40); each shows itself while its pet exists.
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
            b:SetAlpha(0) -- no frame to sit next to
        end
    end
    styleChildren(c)
end

-- groupPets has two forms: the normal pet header, or the attached buttons.
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
        -- Party-member companions first (slots assigned here, out of combat),
        -- then the friendly boss-unit NPCs (shown by a secure unit condition).
        local units = {}
        for i = 1, 4 do
            if isNpcUnit("party" .. i) then units[#units + 1] = "party" .. i end
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
        -- One slot per chosen unit; a slot shows itself only while its unit exists.
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
    container:SetPoint(cfg.point, UIParent, cfg.point, cfg.x, cfg.y)
    styleChildren(container)
end

-- Push the full attribute set from SavedVariables onto the header. Must run
-- outside combat; SecureGroupHeader_Update relays it to the children.
local function configure(header)
    local key = header.groupKey
    local cfg = N.db[key]
    if key == "ownPet" or key == "npc" or key == "spotlight" then
        configurePetContainer(header)
        return
    end

    header:SetAttribute("template", "SecureUnitButtonTemplate")
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
        header:SetAttribute("sortMethod", "INDEX")
        header:SetAttribute("nameList", nil)
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

        if cfg.groupBy == "GROUP" then
            header:SetAttribute("groupBy", "GROUP")
            header:SetAttribute("groupingOrder", "1,2,3,4,5,6,7,8")
            header:SetAttribute("unitsPerColumn", 5)
        elseif cfg.groupBy == "CLASS" then
            header:SetAttribute("groupBy", "CLASS")
            header:SetAttribute("groupingOrder", CLASS_ORDER)
        elseif cfg.groupBy == "ROLE" then
            header:SetAttribute("groupBy", "ASSIGNEDROLE")
            header:SetAttribute("groupingOrder", "TANK,HEALER,DAMAGER,NONE")
        else
            header:SetAttribute("groupBy", nil)
            header:SetAttribute("groupingOrder", nil)
        end

        -- Only the chosen raid groups (the explicit name list below does its own filtering).
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

    header:ClearAllPoints()
    header:SetPoint(cfg.point, UIParent, cfg.point, cfg.x, cfg.y)

    if SecureGroupHeader_Update then
        SecureGroupHeader_Update(header)
    end
    applyChildSize(header)
    styleChildren(header)
    -- Child creation can lag a frame behind the attribute write.
    C_Timer.After(0, function() styleChildren(header) end)
    if key == "groupPets" then applyGroupPetsMode() end
end

-- Re-anchor the attached pet frames to their owners (roster / layout changes).
function HG.RefreshAttach()
    N.RunWhenSafe(function()
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
        -- One plain container with its own secure unit buttons: the pet is
        -- always "pet", NPC companions are party1-4 (assigned as they appear).
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
            -- Friendly NPCs the game exposes as boss units (escorts, allies in
            -- encounters). Each button shows itself while its unit is friendly.
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
    -- Party / raid headers sit inside a plain holder frame: the show/hide state
    -- driver goes on the holder, never on the header itself (the header then
    -- re-reads the roster when the holder is shown). A driver on the header made
    -- the game's own header update run tainted in combat and get blocked.
    local holder
    if key == "party" or key == "raid" then
        holder = CreateFrame("Frame", name .. "Holder", UIParent, "SecureFrameTemplate")
        holder:SetAllPoints(UIParent)
    end
    local header = CreateFrame("Frame", name, holder or UIParent, template)
    header.holder = holder
    header.groupKey = key
    header:SetMovable(true)
    header:SetClampedToScreen(true)

    function header:StyleChild(childName)
        N.StyleUnitButton(childName)
    end

    N.headers[key] = header
    configure(header)

    -- Have the header create every child it could ever need now, out of combat.
    -- A child born inside the header's own update during combat runs our insecure
    -- styling in the middle of it, and the game then blocks that update (the
    -- SetPoint on the first child).
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

-- Show/hide is driven securely so it also works during combat lockdown.
applyVisibility = function(header)
    -- An auto-switch rule can hide the frames outright for a situation.
    if N.profileHidden then
        if header.groupKey == "ownPet" then
            RegisterStateDriver(header.buttons[1], "visibility", "hide")
        elseif header.groupKey == "groupPets" then
            applyGroupPetsMode()
        elseif header.groupKey == "npc" or header.groupKey == "spotlight" then
            header:Hide()
        else
            RegisterStateDriver(header.holder or header, "visibility", "hide")
        end
        return
    end
    local key = header.groupKey
    if key == "ownPet" then
        -- The pet button shows only while a pet exists; the container (and with
        -- it the drag handle) stays up.
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
    local target = header.holder or header
    if key == "party" then
        RegisterStateDriver(target, "visibility",
            "[@raid6,exists] hide; [group] show; " .. solo)
    else
        RegisterStateDriver(target, "visibility", "[group:raid] show; " .. solo)
    end
end

function HG.Init()
    for _, key in ipairs({ "party", "raid", "ownPet", "groupPets", "npc", "spotlight" }) do
        if N.db[key].enabled then
            createHeader(key)
        end
    end

    -- Re-style whenever the header may have (re)built its children.
    local rosterFrame = CreateFrame("Frame")
    rosterFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    rosterFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    rosterFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    local lastFilter
    rosterFrame:SetScript("OnEvent", function()
        for _, header in pairs(N.headers) do
            styleChildren(header)
        end
        -- NPC companions: reassign their frames and re-filter the party frames
        -- (only when the NPC list actually changed).
        if N.db.npc and N.db.npc.enabled then
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
    rosterFrame:RegisterEvent("UNIT_NAME_UPDATE")
    rosterFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
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
        HG.RefreshAttach()
        C_Timer.After(0.5, HG.RefreshAttach) -- the headers assign units a moment later
    end)
end

-- React to option changes. Section is "party" / "raid" / "general" / ...
-- Indicator and appearance sub-keys are handled by their own modules; the
-- header only cares about layout / size / visibility.
N:On("NUCLEUS_SETTING_CHANGED", function(_, section, path)
    if not N.GROUP_KEYS[section] then return end
    if path and (path:find("%.indicators%.") or path:find("%.appearance%.") or path:find("%.auras%.") or path:find("%.customIndicators")) then return end

    -- The NPC frames decide what the party frames list.
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
                    local target = header.holder or header
                    UnregisterStateDriver(target, "visibility")
                    target:Hide()
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
